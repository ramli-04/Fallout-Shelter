"""Seeded, planar city layout. Metres are 10 simulation units; no physics here.

Ground centerlines are noded BEFORE graphs, setbacks or meshes are built. Raised
highways form a separate level, connected only through explicit access ramps.
"""
from __future__ import annotations

import hashlib
import json
import math
import random
import time
from collections import defaultdict, deque
from pathlib import Path

from shapely import LineString, Point, Polygon, box, unary_union, set_precision, constrained_delaunay_triangles
from shapely.ops import nearest_points
from shapely.strtree import STRtree

VERSION = 15
BASE_SIZE = (6750.0, 4050.0)
DISTRICTS = {
    'DOWNTOWN': (.43, .45), 'INDUSTRIAL': (.16, .27),
    'RESIDENTIAL': (.23, .57), 'GROVE': (.42, .83),
    'SCHOOL': (.65, .78), 'SERVICES': (.65, .46), 'MOUNTAINS': (.86, .24),
}
COLORS = ['c9a061', '8a9fa5', '83ad77', '52a787', 'd0bc78', '82b4cf', '879471']


def rect(shape):
    a, b, c, d = shape.bounds
    return [a, b, c-a, d-b]


def curve(a, b, bend=0.0, spacing=32):
    dx, dy = b[0]-a[0], b[1]-a[1]
    length = math.hypot(dx, dy)
    steps = max(2, math.ceil(length/spacing))
    return [(a[0]+dx*i/steps-dy/max(1, length)*math.sin(math.pi*i/steps)*bend,
             a[1]+dy*i/steps+dx/max(1, length)*math.sin(math.pi*i/steps)*bend)
            for i in range(steps+1)]


def district_centers(size, district_rng, procedural=True, district_count=7):
    w,h=size
    centers = {k: (w*(u+district_rng.uniform(-.055 if procedural else -.018,.055 if procedural else .018)), h*(v+district_rng.uniform(-.035 if procedural else -.02,.035 if procedural else .02)))
               for k, (u,v) in DISTRICTS.items()}
    if procedural and district_rng.random()<.5:
        centers['INDUSTRIAL'],centers['SERVICES']=centers['SERVICES'],centers['INDUSTRIAL']
    if procedural:
        for i in range(max(0,district_count-7)):
            centers[f'RESIDENTIAL:{i}']=(w*district_rng.uniform(.18,.73),h*district_rng.uniform(.28,.72))
    return centers


