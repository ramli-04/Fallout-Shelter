import copy
import tempfile
import unittest
from unittest.mock import patch
from ai_service.generation_pipeline import ArtifactCache,GenerationPipeline,Stage
from ai_service.world_generation import generate,validate_layout
from shapely import LineString,box

class GenerationPipelineTests(unittest.TestCase):
    def test_priority_only_orders_ready_dependencies(self):
        visited=[]
        def build(inputs,deps): visited.append(inputs['name']); return inputs['name']
        pipeline=GenerationPipeline([Stage('decor',('shelters',),999,build),Stage('roads',('shelters',),50,build),
                                     Stage('shelters',('terrain',),100,build),Stage('terrain',(),1,build)])
        pipeline.run({name:dict(name=name) for name in pipeline.stages})
        self.assertEqual(visited,['terrain','shelters','decor','roads'])
        # Independent priorities can change without violating the shelter prerequisite.
        changed=GenerationPipeline([Stage('decor',('shelters',),1,build),Stage('roads',('shelters',),1000,build),
                                    Stage('shelters',('terrain',),100,build),Stage('terrain',(),1,build)])
        self.assertEqual(changed.order(),['terrain','shelters','roads','decor'])

    def test_invalid_graph_rejected_before_work(self):
        def fail(*_): raise AssertionError('executed before graph validation')
        for stages in ([Stage('a',('missing',),1,fail)],
                       [Stage('a',('b',),1,fail),Stage('b',('a',),1,fail)],
                       [Stage('a',(),1,fail),Stage('a',(),1,fail)]):
            with self.assertRaises(ValueError): GenerationPipeline(stages).run({})

    def test_incremental_artifacts_survive_process_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            cache=ArtifactCache(directory)
            first=generate(42,'small',artifact_cache=cache,vegetation_density=0)
            from ai_service import city_generator
            with patch.object(city_generator,'generate',side_effect=AssertionError('rebuilding roads')):
                second=generate(42,'small',artifact_cache=ArtifactCache(directory),vegetation_density=2)
            self.assertEqual(first['layout']['roads'],second['layout']['roads'])
            self.assertEqual(first['layout']['shelter_access'],second['layout']['shelter_access'])
            self.assertNotEqual(first['layout']['vegetation'],second['layout']['vegetation'])
            self.assertEqual(second,generate(42,'small',vegetation_density=2))

    def test_final_shelter_reservations_drive_real_roads(self):
        for seed in [0,2,42,43]:
            world=generate(seed,'small'); layout=world['layout']
            self.assertLess(world['stages'].index('shelters'),world['stages'].index('layout'))
            self.assertTrue(validate_layout(layout)['valid'])
            for name,plaza in layout['shelter_access'].items():
                r=plaza['bounds']; shape=box(r[0],r[1],r[0]+r[2],r[1]+r[3])
                self.assertEqual(tuple(plaza['road_entry']),tuple(layout['sites'][name]))
                for road in layout['roads']:
                    self.assertFalse(shape.intersects(LineString(road['points']).buffer(road['width']/2+road['sidewalk'])))

if __name__=='__main__': unittest.main()
