"""Acceptance tests exercise the real generator, validator and snapshot loader."""
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from ai_service import world_generation as world


class WorldGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.first=world.generate(42,'small')
        cls.second=world.generate(43,'small')

    def test_reproducible_across_processes(self):
        script="from ai_service.world_generation import generate; print(generate(42,'small')['content_hash'])"
        env=dict(os.environ,PYTHONHASHSEED='9871')
        actual=subprocess.check_output([sys.executable,'-c',script],env=env,text=True).strip()
        self.assertEqual(self.first['content_hash'],actual)
        self.assertEqual(self.first,world.generate(42,'small'))

    def test_visibly_different_road_layouts(self):
        self.assertEqual({world.generate(seed,'small')['layout_pattern'] for seed in [0,1,2]}, {'organic','mixed','radial'})
        self.assertNotEqual(self.first['layout']['roads'],self.second['layout']['roads'])
        self.assertNotEqual(self.first['layout']['size'],self.second['layout']['size'])
        self.assertNotEqual(self.first['layout']['sites'],self.second['layout']['sites'])
        radial=world.generate(2,'small')
        self.assertEqual(radial['layout_pattern'],'radial')
        self.assertTrue(radial['layout']['validation']['valid'])

    def test_independent_vegetation_stream(self):
        sparse=world.generate(42,'small',vegetation_density=0)
        dense=world.generate(42,'small',vegetation_density=2)
        self.assertEqual(sparse['layout']['vegetation'],[])
        self.assertGreater(len(dense['layout']['vegetation']),50)
        for key in ('roads','buildings','districts','shelter_access','vehicle_spawns'):
            self.assertEqual(sparse['layout'][key],dense['layout'][key],key)
        self.assertEqual(sparse['shelters'],dense['shelters'])

    def test_all_size_presets_and_shelter_constraints(self):
        sizes=[]; districts=[]
        for preset in world.CONFIG['presets']:
            data=self.first if preset=='small' else world.generate(42,preset)
            with self.subTest(preset=preset):
                layout=data['layout']; self.assertTrue(layout['validation']['valid'])
                self.assertEqual(layout['validation']['components'],1)
                self.assertEqual(len(data['shelters']),5)
                self.assertEqual({k:v['capacity'] for k,v in data['shelters'].items()},world.CAPACITIES)
                self.assertTrue(data['shelters']['S5']['hidden'])
                center=next(d['center'] for d in layout['districts'] if d['name']=='DOWNTOWN')
                distance=lambda k: __import__('math').dist(center,data['shelters'][k]['position'])
                self.assertGreater(distance('S4'),distance('S1')*1.5)
                self.assertGreater(distance('S5'),distance('S1')*1.5)
                metro=next(p for p in layout['infrastructure'] if p['kind']=='metro_entrance')
                self.assertEqual(metro['position'],layout['shelter_access']['S2']['road_entry'])
                self.assertGreaterEqual(layout['validation']['parking_spaces'],96)
                self.assertTrue(any(r.get('one_way') for r in layout['roads']))
                sizes.append(layout['size'][0]*layout['size'][1]); districts.append(data['settings']['district_count'])
        self.assertEqual(sizes,sorted(sizes)); self.assertEqual(districts,[7,8,10,12])

    def test_save_load_immutable_full_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'city.json'
            world.save_world(self.first,path)
            self.assertEqual(world.load_world(path),json.loads(world.encode(self.first)))
            # Loading uses saved geometry; generation is not invoked.
            from unittest.mock import patch
            with patch.object(world,'generate',side_effect=AssertionError('regenerated')):
                self.assertEqual(world.load_world(path)['world_id'],self.first['world_id'])

    def test_reject_corrupt_or_unsupported_saves(self):
        bad=copy.deepcopy(self.first); bad['layout']['buildings'][0]['rect'][0]+=10
        with self.assertRaisesRegex(ValueError,'checksum'): world.validate_world(bad)
        bad=copy.deepcopy(self.first); bad['generator_version']='future'
        with self.assertRaisesRegex(ValueError,'Unsupported'): world.validate_world(bad)
        bad=copy.deepcopy(self.first)
        bad['layout']['buildings'][1]['rect']=bad['layout']['buildings'][0]['rect']
        # A matching hash alone cannot turn overlapping geometry into a valid city.
        bad['content_hash']=world.digest({k:v for k,v in bad.items() if k not in ('world_id','content_hash')})
        bad['world_id']=f'essaim-42-{bad["content_hash"][:16]}'
        with self.assertRaises(ValueError): world.validate_world(bad)

    def test_retries_are_bounded_and_repeatable(self):
        from unittest.mock import patch
        real=world.city.generate
        seen=[]
        def fail_first(**kwargs):
            seen.append(kwargs['streams'])
            if len(seen)==1: raise ValueError('forced failed section')
            return real(**kwargs)
        with patch.object(world.city,'generate',side_effect=fail_first): data=world.generate(42,'small')
        self.assertEqual(data['attempt'],1)
        self.assertNotEqual(seen[0]['roads'],seen[1]['roads'])
        with patch.object(world.city,'generate',side_effect=ValueError('unrepairable')) as call:
            with self.assertRaisesRegex(ValueError,'exhausted'): world.generate(42,'small')
            self.assertEqual(call.call_count,world.CONFIG['max_attempts'])

    def test_invalid_settings_and_seed_rejected(self):
        for kwargs in ({'world_seed':-1},{'world_seed':True},{'preset':'tiny'},
                       {'vegetation_density':float('nan')},{'district_density':0}, {'unknown':1}):
            with self.subTest(kwargs=kwargs),self.assertRaises(ValueError): world.generate(**kwargs)

    def test_corrupt_generation_cache_is_rebuilt(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            request=Path(directory)/'request.json'; target=Path(directory)/'world.json'
            request.write_text(json.dumps(dict(world_seed=42,preset='small')))
            with patch.object(sys,'argv',['world_generation',str(request),str(target)]):
                world.main()
                identity=world.load_world(target)['world_id']
                target.write_text('{corrupt')
                world.main()
                self.assertEqual(world.load_world(target)['world_id'],identity)


if __name__=='__main__': unittest.main()
