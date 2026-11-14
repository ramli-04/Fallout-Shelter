import math
import unittest
from shapely import LineString, Point, Polygon, buffer, unary_union
from ai_service.road_art_layout import partition


class RoadArtLayoutTests(unittest.TestCase):
    def fixture(self, arms):
        nodes = [[0, 0]] + arms
        roads = [dict(points=[nodes[0], p], width=70, lanes=2, **{'from': 0, 'to': i+1})
                 for i, p in enumerate(arms)]
        shape = unary_union([buffer(LineString(r['points']), 35, cap_style='flat') for r in roads]+[Point(0, 0).buffer(40)])
        return shape, partition(shape, roads, nodes, 40)

    def assert_complete(self, shape, records):
        triangles = [Polygon([v[:2] for v in r['vertices']]) for r in records]
        union = unary_union(triangles)
        self.assertLess(shape.symmetric_difference(union).area, 1e-5)
        self.assertAlmostEqual(sum(t.area for t in triangles), union.area, delta=1e-5)
        self.assertTrue(all(math.isfinite(v) for r in records for p in r['vertices'] for v in p))

    def test_all_four_corners_have_complete_unique_surfaces(self):
        for arms, expected in [([[400, 0], [0, -400]], 9), ([[-400, 0], [0, -400]], 10),
                               ([[400, 0], [0, 400]], 11), ([[-400, 0], [0, 400]], 12)]:
            with self.subTest(tile=expected):
                shape, records = self.fixture(arms)
                self.assert_complete(shape, records)
                self.assertTrue(any(r['tile'] == expected for r in records))
                node_triangles = [Polygon([v[:2] for v in r['vertices']]) for r in records if r['tile'] == expected]
                self.assertTrue(unary_union(node_triangles).covers(Point(0, 0)))

    def test_t_and_cross_junctions_do_not_overlap_or_leave_holes(self):
        for arms in [[[400, 0], [-400, 0], [0, 400]],
                     [[400, 0], [-400, 0], [0, 400], [0, -400]]]:
            shape, records = self.fixture(arms)
            self.assert_complete(shape, records)

    def test_repeatable_uvs_and_segment_ownership(self):
        shape, first = self.fixture([[400, 0], [-400, 0], [0, 400]])
        _, second = self.fixture([[400, 0], [-400, 0], [0, 400]])
        self.assertEqual(first, second)
        self.assertTrue(all(-1e-5 <= v[2] <= 1.00001 for r in first if r['tile'] == 0 for v in r['vertices']))

    def test_parking_art_follows_rotated_lot_and_station_is_excluded(self):
        polygon=[[0,0],[0,230],[-150,230],[-150,0]]
        lot=dict(polygon=polygon,position=[-75,115],tangent=[0,1],normal=[-1,0])
        shape=Polygon(polygon)
        records=partition(shape,[],[],40,[lot])
        self.assert_complete(shape,records)
        self.assertTrue(all(r['tile']==-2 for r in records))
        self.assertTrue(all(-.00001<=v[2]<=1.00001 and -.00001<=v[3]<=1.00001 for r in records for v in r['vertices']))
        lot['integrated_station']=True
        records=partition(shape,[],[],40,[lot])
        self.assertTrue(all(r['tile']==-1 for r in records))

    def test_special_road_tile_owns_complete_turning_head(self):
        shape=Point(0,0).buffer(115)
        records=partition(shape,[],[],40,special=[dict(center=[0,0],extent=287.5,tile=15)])
        self.assert_complete(shape,records)
        self.assertTrue(all(r['tile']==15 for r in records))
