import copy
import json
import hashlib
import math
import unittest
from pathlib import Path
from shapely import LineString, Point, Polygon, box, unary_union
from ai_service.city_generator import BASE_SIZE, generate, validate
from ai_service.road_geometry import build


class CityGeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.city = generate(42)

    def test_reproducible_and_different_seeds(self):
        a = {k:v for k,v in self.city.items() if k != 'generation_ms'}
        b = {k:v for k,v in generate(42).items() if k != 'generation_ms'}
        self.assertEqual(a,b)
        self.assertNotEqual(a['roads'],generate(43)['roads'])
        self.assertNotEqual(a['districts'],generate(43)['districts'])

    def test_twice_area_fixed_world_scale(self):
        self.assertAlmostEqual(math.prod(self.city['size'])/math.prod(BASE_SIZE),2)
        residential=next(r for r in self.city['roads'] if r['kind']=='residential')
        self.assertEqual(residential['width'],70)  # 2 x 3.5 m, no scaling of metres
        self.assertTrue(any(r['lanes']==4 for r in self.city['roads']))
        self.assertTrue(any(r['lanes']==6 for r in self.city['roads']))

    def test_layout_seed_and_parameter_matrix(self):
        for seed in [0,1,2,7,43,91,123,1000]:
            with self.subTest(seed=seed):
                self.assertTrue(generate(seed)['validation']['valid'])
        for area,width in [(1,.75),(1,1.5),(2,1.5),(3,.75),(3,1.5)]:
            with self.subTest(area=area,width=width):
                data=generate(42,size=[s*math.sqrt(area) for s in BASE_SIZE],road_width_multiplier=width)
                self.assertTrue(data['validation']['valid'])

    def test_parking_categories_and_bays(self):
        categories={p['category'] for p in self.city['parking_lots']}
        self.assertTrue({'shopping','school','police','hospital','offices','residential','grove'}<=categories)
        self.assertTrue(any(c.startswith('shelter:') for c in categories))
        bays=[b for p in self.city['parking_lots'] for b in p['bays']]
        self.assertEqual(len(bays),len({b['id'] for b in bays}))
        self.assertTrue(all(b['occupied_by']=='' for b in bays))
        for poi in self.city['pois']:
            lot=next(p for p in self.city['parking_lots'] if p['id']==poi['parking_id'])
            self.assertLess(math.dist(poi['roof_position'],lot['position']),650)

    def test_neighbourhood_is_original_and_connected(self):
        houses=[b for b in self.city['buildings'] if b['district']=='GROVE']
        self.assertGreaterEqual(len(houses),4)
        self.assertTrue(all('yard' in b and 'driveway' in b for b in houses))
        self.assertEqual(self.city['grove']['name'],'ALDER COURT')
        self.assertGreater(Polygon(self.city['grove']['bulb']).area,30000)
        self.assertTrue(self.city['validation']['ground_crossings_noded'])

    def test_validation_rejects_corruption(self):
        city=copy.deepcopy(self.city)
        city['roads'][0]['points'][0][0]+=100
        self.assertFalse(validate(city)['valid'])
        city=copy.deepcopy(self.city)
        city['parking_lots'][1]=copy.deepcopy(city['parking_lots'][0])
        self.assertFalse(validate(city)['valid'])
        city=copy.deepcopy(self.city)
        city['buildings'][0]['rect']=[*city['roads'][0]['points'][0],100,100]
        self.assertFalse(validate(city)['valid'])

    def test_surface_layers_are_disjoint_and_terrain_constrained(self):
        groups={'asphalt':dict(paths=[dict(points=[[0,0],[90,90]],width=10)]),
                'curb':dict(paths=[dict(points=[[0,0],[90,90]],width=12)],subtract=['asphalt'],terrain_cell=20),
                'sidewalk':dict(paths=[dict(points=[[0,0],[90,90]],width=25)],subtract=['asphalt','curb'],terrain_cell=20)}
        result=build(groups)
        shapes={k:unary_union([Polygon(t) for t in triangles]) for k,triangles in result.items()}
        self.assertLess(shapes['asphalt'].intersection(shapes['curb']).area,1e-6)
        self.assertLess(shapes['sidewalk'].intersection(shapes['curb']).area,1e-6)
        for key in ['curb','sidewalk']:
            triangles=[Polygon(t) for t in result[key]]
            self.assertAlmostEqual(sum(t.area for t in triangles),shapes[key].area,places=6)
            for triangle in triangles:
                x,y=triangle.centroid.coords[0]; ix,iy=math.floor(x/20),math.floor(y/20)
                a=(ix*20,iy*20); b=(ix*20,(iy+1)*20); c=((ix+1)*20,(iy+1)*20); d=((ix+1)*20,iy*20)
                self.assertTrue(Polygon([a,c,b]).buffer(1e-7).covers(triangle) or Polygon([a,d,c]).buffer(1e-7).covers(triangle))

    def test_original_carriageways_are_unchanged(self):
        # Captured before the streetscape work: excludes only sidewalk widths.
        # Vertices, topology, widths, kinds and grade separation remain identical.
        expected={42:'8fb8d4a98c7dc23bc64607574645b9287f282f9191ac27f98b72c2a707ab6820',
                  7:'393bf05a5d0ab417315da61d137087a4442afeddfd9b46fd267eb06c7b88fad3'}
        for seed,digest in expected.items():
            city=self.city if seed==42 else generate(seed)
            carriageways=[{k:v for k,v in road.items() if k!='sidewalk'} for road in city['roads']]
            self.assertEqual(hashlib.sha256(json.dumps(carriageways,sort_keys=True).encode()).hexdigest(),digest)

    def test_dense_frontages_and_wide_pavements(self):
        self.assertGreaterEqual(len(self.city['buildings']),190)
        self.assertGreaterEqual(sum(b.get('local_size',[0])[0]>180 for b in self.city['buildings']),80)
        self.assertGreater(sum(b['rect'][2]*b['rect'][3] for b in self.city['buildings']),6_000_000)
        for road in self.city['roads']:
            if road['kind'] not in ('highway','ramp','mountain','grove'): self.assertGreaterEqual(road['sidewalk'],40)
        for b in self.city['buildings']:
            if b.get('style')=='perimeter': self.assertGreaterEqual(b['height_m'],16.5)

    def test_shelter_structures_use_off_road_plazas(self):
        ground=[r for r in self.city['roads'] if not r.get('elevated') and not r.get('ramp')]
        carriageways=unary_union([LineString(r['points']).buffer(r['width']/2+r['sidewalk']) for r in ground])
        for key,plaza in self.city['shelter_access'].items():
            x,y,w,h=plaza['bounds']; bounds=box(x,y,x+w,y+h)
            self.assertFalse(bounds.intersects(carriageways))
            self.assertTrue(bounds.covers(Point(plaza['position'])))
            self.assertEqual(plaza['road_entry'],self.city['sites'][key])
        damaged=copy.deepcopy(self.city)
        damaged['shelter_access']['S1']['bounds']=[*self.city['roads'][0]['points'][0],100,100]
        self.assertFalse(validate(damaged)['valid'])

    def test_invalid_parameters(self):
        for value in [0,float('nan'),2]:
            with self.assertRaises(ValueError): generate(42,road_width_multiplier=value)

    def test_actual_city_surface_union(self):
        fixture=Path('outputs/city61-road-fixture.json')
        if not fixture.exists(): self.skipTest('Run render_city61.gd to export current real road layers')
        groups=json.loads(fixture.read_text())
        geometry=build({k:groups[k] for k in ['asphalt','curb','sidewalk']})
        shapes={}
        for key,triangles in geometry.items():
            polygons=[Polygon(t) for t in triangles]
            union=unary_union(polygons)
            self.assertTrue(all(p.is_valid and p.area>1e-8 for p in polygons))
            self.assertAlmostEqual(sum(p.area for p in polygons),union.area,delta=.001)
            shapes[key]=union
        for a,b in [('asphalt','curb'),('asphalt','sidewalk'),('curb','sidewalk')]:
            self.assertLess(shapes[a].intersection(shapes[b]).area,.001)


if __name__=='__main__': unittest.main()
