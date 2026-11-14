import json
import unittest
from pathlib import Path
from shapely import LineString, Polygon, buffer, unary_union
from ai_service.road_geometry import build

class RoadGeometryTests(unittest.TestCase):
    def verify(self,groups):
        result=build(groups)
        for key,paths in groups.items():
            triangles=[Polygon(p) for p in result[key]]
            self.assertTrue(all(p.is_valid and p.area>1e-8 for p in triangles))
            union=unary_union(triangles)
            expected=unary_union([buffer(LineString(p['points']),p['width'],cap_style='flat',join_style='mitre',mitre_limit=2) for p in paths])
            self.assertAlmostEqual(sum(p.area for p in triangles),union.area,delta=1e-6)
            self.assertLess(union.symmetric_difference(expected).area,1e-6)

    def test_crossings_curves_and_holes(self):
        self.verify({'asphalt':[dict(points=[[0,0],[50,60],[100,50]],width=5),
            dict(points=[[0,50],[100,0]],width=5),
            dict(points=[[0,0],[100,0],[100,100],[0,100],[0,0]],width=5)]})

    def test_actual_seeded_city(self):
        fixture=Path('outputs/phase5-road-fixture.json')
        if not fixture.exists(): self.skipTest('Run Godot test_road_surface.gd to export actual city fixture')
        self.verify(json.loads(fixture.read_text()))
