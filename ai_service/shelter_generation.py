"""Reserve final shelter structures and approaches before streets or parcels."""
import math
import random
from shapely import Point,LineString,box

def reserve(size,centers,seed):
    w,h=size; rng=random.Random(seed)
    cx,cy=centers['GROVE']
    protected=[box(w*.08,h*.62,w*.22,h*.85),box(cx-650,cy-480,cx+650,cy+480)]
    zones={'S1':(.34,.52,.34,.57),'S2':(.47,.64,.65,.77),'S3':(.66,.79,.57,.72),
           'S4':(.86,.94,.38,.52),'S5':(.82,.93,.07,.17)}
    result={}
    for name,(x0,x1,y0,y1) in zones.items():
        for attempt in range(120):
            p=(w*rng.uniform(x0,x1),h*rng.uniform(y0,y1))
            bounds=box(p[0]-110,p[1]-30,p[0]+110,p[1]+175) if name in ('S4','S5') else box(p[0]-95,p[1]-30,p[0]+95,p[1]+115)
            entry=(p[0],p[1]-260)
            corridor=LineString([entry,p]).buffer(32)
            if not box(30,30,w-30,h-30).covers(bounds): continue
            if any(bounds.buffer(30).intersects(region) or corridor.intersects(region) for region in protected): continue
            result[name]=dict(position=p,road_entry=entry,bounds=[bounds.bounds[0],bounds.bounds[1],bounds.bounds[2]-bounds.bounds[0],bounds.bounds[3]-bounds.bounds[1]])
            protected.extend([bounds.buffer(30),corridor]); break
        else: raise ValueError(f'Cannot reserve accessible structure for {name}')
    return result
