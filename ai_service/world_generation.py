"""Versioned, deterministic world pipeline. No AI/network services are needed.

The existing planar street/parcel builder is reused. Every accepted attempt is
validated; saved worlds carry the complete immutable layout, not only a seed.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import random
from collections import defaultdict
from pathlib import Path

from shapely import LineString, Point, Polygon, box, unary_union
from shapely.strtree import STRtree

from . import city_generator as city
from .generation_pipeline import ArtifactCache
from .world_stages import make_pipeline
from .tile_world import CONFIG as TILE_CONFIG, TILE_SIZE

CONFIG = json.loads((Path(__file__).resolve().parents[1] / 'resources/world_generation.json').read_text())
FORMAT = CONFIG['format_version']
VERSION = CONFIG['generator_version']
STREAMS = ('terrain', 'roads', 'districts', 'buildings', 'vegetation', 'vehicles', 'props', 'shelters')
CAPACITIES = dict(S1=2500, S2=750, S3=1800, S4=3500, S5=5000)


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(encode(value).encode()).hexdigest()


def stream_seed(seed, name, attempt=0):
    return int.from_bytes(hashlib.sha256(f'essaim-world-1:{seed}:{name}:{attempt}'.encode()).digest()[:8], 'big') & 0x7fffffff


def settings_for(preset='medium', **overrides):
    if preset not in CONFIG['presets']:
        raise ValueError('Unknown city preset')
    allowed={'district_density', 'vegetation_density', 'road_width_multiplier', 'straight_road_ratio'}
    if set(overrides)-allowed:
        raise ValueError('Unknown generation setting')
    result=copy.deepcopy(CONFIG['presets'][preset])
    result['district_count']={'small':7,'medium':8,'large':10,'very_large':12}[preset]
    result.update(preset=preset, road_width_multiplier=1.0,
                  straight_road_ratio=CONFIG.get('straight_road_ratio',0.7))
    result.update(overrides)
    for key,low,high in [('district_density',.5,1.5),('vegetation_density',0,2),('road_width_multiplier',.75,1.5),('straight_road_ratio',0,1)]:
        value=result[key]
        if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or not low<=value<=high:
            raise ValueError(f'Invalid {key}: expected {low} through {high}')
    # Density changes counts, without altering which district names are available.
    result['max_buildings']=round(result['max_buildings']*result['district_density'])
    return result


def _decorate(layout, streams, settings):
    roads=[r for r in layout['roads'] if not r.get('elevated') and not r.get('ramp')]
    corridors=unary_union([LineString(r['points']).buffer(r['width']/2+r['sidewalk']+30) for r in roads])
    reserved=[box(*city._rect_bounds(b['rect'])).buffer(30) for b in layout['buildings']]
    reserved += [box(*city._rect_bounds(p['bounds'])).buffer(30) for p in layout['shelter_access'].values()]
    reserved += [box(*city._rect_bounds(p['bounds'])).buffer(30) for p in layout['parking_lots']]
    reserved += [box(*city._rect_bounds(layout['lake'])).buffer(30)]
    reserved += [Point(layout['grove']['gathering']).buffer(100)]
    reserved += [Polygon(b['municipal_block']) for b in layout['buildings'] if 'municipal_block' in b]
    reserved += [LineString(b['access_path']).buffer(20) for b in layout['buildings'] if 'access_path' in b]
    reserved += [LineString(b['driveway']).buffer(20) for b in layout['buildings'] if 'driveway' in b]
    # Reserve the real entrance connectors, not only their endpoints.
    reserved += [LineString([p['road_entry'],p['position']]).buffer(35) for p in layout['shelter_access'].values()]
    excluded=unary_union([corridors]+reserved)
    w,h=layout['size']; rng=random.Random(streams['vegetation'])
    trees=[]; occupied=[]; tree_cells=defaultdict(list); object_cells=set()
    target=round((w*h/(9500*5900))*1800*settings['vegetation_density'])
    for _ in range(target*15):
        if len(trees)>=target: break
        p=(rng.uniform(60,w-60),rng.uniform(60,h-60))
        tile_cell=(int(p[0]//TILE_SIZE),int(p[1]//TILE_SIZE))
        if tile_cell in object_cells: continue
        cell=(int(p[0]//45),int(p[1]//45))
        if excluded.intersects(Point(p)) or any(math.dist(p,q)<45 for x in range(cell[0]-1,cell[0]+2) for y in range(cell[1]-1,cell[1]+2) for q in tree_cells[(x,y)]): continue
        tree_cells[cell].append(p); object_cells.add(tile_cell)
        trees.append(dict(position=p,scale=rng.uniform(.7,1.65),variant=rng.randrange(3)))
        occupied.append(p)
    rng=random.Random(streams['props']); props=[]
    for _ in range(settings['max_props']*30):
        if len(props)>=settings['max_props']: break
        p=(rng.uniform(70,w-70),rng.uniform(h*.2,h-70))
        tile_cell=(int(p[0]//TILE_SIZE),int(p[1]//TILE_SIZE))
        if tile_cell in object_cells or excluded.intersects(Point(p)) or any(math.dist(p,q)<40 for q in occupied): continue
        object_cells.add(tile_cell)
        props.append(dict(position=p,variant=rng.choice(['debris','crate','construction']),rotation=rng.uniform(0,math.tau)))
        occupied.append(p)
    rng=random.Random(streams['vehicles'])
    spawns=[dict(bay_id=b['id'],position=b['position'],heading=b['heading'],variant=rng.randrange(6))
            for p in layout['parking_lots'] for b in p['bays']]
    rng.shuffle(spawns)
    rng=random.Random(streams['buildings'])
    for b in layout['buildings']:
        b['asset_variant']=rng.randrange(6)
        b['weathering']=rng.uniform(.05,.85)
    layout.update(vegetation=trees,environment_props=props,vehicle_spawns=spawns)
    from .tile_world import manifest
    layout["tile_world"]=manifest(layout,layout.get("tile_world",{}).get("rejected_placements",0))


def validate_layout(layout):
    """Revalidate untrusted saved geometry; never trust its stored valid flag."""
    report=city.validate(layout)
    errors=list(report['errors'])
    directed=defaultdict(set)
    for edge in layout['roads']:
        a,b=edge['from'],edge['to']
        direction=edge.get('direction','both')
        if direction in ('both','forward'): directed[a].add(b)
        if direction in ('both','reverse'): directed[b].add(a)
    reached=set(); todo=[0]
    while todo:
        node=todo.pop()
        if node in reached: continue
        reached.add(node); todo.extend(directed[node]-reached)
    if len(reached)!=len(layout['nodes']): errors.append('Disconnected directed vehicle network')
    incoming=defaultdict(set)
    for a,neighbors in directed.items():
        for b in neighbors: incoming[b].add(a)
    reached=set(); todo=[0]
    while todo:
        node=todo.pop()
        if node in reached: continue
        reached.add(node); todo.extend(incoming[node]-reached)
    if len(reached)!=len(layout['nodes']): errors.append('Vehicle network has no return route')
    w,h=layout['size']
    if len(layout['nodes'])>20000 or len(layout['roads'])>30000 or len(layout['buildings'])>5000:
        errors.append('World exceeds runtime limits')
    buildings=[box(*city._rect_bounds(b['rect'])) for b in layout['buildings']]
    lake=box(*city._rect_bounds(layout['lake']))
    tree=STRtree(buildings)
    lines=[LineString(r['points']) for r in layout['roads']]
    road_tree=STRtree(lines)
    for id,p in layout['shelter_access'].items():
        connector=LineString([p['road_entry'],p['position']])
        if connector.intersects(lake) or len(tree.query(connector.buffer(12),predicate='intersects')):
            errors.append('Obstructed shelter entrance connector')
        if not box(0,0,w,h).contains(Point(p['position'])): errors.append('Shelter outside map')
    for poi in layout['pois']:
        point=Point(poi['position'])
        if point.distance(lines[int(road_tree.nearest(point))])>.02:
            errors.append('Public infrastructure lacks road access')
    # Every frontage has a walkable exit and lies within a bounded road distance.
    for b in layout['buildings']:
        point=box(*city._rect_bounds(b['rect'])).centroid
        if point.distance(lines[int(road_tree.nearest(point))])>600:
            errors.append('Building has no street access')
    ground=[r for r in layout['roads'] if not r.get('elevated') and not r.get('ramp')]
    corridors=unary_union([LineString(r['points']).buffer(r['width']/2+r['sidewalk']+12) for r in ground])
    for item in layout.get('vegetation',[])+layout.get('environment_props',[]):
        p=Point(item['position'])
        if corridors.intersects(p) or len(tree.query(p.buffer(12),predicate='intersects')):
            errors.append('Environmental object blocks road or building')
    bays={b['id']:b for p in layout['parking_lots'] for b in p['bays']}
    seen=set()
    for spawn in layout.get('vehicle_spawns',[]):
        bay=bays.get(spawn['bay_id'])
        if bay is None or spawn['bay_id'] in seen or math.dist(bay['position'],spawn['position'])>.01:
            errors.append('Invalid vehicle spawn inventory')
        seen.add(spawn['bay_id'])
    report.update(valid=not errors,errors=sorted(set(errors)),components=1 if report['valid'] else None)
    return report


def generate(world_seed=42, preset='medium', artifact_cache=None, **overrides):
    if isinstance(world_seed,bool) or not isinstance(world_seed,int) or not 0<=world_seed<=2147483646:
        raise ValueError('World seed must be an integer from 0 through 2147483646')
    settings=settings_for(preset,**overrides)
    failures=[]
    pipeline=make_pipeline(_decorate,validate_layout,artifact_cache,CONFIG.get('stage_priorities',{}))
    for attempt in range(CONFIG['max_attempts']):
        streams={name:stream_seed(world_seed,name,attempt) for name in STREAMS}
        rng=random.Random(streams['terrain'])
        size=[round(v*rng.uniform(.965,1.025),3) for v in settings['size']]
        pattern=random.Random(streams['roads']).choice(['organic','radial','mixed'])
        try:
            inputs={
                'geography':{'seed':streams['terrain'],'size':settings['size']},
                'districts':{'seed':streams['districts'],'count':settings['district_count']},
                'shelters':{'seed':streams['shelters']},
                'layout':{'world_seed':world_seed,'pattern':pattern,'density':settings['district_density'],
                          'city_generator_version':city.VERSION, 'tile_grid_config':TILE_CONFIG,
                          'streams':streams,'buildings':settings['max_buildings'],'parking':settings['parking_lots'],
                          'district_count':settings['district_count'],'width':settings['road_width_multiplier'],
                          'straight_road_ratio':settings['straight_road_ratio']},
                'environment':{'vegetation_version':3,'streams':streams,'settings':{'vegetation_density':settings['vegetation_density'],'max_props':settings['max_props']}}}
            layout=pipeline.run(inputs)['validation']
            exists=random.Random(streams['shelters']).random()<.5
            shelters={k:dict(capacity=v,exists=(k!='S5' or exists),hidden=(k=='S5'),
                             position=layout['shelter_access'][k]['position']) for k,v in CAPACITIES.items()}
            content=dict(format_version=FORMAT,generator_version=VERSION,world_seed=world_seed,
                settings=settings,streams=streams,attempt=attempt,layout_pattern=pattern,
                layout=layout,shelters=shelters,
                stages=pipeline.order(),
                generation_dependencies={k:dict(dependencies=list(v.dependencies),priority=v.priority,version=v.version)
                                         for k,v in pipeline.stages.items()})
            content['content_hash']=digest(content)
            content['world_id']=f'essaim-{world_seed}-{content["content_hash"][:16]}'
            return content
        except ValueError as exc:
            failures.append(str(exc))
    raise ValueError('Deterministic generation attempts exhausted: '+' | '.join(failures))


def validate_world(data):
    if data.get('format_version')!=FORMAT or data.get('generator_version') not in ('essaim-world-1','essaim-world-2','essaim-world-3',VERSION):
        raise ValueError('Unsupported saved world version; use its original generator or an explicit migration')
    content={k:v for k,v in data.items() if k not in ('content_hash','world_id')}
    if digest(content)!=data.get('content_hash'):
        raise ValueError('Saved world checksum mismatch')
    if data['world_id']!=f'essaim-{data["world_seed"]}-{data["content_hash"][:16]}':
        raise ValueError('Saved world identity mismatch')
    if data['layout']['terrain']['formula_version']!=1:
        raise ValueError('Unsupported terrain formula')
    for k,capacity in CAPACITIES.items():
        if data['shelters'][k]['capacity']!=capacity or (k!='S5' and not data['shelters'][k]['exists']):
            raise ValueError('Incompatible shelter scenario')
    report=validate_layout(data['layout'])
    if not report['valid']: raise ValueError('; '.join(report['errors']))
    return data


def save_world(data,path):
    validate_world(data)
    target=Path(path); target.parent.mkdir(parents=True,exist_ok=True)
    temporary=target.with_suffix(f'.{__import__("os").getpid()}.tmp')
    temporary.write_text(encode(data),encoding='utf-8'); temporary.replace(target)


def load_world(path):
    if Path(path).stat().st_size>50_000_000: raise ValueError('World file exceeds 50 MB')
    return validate_world(json.loads(Path(path).read_text(encoding='utf-8-sig')))


def main():
    import sys
    request=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    import os
    progress=request.pop("progress_path",None)
    if progress: os.environ["ESSAIM_PROGRESS_FILE"]=progress
    target=Path(sys.argv[2])
    if 'load_path' in request:
        save_world(load_world(request['load_path']),target)
        return
    # Request/version cache avoids recomputing a world for UI repeats.
    key=digest(dict(version=VERSION,city_version=city.VERSION,configuration=CONFIG,request=request))
    marker=target.with_suffix('.request')
    if target.exists() and marker.exists() and marker.read_text()==key:
        try:
            load_world(target)
            return
        except (ValueError,OSError,KeyError,TypeError):
            # A corrupt cache is disposable. Explicit user loads still reject it.
            pass
    save_world(generate(**request,artifact_cache=ArtifactCache(target.parent/"stages")),target)
    marker.write_text(key)


if __name__=='__main__': main()
