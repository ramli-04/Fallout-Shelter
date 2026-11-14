"""Partition connected road surfaces before assigning atlas UVs.

Each junction and each segment owns a disjoint polygon. Triangles never choose
their own nearest road, which previously produced discontinuous diagonal strips.
"""
import math
from shapely import LineString, Point, Polygon, box, buffer, unary_union
from shapely.affinity import rotate, translate
from .road_geometry import terrain_triangles


def partition(surface, roads, nodes, cell, parking=()):
    ground = [r for r in roads if not r.get('elevated') and not r.get('ramp')]
    adjacency = {}
    for r in ground:
        for node, other in [(r['from'], r['points'][1]), (r['to'], r['points'][-2])]:
            p = nodes[int(node)]
            angle = math.atan2(other[1]-p[1], other[0]-p[0])
            adjacency.setdefault(int(node), []).append((angle, r['width']))
    patches = []; occupied = []
    # Explicit parking never borrows a neighboring street's lane markings.
    for lot in parking:
        if lot.get('integrated_station'): continue
        shape = Polygon(lot['polygon']).intersection(surface)
        if not shape.is_empty:
            patches.append((shape, -1, lot['position'], (1, 0), 230, 0))
            occupied.append(shape)
    for node, directions in sorted(adjacency.items()):
        p = nodes[node]; count = len(directions)
        if count == 2 and abs(math.cos(directions[0][0]-directions[1][0])) > .85:
            continue
        angle = min(((a+math.pi/4) % (math.pi/2)-math.pi/4 for a, _ in directions), key=abs)
        tangent = (math.cos(angle), math.sin(angle))
        mask = 0
        for a, _ in directions:
            quarter = round((a-angle)/(math.pi/2)) % 4
            mask |= (1, 4, 2, 8)[quarter]
        tile = 1
        if count == 3: tile = {7: 5, 14: 6, 11: 7, 13: 8}.get(mask, 1)
        elif count == 2: tile = {9: 9, 10: 10, 5: 11, 6: 12}.get(mask, 1)
        elif count == 1: tile = 13
        extent = max(w for _, w in directions)*1.65
        zone = translate(rotate(box(-extent/2, -extent/2, extent/2, extent/2), angle, use_radians=True), *p)
        shape = zone.intersection(surface)
        if occupied: shape = shape.difference(unary_union(occupied))
        if shape.is_empty: continue
        patches.append((shape, tile, p, tangent, extent, 0)); occupied.append(zone)
    remainder = surface.difference(unary_union(occupied)) if occupied else surface
    # Split at segment boundaries as well: bends keep continuous path distance UVs.
    for road in ground:
        distance = 0
        for a, b in zip(road['points'], road['points'][1:]):
            length = math.dist(a, b)
            if length < .001: continue
            tangent = ((b[0]-a[0])/length, (b[1]-a[1])/length)
            strip = buffer(LineString([a, b]), road['width']/2+.5, cap_style='flat')
            shape = remainder.intersection(strip)
            if not shape.is_empty:
                patches.append((shape, -4 if road['lanes']>=4 else 0, a, tangent, road['width'], distance))
                remainder = remainder.difference(strip)
            distance += length
    if not remainder.is_empty:
        patches.append((remainder, -1, (0, 0), (1, 0), 100, 0))
    result = []
    for shape, tile, origin, tangent, width, distance in patches:
        for triangle in terrain_triangles(shape, cell):
            vertices = []
            for x, y in list(triangle.exterior.coords)[:3]:
                dx, dy = x-origin[0], y-origin[1]
                along = dx*tangent[0]+dy*tangent[1]
                across = -dx*tangent[1]+dy*tangent[0]
                uv = [.5+along/width, .5+across/width] if tile > 0 else [.5+across/width, (distance+along)/width]
                vertices.append([x, y, *uv])
            result.append(dict(tile=tile, vertices=vertices))
    return result
