"""Robust planar road overlay and constrained triangulation, before simulation starts."""
import hashlib
import json
from pathlib import Path
from shapely import LineString, Polygon, box, buffer, unary_union, constrained_delaunay_triangles, make_valid, intersection

def terrain_triangles(shape, cell):
    """Constrain every surface triangle to one authoritative terrain triangle.

    Interpolating its vertex heights then matches the terrain everywhere, so a
    wide intersection cannot cut through a hill between tessellation vertices.
    """
    import math
    x0,y0,x1,y1=shape.bounds
    result=[]
    # Clip once per terrain row first. Intersecting each tiny tile against the
    # whole city's detailed polygon makes startup quadratic in road complexity.
    for y in range(math.floor(y0/cell),math.ceil(y1/cell)):
        strip=shape.intersection(box(x0-1,y*cell,x1+1,(y+1)*cell))
        if strip.is_empty or strip.area<1e-8: continue
        left,_,right,_=strip.bounds
        tiles=[]
        for x in range(math.floor(left/cell),math.ceil(right/cell)):
            a=(x*cell,y*cell); b=(x*cell,(y+1)*cell)
            c=((x+1)*cell,(y+1)*cell); d=((x+1)*cell,y*cell)
            tiles.extend([Polygon([a,c,b]),Polygon([a,d,c])])
        clipped=intersection(tiles,strip)
        result.extend(t for piece in clipped if not piece.is_empty
                      for t in constrained_delaunay_triangles(piece).geoms if t.area>1e-8)
    return result

def build(groups):
    result={}; shapes={}
    for key, records in groups.items():
        definition=records if isinstance(records,dict) else dict(paths=records)
        paths=definition.get('paths',[])
        polygons=[Polygon(p) for p in definition.get('polygons',[])]
        polygons += [buffer(LineString(r['points']),r['width'],cap_style='flat',join_style='mitre',mitre_limit=2)
                     for r in paths if len(r['points'])>=2]
        shapes[key]=make_valid(unary_union(polygons))
    for key, records in groups.items():
        definition=records if isinstance(records,dict) else {}
        merged=shapes[key]
        subtract=definition.get('subtract',[])
        if subtract: merged=make_valid(merged.difference(unary_union([shapes[k] for k in subtract])))
        if merged.is_empty: result[key]=[]; continue
        cell=definition.get('terrain_cell',0)
        triangles=terrain_triangles(merged,cell) if cell else constrained_delaunay_triangles(merged).geoms
        result[key]=[[list(p) for p in triangle.exterior.coords[:3]] for triangle in triangles if triangle.area>1e-8]
    return result

if __name__=='__main__':
    import sys
    source=Path(sys.argv[1]).read_bytes()
    digest=hashlib.sha256(b'city61-terrain-v2'+source).hexdigest()
    target=Path(sys.argv[2])
    if not target.exists() or json.loads(target.read_text()).get('hash')!=digest:
        import os
        temporary=target.with_suffix(f'.{os.getpid()}.tmp')
        temporary.write_text(json.dumps(dict(hash=digest,groups=build(json.loads(source)))),encoding='utf-8')
        temporary.replace(target)
