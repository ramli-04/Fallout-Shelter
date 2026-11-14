"""Sparse logical tiles and deterministic chunk manifests, independent of rendering."""
import math
import json
from pathlib import Path
from collections import defaultdict
from shapely import box, Point, LineString

CONFIG = json.loads((Path(__file__).resolve().parents[1]/'resources/chunk_generation.json').read_text())
TILE_SIZE = float(CONFIG['tile_size'])
CHUNK_TILES = int(CONFIG['chunk_tiles'])
ASSETS = CONFIG['asset_modules']

class Occupancy:
    def __init__(self, tile_size=TILE_SIZE):
        self.tile_size = tile_size
        self.cells = {}
        self.rejected = 0

    def footprint(self, shape):
        a,b,c,d = shape.bounds
        return (math.floor(a/self.tile_size), math.floor(b/self.tile_size),
                math.ceil(c/self.tile_size), math.ceil(d/self.tile_size))

    def keys(self, shape):
        a,b,c,d = self.footprint(shape)
        return ((x,y) for x in range(a,c) for y in range(b,d))

    def can_place(self, shape):
        valid = not any(cell in self.cells for cell in self.keys(shape))
        if not valid: self.rejected += 1
        return valid

    def reserve(self, shape, owner):
        for cell in self.keys(shape): self.cells[cell] = owner


def manifest(layout, rejected=0):
    """Stable IDs and cross-chunk references; loading order never draws RNG."""
    tile = TILE_SIZE; count = CHUNK_TILES
    chunks = {}; entities = []; layers = defaultdict(lambda: defaultdict(set))
    size = layout['size']
    def cell(point): return math.floor(point[0]/tile), math.floor(point[1]/tile)
    def chunk(key):
        x,y=key
        name=f'{x}:{y}'
        if name not in chunks:
            chunks[name] = {'coordinate':[x,y], 'seed':(int(layout['seed']) ^ (x*73856093) ^ (y*19349663)) & 0x7fffffff,
                            'entities':[], 'owned_entities':[], 'layers':{}}
        return chunks[name]
    def add_layer(name, cells):
        for x,y in cells:
            if x<0 or y<0 or x*tile>=size[0] or y*tile>=size[1]: continue
            layers[(x//count,y//count)][name].add((x%count,y%count))
    def entity(kind, index, shape, extra=None):
        bounds=Occupancy().footprint(shape); a,b,c,d=bounds
        owner=cell(shape.centroid.coords[0]); owner=(owner[0]//count,owner[1]//count)
        record={'id':f'{kind}:{index}', 'kind':kind, 'index':index,
                'tile_origin':[a,b], 'footprint':[c-a,d-b], 'owner_chunk':list(owner)}
        if extra: record.update(extra)
        entities.append(record)
        for x in range(a//count, (c-1)//count+1):
            for y in range(b//count,(d-1)//count+1): chunk((x,y))['entities'].append(record['id'])
        chunk(owner)['owned_entities'].append(record['id'])
        add_layer(kind, ((x,y) for x in range(a,c) for y in range(b,d)))
        return record
    for i,b in enumerate(layout['buildings']):
        r=b['rect']; shape=box(r[0],r[1],r[0]+r[2],r[1]+r[3])
        record=entity('building',i,shape,{'district':b['district']})
        b['tile_placement']={k:record[k] for k in ('tile_origin','footprint','owner_chunk')}
        if 'municipal_block' in b:
            from shapely import Polygon
            entity('reserved',i,Polygon(b['municipal_block']))
        if 'access_path' in b:
            access=LineString(b['access_path']).buffer(10)
            add_layer('access',Occupancy().keys(access))
    for i,p in enumerate(layout['parking_lots']):
        from shapely import Polygon
        entity('parking',i,Polygon(p['polygon']))
    for kind, source in [('tree',layout.get('vegetation',[])),('prop',layout.get('environment_props',[]))]:
        for i,p in enumerate(source):
            x,y=cell(p['position']); shape=box(x*tile,y*tile,(x+1)*tile,(y+1)*tile)
            entity(kind,i,shape)
    for road in layout['roads']:
        if road.get('elevated') or road.get('ramp'): continue
        shape=LineString(road['points']).buffer(road['width']/2)
        # Road cells are rasterized at cell centres, separately from object occupancy.
        add_layer('road',(key for key in Occupancy().keys(shape)
                          if shape.covers(Point((key[0]+.5)*tile,(key[1]+.5)*tile))))
    for x in range(math.ceil(size[0]/(tile*count))):
        for y in range(math.ceil(size[1]/(tile*count))): chunk((x,y))
    for key,groups in layers.items():
        chunk(key)['layers']={name:[list(v) for v in sorted(cells)] for name,cells in sorted(groups.items())}
    return {'version':1,'tile_size':tile,'chunk_tiles':count,
            'asset_modules':ASSETS,'entities':entities,
            'chunks':[chunks[k] for k in sorted(chunks)],'rejected_placements':rejected}