def generate(seed=42, size=None, road_width_multiplier=1.0, parking_count=12,
             procedural=False, layout='organic', district_density=1.0,
             streams=None, max_buildings=100000, district_count=7, shelter_plan=None, district_plan=None,
             straight_road_ratio=0.7, **_):
    started = time.perf_counter()
    size = list(size or [v*math.sqrt(2) for v in BASE_SIZE])
    if len(size) != 2 or any(not math.isfinite(v) or v < 4000 or v > 16000 for v in size):
        raise ValueError('City dimensions must be finite, between 4000 and 16000 simulation units')
    if not .75 <= road_width_multiplier <= 1.5:
        raise ValueError('Road width multiplier must be within [0.75, 1.5]')
    if isinstance(straight_road_ratio, bool) or not isinstance(straight_road_ratio, (int, float)) or not math.isfinite(straight_road_ratio) or not 0 <= straight_road_ratio <= 1:
        raise ValueError('Straight road ratio must be within [0, 1]')
    rng = random.Random(int(seed)+610100)
    streams = streams or {}
    district_rng = random.Random(streams.get('districts', int(seed)+610101)) if procedural else rng
    shelter_rng = random.Random(streams.get('shelters', int(seed)+610102)) if procedural else rng
    road_rng = random.Random(streams.get('roads', int(seed)+610103)) if procedural else rng
    building_rng = random.Random(streams.get('buildings', int(seed)+610104)) if procedural else rng
    w, h = size
    world = box(20, 20, w-20, h-20)
    centers=dict(district_plan) if district_plan else district_centers(size,district_rng,procedural,district_count)
    grove_center = centers['GROVE']
    grove_bounds = box(grove_center[0]-650, grove_center[1]-480,
                       grove_center[0]+650, grove_center[1]+480)
    park = box(w*.08, h*.62, w*.22, h*.85)
    lake = box(w*.105, h*.69, w*.145, h*.745)
    sites = {'S1': (w*.185,h*.65), 'S2': (w*.53,h*.90),
             'S3': (w*.82,h*.78), 'S4': (w*.90,h*.40), 'S5': (w*.85,h*.12)}
    # Preserve the five shelter identities; deterministic jitter varies their approaches.
    sites = {k:(x+shelter_rng.uniform(-65,65), y+shelter_rng.uniform(-65,65)) for k,(x,y) in sites.items()}
    if procedural:
        zones={'S1':(.34,.52,.34,.57),'S2':(.47,.64,.65,.77),
               'S3':(.66,.79,.57,.72),'S4':(.86,.94,.38,.52),'S5':(.82,.93,.07,.17)}
        sites={k:(w*shelter_rng.uniform(a,b),h*shelter_rng.uniform(c,d)) for k,(a,b,c,d) in zones.items()}
    if shelter_plan:
        sites={k:tuple(p['road_entry']) for k,p in shelter_plan.items()}
    keepouts=unary_union([box(*_rect_bounds(p['bounds'])).buffer(160) for p in (shelter_plan or {}).values()])
    def district(p):
        if grove_bounds.contains(Point(p)): return 'GROVE'
        return min(centers, key=lambda k: ((p[0]-centers[k][0])/w)**2+((p[1]-centers[k][1])/h)**2).split(':')[0]
    sources = []
    def add(points, kind='residential'):
        line = set_precision(LineString(points), .001)
        if line.length > .1:
            sources.append(dict(line=line, kind=kind))
    columns = max(10, round(w/(700/math.sqrt(district_density))))
    rows = max(7, round(h/(650/math.sqrt(district_density))))
    # Shared row/column offsets preserve parallel frontage and usable blocks.
    # Smooth district-scale bends replace independent intersection jitter.
    column_offsets = [road_rng.uniform(-22,22) for _ in range(columns)]
    row_offsets = [road_rng.uniform(-18,18) for _ in range(rows)]
    nodes = {}
    for x in range(columns):
        for y in range(rows):
            u,v=x/(columns-1),y/(rows-1)
            if procedural and layout=='radial':
                angle=-math.pi*.88+u*math.pi*1.76
                radius=.14+.30*v
                p=(w*(.46+math.cos(angle)*radius),h*(.53+math.sin(angle)*radius*.90))
            else:
                bend = 0 if layout == 'mixed' else .012
                p=(w*(.045+.91*u+bend*math.sin(v*math.pi))+column_offsets[x],
                   h*(.22+.71*v+bend*math.sin(u*math.pi))+row_offsets[y])
            if not grove_bounds.buffer(100).contains(Point(p)) and not lake.buffer(100).contains(Point(p)):
                nodes[x,y] = p
    def link(a,b,kind):
        if a not in nodes or b not in nodes: return
        start, end = nodes[a], nodes[b]
        is_straight = road_rng.random() < straight_road_ratio
        if is_straight:
            points = [start,end]
        else:
            bend_limit=.025 if procedural else .02
            points = curve(start,end,road_rng.uniform(-bend_limit,bend_limit)*math.dist(start,end))
        line = LineString(points)
        if line.intersects(grove_bounds.buffer(70)) or line.intersects(lake.buffer(70)) or line.intersects(keepouts): return
        add(points,kind)
    for x,y in nodes:
        link((x,y),(x+1,y),'boulevard' if y in (1,rows//2) else 'residential')
        link((x,y),(x,y+1),'arterial' if x%4==0 else 'residential')
    roundabouts=[]
    if procedural:
        center=min(nodes.values(),key=lambda p:math.dist(p,centers['DOWNTOWN']))
        island=Point(center).buffer(130,quad_segs=12)
        if not island.buffer(120).intersects(grove_bounds) and not island.buffer(120).intersects(lake):
            clipped=[]
            for source in sources:
                difference=source['line'].difference(island)
                for line in difference.geoms if hasattr(difference,'geoms') else [difference]:
                    if line.geom_type=='LineString' and line.length>.1:
                        clipped.append(dict(line=set_precision(line,.001),kind=source['kind']))
            sources=clipped
            add(list(island.exterior.coords),'roundabout')
            roundabouts.append(dict(center=center,radius=130,island_radius=65))
    # Alder Court: an original curved suburban stem and a round dead-end turning head.
    cx, cy = grove_center
    entrance = (cx-610,cy-290)
    stem = [(cx-610,cy-290),(cx-480,cy-240),(cx-310,cy-120),(cx-110,cy-35),(cx+110,cy)]
    # Quadratic Bezier smoothing through the stem, exact endpoints retained.
    smooth = [stem[0]]
    for i in range(1,len(stem)-1):
        a = smooth[-1]
        b = stem[i]
        c = ((b[0]+stem[i+1][0])/2,(b[1]+stem[i+1][1])/2)
        for j in range(1,9):
            t=j/8
            smooth.append(((1-t)**2*a[0]+2*(1-t)*t*b[0]+t*t*c[0],
                           (1-t)**2*a[1]+2*(1-t)*t*b[1]+t*t*c[1]))
    smooth.extend(curve(smooth[-1],stem[-1]))
    add(smooth,'grove')
    bulb = Point(stem[-1]).buffer(115,quad_segs=24)
    nearest = nearest_points(Point(entrance),unary_union([r['line'] for r in sources if r['kind']!='grove']))[1]
    add(curve(entrance,nearest.coords[0],0),'residential')
    for key,p in sites.items():
        if shelter_plan:
            choices=[]
            for source in sources:
                end=nearest_points(Point(p),source['line'])[1].coords[0]
                line=LineString([p,end])
                if not line.intersects(keepouts) and not line.intersects(lake.buffer(60)):
                    choices.append((line.length,end))
            if not choices: raise ValueError(f'No unobstructed road approach to {key}')
            endpoint=min(choices)[1]
            add([p,endpoint],'mountain' if key in ('S4','S5') else 'residential')
        else:
            network = unary_union([s['line'] for s in sources])
            endpoint = nearest_points(Point(p),network)[1].coords[0]
            line = LineString(curve(p,endpoint,0))
            if line.intersects(lake.buffer(60)):
                detour=(lake.bounds[2]+130,lake.bounds[1]-130)
                add([p,detour,endpoint],'mountain' if key in ('S4','S5') else 'residential')
            else: add(line.coords,'mountain' if key in ('S4','S5') else 'residential')
    # Repair any isolated grid component before final noding (no invisible graph links).
    for _attempt in range(30):
        merged = unary_union([r['line'] for r in sources], grid_size=.001)
        parts = list(merged.geoms) if hasattr(merged,'geoms') else [merged]
        adjacency=defaultdict(set)
        def nodekey(p): return tuple(round(v,5) for v in p)
        for line in parts:
            a,b=nodekey(line.coords[0]),nodekey(line.coords[-1]); adjacency[a].add(b); adjacency[b].add(a)
        remaining=set(adjacency); components=[]
        while remaining:
            found=set(); todo=[min(remaining)]
            while todo:
                a=todo.pop()
                if a in found: continue
                found.add(a); todo.extend(adjacency[a]-found)
            remaining-=found; components.append(found)
        if len(components)==1: break
        components.sort(key=lambda c:(-len(c),min(c)))
        options=sorted((math.dist(a,b),a,b) for a in components[0] for c in components[1:] for b in c)
        for _,a,b in options:
            candidate=LineString([a,b])
            if not candidate.intersects(lake.buffer(80)) and not candidate.intersects(grove_bounds) and not candidate.intersects(keepouts):
                add([a,b],'residential'); break
        else: raise ValueError('Cannot connect district without crossing protected land')
    # STRtree resolves the class of each noded piece against its source, including splits.
    source_lines=[s['line'] for s in sources]; source_tree=STRtree(source_lines)
    noded=unary_union(source_lines, grid_size=.001)
    pieces=sorted(noded.geoms,key=lambda l:(tuple(l.coords[0]),tuple(l.coords[-1])))
    graph_nodes=[]; ids={}; roads=[]
    def getid(p,level=0):
        key=(round(p[0],5),round(p[1],5),level)
        if key not in ids: ids[key]=len(graph_nodes); graph_nodes.append([p[0],p[1]])
        return ids[key]
    widths={'residential':70,'grove':65,'arterial':100,'boulevard':140,'mountain':65,'highway':210,'ramp':75,'roundabout':70}
    def road(points,kind,level=0,**extra):
        pts=[list(p) for p in points]
        a,b=getid(pts[0],level),getid(pts[-1],level)
        if a==b: return
        roads.append(dict(points=pts,**{'from':a,'to':b},kind=kind,
                          width=widths[kind]*road_width_multiplier,
                          sidewalk=80 if kind not in ('highway','ramp','mountain','grove') and district(pts[len(pts)//2])=='DOWNTOWN' else 40 if kind not in ('highway','ramp','mountain','grove') else 30 if kind=='grove' else 20 if kind=='mountain' else 0,
                          lanes=4 if kind=='boulevard' else 6 if kind=='highway' else 2,
                          trail=False,**extra))
    for line in pieces:
        if line.length<.01: continue
        idx=int(source_tree.nearest(line.interpolate(.5,normalized=True)))
        kind=sources[idx]['kind']
        extra={}
        if kind=='roundabout':
            c=roundabouts[0]['center']; a=line.coords[0]; b=line.coords[-1]
            cross=(a[0]-c[0])*(b[1]-c[1])-(a[1]-c[1])*(b[0]-c[0])
            extra={'one_way':True,'direction':'forward' if cross<0 else 'reverse'}
        road(line.coords,kind,**extra)
    # Raised highway: independent graph level, exact ramp endpoints are explicit nodes.
    highway=curve((-w*.12,h*.15),(w*1.12,h*.16),h*.025,spacing=w/100)
    if shelter_plan:
        for fraction in (.15,.23,.025,.30):
            candidate=curve((-w*.12,h*fraction),(w*1.12,h*(fraction+.01)),h*.025,spacing=w/100)
            if not LineString(candidate).buffer(210*road_width_multiplier/2+25).intersects(keepouts):
                highway=candidate; break
        else: raise ValueError('Highway cannot avoid shelter reservations')
    # Fixed 101 samples support the existing scenic structures.
    highway=[LineString(highway).interpolate(i/100,normalized=True).coords[0] for i in range(101)]
    for i in range(1,len(highway)): road(highway[i-1:i+1],'highway',1,elevated=True)
    ground_count=len(graph_nodes)-len(highway)
    ramps=[]
    for index in (28,70):
        start=highway[index]
        targets=sorted(range(ground_count),key=lambda i:math.dist(start,graph_nodes[i]))
        if shelter_plan: targets=[i for i in targets if not LineString([start,graph_nodes[i]]).intersects(keepouts)]
        if not targets: raise ValueError('No unobstructed highway ramp')
        target=targets[0]
        pts=curve(start,graph_nodes[target],0)
        roads.append(dict(points=[list(p) for p in pts],**{'from':getid(start,1),'to':target},
                          kind='ramp',width=widths['ramp']*road_width_multiplier,sidewalk=0,lanes=2,trail=False,ramp=True))
        ramps.append([list(p) for p in pts])
    ground=[r for r in roads if not r.get('elevated') and not r.get('ramp')]
    corridors=[LineString(r['points']).buffer(r['width']/2+r['sidewalk']+12) for r in ground]
    # Buildings and parking also reserve clearance around bridge decks and ramp
    # supports. Grade separation permits streets underneath, not tall buildings.
    corridors += [LineString(r['points']).buffer(r['width']/2+20) for r in roads if r.get('elevated') or r.get('ramp')]
    road_land=unary_union(corridors+[bulb.buffer(32)]+[Point(r['center']).buffer(r['radius']+40) for r in roundabouts])
    # Move shelter structures into reserved off-road plazas. Original road-entry
    # nodes remain untouched; agents use a walkable connector to the new threshold.
    if shelter_plan:
        shelter_access=shelter_plan
        if any(box(*_rect_bounds(p['bounds'])).intersects(road_land) for p in shelter_plan.values()):
            raise ValueError('Road encroaches on prior shelter reservation')
    else:
        shelter_access={}
        for key,entry in sites.items():
            chosen=None
            for radius in range(170,1500,70):
                for index in range(24):
                    angle=index*math.tau/24
                    point=(entry[0]+math.cos(angle)*radius,entry[1]+math.sin(angle)*radius)
                    # Bounds cover the complete existing vault/rock-shoulder assembly.
                    bounds=box(point[0]-110,point[1]-30,point[0]+110,point[1]+175) if key in ('S4','S5') else box(point[0]-95,point[1]-30,point[0]+95,point[1]+115)
                    if not world.contains(bounds) or bounds.intersects(road_land) or bounds.intersects(lake.buffer(40)): continue
                    if any(bounds.buffer(20).intersects(box(*_rect_bounds(p['bounds']))) for p in shelter_access.values()): continue
                    chosen=dict(position=point,road_entry=entry,bounds=rect(bounds)); break
                if chosen: break
            if not chosen: raise ValueError(f'No safe off-road shelter plaza for {key}')
            shelter_access[key]=chosen
    gathering=(cx+470,cy+340)
    forbidden=unary_union([road_land,lake.buffer(40),park,Point(gathering).buffer(80)]+[Point(p).buffer(155) for p in sites.values()]+[box(*_rect_bounds(p['bounds'])).buffer(15) for p in shelter_access.values()])
    if procedural:
        forbidden=unary_union([forbidden]+[LineString([p['road_entry'],p['position']]).buffer(35) for p in shelter_access.values()])
    from .tile_world import Occupancy, manifest
    occupancy=Occupancy()
    reserved=[]; parking=[]; buildings=[]; pois=[]; municipal={}
    access_reservations=[]
    # Candidate curb positions are shared by parking and frontage parcels.
    candidates=[]
    for r in ground:
        line=LineString(r['points'])
        for cursor in range(110,int(line.length)-110,100):
            p=line.interpolate(cursor); before=line.interpolate(cursor-2); after=line.interpolate(cursor+2)
            dx,dy=after.x-before.x,after.y-before.y; length=math.hypot(dx,dy)
            if length<.1: continue
            t=(dx/length,dy/length)
            for sign in (-1,1):
                n=(-t[1]*sign,t[0]*sign)
                candidates.append((p.coords[0],t,n,r))
    building_rng.shuffle(candidates)
    def available(poly):
        return world.contains(poly) and not poly.intersects(forbidden) and occupancy.can_place(poly.buffer(12))
    def reserve(poly):
        occupancy.reserve(poly,len(reserved)); reserved.append(poly)
    # Small houses at Alder Court have reserved yards and actual driveway access.
    grove_line=LineString(smooth)
    for cursor in range(140,int(grove_line.length)-70,145):
        p=grove_line.interpolate(cursor); a=grove_line.interpolate(cursor-1); b=grove_line.interpolate(cursor+1)
        dx,dy=b.x-a.x,b.y-a.y; length=math.hypot(dx,dy); t=(dx/length,dy/length)
        for sign in (-1,1):
            n=(-t[1]*sign,t[0]*sign); center=(p.x+n[0]*172,p.y+n[1]*172)
            footprint=box(center[0]-48,center[1]-48,center[0]+48,center[1]+48)
            yard=footprint.buffer(22,cap_style='square',join_style='mitre')
            if not available(yard): continue
            buildings.append(dict(rect=rect(footprint),angle=-math.atan2(t[1],t[0])+(math.pi if sign==1 else 0),district='GROVE',local_size=[62,62],
                                  driveway=[(p.x+n[0]*55,p.y+n[1]*55),center],yard=rect(yard)))
            reserve(yard)
    for i in range(8):
        angle=i*math.tau/8
        direction=(math.cos(angle),math.sin(angle))
        center=(stem[-1][0]+direction[0]*245,stem[-1][1]+direction[1]*245)
        footprint=box(center[0]-48,center[1]-48,center[0]+48,center[1]+48)
        yard=footprint.buffer(18,join_style='mitre')
        if not available(yard): continue
        start=(stem[-1][0]+direction[0]*108,stem[-1][1]+direction[1]*108)
        buildings.append(dict(rect=rect(footprint),angle=-angle+math.pi/2,district='GROVE',local_size=[62,62],driveway=[start,center],yard=rect(yard)))
        reserve(yard)
    categories=[('shopping','DOWNTOWN'),('school','SCHOOL'),('police','SERVICES'),('hospital','SERVICES'),
                ('offices','DOWNTOWN'),('motel','RESIDENTIAL'),('residential','RESIDENTIAL'),('industrial','INDUSTRIAL'),('grove','GROVE'),
                ('shelter:S2','S2'),('shelter:S3','S3')]
    categories += [('residential','RESIDENTIAL') for _ in range(max(12,int(parking_count))-len(categories))]
    for category,target in categories:
        aim=sites[target] if target in sites else centers[target]
        for p,t,n,r in sorted(candidates,key=lambda c:math.dist(c[0],aim)):
            setback=r['width']/2+r['sidewalk']+28
            def point(along,out): return (p[0]+t[0]*along+n[0]*out,p[1]+t[1]*along+n[1]*out)
            poly=Polygon([point(-115,setback),point(115,setback),point(115,setback+150),point(-115,setback+150)])
            campus=None
            if category in ('police','hospital','offices','motel'):
                # Reserve the complete service parcel before ordinary development.
                rear=560 if category=='hospital' else 440 if category=='motel' else 465
                campus=Polygon([point(-145,setback),point(145,setback),point(145,setback+rear),point(-145,setback+rear)])
                if category=="motel": campus=Polygon([point(-145,setback),point(330,setback),point(330,setback+185),point(-145,setback+185)])
                if not available(campus): continue
            elif not available(poly): continue
            lot_id=f'PARK{len(parking):03d}'; bays=[]
            for i in range(6):
                along=(i-2.5)*34; center=point(along,setback+112)
                bays.append(dict(id=f'{lot_id}:{i}',position=center,heading=math.atan2(-n[1],-n[0]),
                                 width=30,length=66,occupied_by='',
                                 approach=[p,point(0,setback+42),point(along,setback+42),center]))
            parking.append(dict(id=lot_id,category=category,position=point(0,setback+75),road_entry=p,
                                tangent=t,normal=n,polygon=list(poly.exterior.coords)[:-1],bounds=rect(poly),bays=bays))
            if campus is not None:
                bw,bd=(180,80) if category=='motel' else (230,220 if category=='hospital' else 145)
                center=point(220,setback+75) if category=="motel" else point(0,setback+240+bd/2)
                angle=-math.atan2(t[1],t[0])+(math.pi if t[0]*n[1]-t[1]*n[0]>0 else 0)
                from shapely.affinity import rotate,translate
                actual=translate(rotate(box(-bw/2,-bd/2,bw/2,bd/2),-angle,use_radians=True),*center)
                envelope=box(*actual.buffer(5).bounds)
                if not campus.buffer(.01).covers(envelope) or envelope.intersects(poly):
                    parking.pop(); continue
                municipal[category]=len(buildings)
                threshold=point(220,setback+35) if category=='motel' else point(0,setback+240)
                approach=nearest_points(Point(threshold),LineString(r['points']))[1].coords[0] if category=='motel' else p
                buildings.append(dict(rect=rect(envelope),local_size=[bw,bd],angle=angle,district='SERVICES',style='perimeter',asset_type='motel' if category=='motel' else '',height_m=18 if category=='hospital' else 7,
                                      road_entry=approach,entrance=threshold,access_path=[approach,threshold],municipal_block=list(campus.exterior.coords)[:-1]))
                reserve(campus)
            else: reserve(poly)
            break
        else: raise ValueError(f'No valid parking parcel for {category}')
    # Street-facing perimeter blocks: reserve the complete rotated envelope, including
    # cornices. Navigation, collision and rendered footprints share this envelope.
    def parcel(center, angle, width, depth, name, frontage):
        if len(buildings)>=max_buildings: return False
        from shapely.affinity import rotate, translate
        actual=translate(rotate(box(-width/2,-depth/2,width/2,depth/2),-angle,use_radians=True),*center)
        footprint=box(*actual.buffer(5).bounds)
        if not available(footprint): return False
        p,t,n,r=frontage
        entrance=(center[0]-n[0]*depth/2,center[1]-n[1]*depth/2)
        access=LineString([p,entrance]).buffer(8,cap_style='flat')
        if any(access.intersects(s) for s in reserved): return False
        if any(footprint.intersects(s) for s in access_reservations): return False
        buildings.append(dict(rect=rect(footprint),local_size=[width,depth],angle=angle,
                              district=name,style='perimeter',height_m=(3.8 if len(buildings)%2 else 6.0) if name=='RESIDENTIAL' else 3.3*(5+int((center[0]+center[1])//100)%3),parcel=list(footprint.buffer(6,join_style='mitre').exterior.coords)[:-1],footprint=list(actual.exterior.coords)[:-1],road_entry=p,entrance=entrance,access_path=[p,entrance]))
        access_reservations.append(access)
        reserve(footprint)
        return True
    for p,t,n,r in candidates:
        name=district(p)
        if name in ('GROVE','MOUNTAINS'): continue
        angle=-math.atan2(t[1],t[0])+(math.pi if t[0]*n[1]-t[1]*n[0]>0 else 0)
        suburban=name=='RESIDENTIAL'
        width=building_rng.uniform(90,130) if suburban else building_rng.uniform(240,340)
        depth=building_rng.uniform(85,120) if suburban else building_rng.uniform(160,225)
        # AABB supports the existing inexpensive pedestrian obstacle grid. Try a
        # smaller frontage if a junction, neighbouring block or parking constrains it.
        for scale in (1.0,.78):
            fw,fd=width*scale,depth*scale
            c,s=abs(math.cos(angle)),abs(math.sin(angle))
            support=abs(n[0])*(c*fw+s*fd)/2+abs(n[1])*(s*fw+c*fd)/2
            setback=r['width']/2+r['sidewalk']+24+support
            center=(p[0]+n[0]*setback,p[1]+n[1]*setback)
            if district(center)=='GROVE': continue
            if parcel(center,angle,fw,fd,district(center),(p,t,n,r)): break
    # Gameplay POIs retain their order and names for the existing social simulation.
    used=set()
    for i,(kind,category) in enumerate([('Bank','shopping'),('Police Station','police'),('Medical Station','hospital'),('Fire Station','offices'),('School','school')]):
        anchor=next(p for p in parking if p['category']==category)
        choices=[j for j,b in enumerate(buildings) if j not in used and b['district']!='GROVE']
        best=municipal[category] if category in municipal else min(choices,key=lambda j:Point(anchor['position']).distance(box(*_rect_bounds(buildings[j]['rect']))))
        used.add(best); footprint=box(*_rect_bounds(buildings[best]['rect'])); center=footprint.centroid
        entry=Point(buildings[best]['road_entry']) if 'road_entry' in buildings[best] else nearest_points(center,unary_union([LineString(r['points']) for r in ground]))[1]
        buildings[best]['district']='SCHOOL' if kind=='School' else 'SERVICES' if i in (1,2,3) else 'DOWNTOWN'
        pois.append(dict(id=f'POI{i}',kind=kind,position=entry.coords[0],footprint=rect(footprint),roof_position=center.coords[0],roof_height=buildings[best].get('height_m',5.2),parking_id=anchor['id']))
    districts=[]
    # Voronoi-style clipped cells make district boundaries seeded, irregular and inspectable.
    from shapely import voronoi_polygons, MultiPoint
    regions=voronoi_polygons(MultiPoint(list(centers.values())),extend_to=world,ordered=True)
    for (name,center),region,color in zip(centers.items(),regions.geoms,(COLORS*4)[:len(centers)]):
        polygon=region.intersection(world)
        if name=='GROVE': polygon=grove_bounds
        elif polygon.intersects(grove_bounds): polygon=polygon.difference(grove_bounds)
        for part in polygon.geoms if hasattr(polygon,'geoms') else [polygon]:
            if part.geom_type=='Polygon':
                triangles=[list(t.exterior.coords)[:3] for t in constrained_delaunay_triangles(part).geoms]
                districts.append(dict(name=name.split(':')[0],id=name,center=center,color=color,polygon=list(part.exterior.coords)[:-1],triangles=triangles))
    result=dict(version=VERSION,seed=int(seed),size=size,road_width_multiplier=road_width_multiplier,
                nodes=graph_nodes,roads=roads,sites=sites,shelter_access=shelter_access,park=rect(park),lake=rect(lake),
                grove=dict(name='ALDER COURT',bounds=rect(grove_bounds),center=stem[-1],bulb=list(bulb.exterior.coords)[:-1],entrance=entrance,
                           gathering=gathering,alley=[(cx-510,cy+340),gathering]),
                districts=districts,buildings=buildings,parking_lots=parking,pois=pois,
                highways=[[list(p) for p in highway]],ramps=ramps,roundabouts=roundabouts)
    result['tile_world']=manifest(result,occupancy.rejected)
    result['validation']=validate(result)
    result['generation_ms']=round((time.perf_counter()-started)*1000,2)
    if not result['validation']['valid']: raise ValueError('; '.join(result['validation']['errors']))
    return result


def _rect_bounds(r): return r[0],r[1],r[0]+r[2],r[1]+r[3]


def validate(data):
    errors=[]; adjacency=defaultdict(set); nodes=data['nodes']; roads=data['roads']
    for r in roads:
        a,b=r['from'],r['to']; adjacency[a].add(b); adjacency[b].add(a)
        if math.dist(r['points'][0],nodes[a])>.01 or math.dist(r['points'][-1],nodes[b])>.01: errors.append('Geometry/graph endpoint mismatch')
        if not LineString(r['points']).is_simple: errors.append('Self-intersecting road')
    found=set(); todo=[0]
    while todo:
        a=todo.pop()
        if a in found: continue
        found.add(a); todo.extend(adjacency[a]-found)
    if len(found)!=len(nodes): errors.append('Disconnected road network')
    ground=[r for r in roads if not r.get('elevated') and not r.get('ramp')]
    lines=[LineString(r['points']) for r in ground]; tree=STRtree(lines)
    # Every same-level centerline crossing must be a shared graph endpoint.
    for i,line in enumerate(lines):
        for j in tree.query(line,predicate='intersects'):
            j=int(j)
            if j<=i: continue
            intersection=line.intersection(lines[j])
            shared=set([ground[i]['from'],ground[i]['to']]) & set([ground[j]['from'],ground[j]['to']])
            if intersection.length>.01 or not shared: errors.append('Unnoded/overlapping ground road'); continue
            if any(intersection.distance(Point(nodes[k]))>.02 for k in shared): errors.append('Crossing outside graph junction')
    land=unary_union([line.buffer(r['width']/2+r['sidewalk']+5) for r,line in zip(ground,lines)]+[Polygon(data['grove']['bulb']).buffer(25)])
    structure_land=unary_union([land]+[LineString(r['points']).buffer(r['width']/2+5) for r in roads if r.get('elevated') or r.get('ramp')])
    for plaza in data.get('shelter_access',{}).values():
        if box(*_rect_bounds(plaza['bounds'])).intersects(structure_land): errors.append('Shelter structure intersects road')
    buildings=[box(*_rect_bounds(b['rect'])) for b in data['buildings']]
    for record,p in zip(data['buildings'],buildings):
        if 'local_size' in record:
            from shapely.affinity import rotate, translate
            width,depth=record['local_size']
            actual=translate(rotate(box(-width/2,-depth/2,width/2,depth/2),-record['angle'],use_radians=True),*p.centroid.coords[0])
            if not p.buffer(.01).covers(actual.buffer(3)): errors.append('Rendered building outside reserved envelope')
        if p.intersects(structure_land): errors.append('Building intersects road/sidewalk/deck')
        if any(p.distance(Point(s))<120 for s in data['sites'].values()): errors.append('Building blocks shelter')
    building_tree=STRtree(buildings)
    street_network=unary_union(lines)
    for index,record in enumerate(data['buildings']):
        if 'parcel' in record and not Polygon(record['parcel']).covers(Polygon(record['footprint'])):
            errors.append('Building outside assigned parcel')
        if 'access_path' in record:
            path=LineString(record['access_path'])
            if Point(record['road_entry']).distance(street_network)>.02:
                errors.append('Building frontage is not connected to road')
            if path.length>650: errors.append('Excessive building access distance')
            for other in building_tree.query(path.buffer(6),predicate='intersects'):
                if int(other)!=index: errors.append('Building entrance path obstructed')
            if 'municipal_block' in record:
                block=Polygon(record['municipal_block'])
                if not block.covers(buildings[index]): errors.append('Service building outside reserved site')
                for other in building_tree.query(block,predicate='intersects'):
                    if int(other)!=index: errors.append('Unrelated building in emergency service site')
    park_polys=[Polygon(p['polygon']) for p in data['parking_lots']]
    bay_ids=set(); bay_shapes=[]
    for p,polygon in zip(data['parking_lots'],park_polys):
        if polygon.intersects(land): errors.append('Parking intersects street')
        for b in p['bays']:
            if b['id'] in bay_ids: errors.append('Duplicate parking bay')
            bay_ids.add(b['id'])
            from shapely.affinity import rotate, translate
            footprint=translate(rotate(box(-b['length']/2,-b['width']/2,b['length']/2,b['width']/2),b['heading'],use_radians=True),*b['position'])
            if not polygon.covers(footprint): errors.append('Bay outside lot')
            bay_shapes.append(footprint)
    for shapes,label in [(buildings,'building'),(park_polys,'parking lot'),(bay_shapes,'parking space')]:
        tree=STRtree(shapes)
        for i,p in enumerate(shapes):
            for j in tree.query(p,predicate='intersects'):
                if int(j)>i: errors.append(f'Overlapping {label}')
    if any(p.intersects(b) for p in park_polys for b in buildings): errors.append('Building intersects parking')
    for site in data['sites'].values():
        if min(Point(site).distance(l) for l in lines)>.01: errors.append('Shelter lacks road approach')
    if len(data['sites'])!=5 or len(data['pois'])!=5: errors.append('Missing critical locations')
    if sum(b['district']=='GROVE' for b in data['buildings'])<4: errors.append('Insufficient cul-de-sac houses')
    if any(b['district']=='GROVE' and ('yard' not in b or 'driveway' not in b) for b in data['buildings']): errors.append('Missing cul-de-sac frontage')
    return dict(valid=not errors,errors=sorted(set(errors)),nodes=len(nodes),edges=len(roads),
                buildings=len(buildings),parking_lots=len(park_polys),parking_spaces=len(bay_ids),
                ground_crossings_noded=True)


def main():
    import sys
    request=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    encoded=json.dumps(dict(version=VERSION,request=request),sort_keys=True).encode()
    digest=hashlib.sha256(encoded).hexdigest(); target=Path(sys.argv[2])
    if target.exists():
        try:
            if json.loads(target.read_text()).get('hash')==digest: return
        except (ValueError,OSError): pass
    data=generate(**request); data['hash']=digest
    import os
    temporary=target.with_suffix(f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
    temporary.replace(target)


if __name__=='__main__': main()
