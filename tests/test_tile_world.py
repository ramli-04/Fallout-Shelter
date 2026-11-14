import unittest
from shapely import box
from ai_service.tile_world import Occupancy, manifest, TILE_SIZE, CHUNK_TILES
from ai_service.city_generator import generate

class TileWorldTests(unittest.TestCase):
    def test_cell_reservations_and_shared_edges(self):
        grid=Occupancy()
        grid.reserve(box(0,0,80,80),'road')
        self.assertFalse(grid.can_place(box(40,40,120,120)))
        self.assertTrue(grid.can_place(box(80,0,160,80)))
        self.assertEqual(grid.footprint(box(0,0,80,80)),(0,0,2,2))

    def test_cross_chunk_ownership_and_empty_chunks(self):
        data={'seed':42,'size':[3600,2400],'roads':[],'parking_lots':[],
              'buildings':[{'rect':[1160,1160,120,120],'district':'RESIDENTIAL'}]}
        result=manifest(data)
        self.assertEqual(len(result['chunks']),6)
        owners=[c for c in result['chunks'] if 'building:0' in c['owned_entities']]
        touched=[c for c in result['chunks'] if 'building:0' in c['entities']]
        self.assertEqual(len(owners),1)
        self.assertEqual(len(touched),4)
        self.assertEqual(result['entities'][0]['footprint'],[3,3])
        self.assertEqual(result,manifest(data))

    def test_real_generation_cells_have_no_building_or_road_overlap(self):
        for seed in (1,42):
            data=generate(seed); result=data['tile_world']; occupied=set(); roads=set()
            self.assertEqual(result['asset_modules']['road'],[2,2])
            for e in result['entities']:
                if e['kind']!='building':continue
                x,y=e['tile_origin'];w,h=e['footprint']
                cells={(a,b) for a in range(x,x+w) for b in range(y,y+h)}
                self.assertFalse(cells & occupied); occupied.update(cells)
            for c in result['chunks']:
                x,y=c['coordinate']
                roads.update((x*CHUNK_TILES+a,y*CHUNK_TILES+b) for a,b in c['layers'].get('road',[]))
            self.assertFalse(roads & occupied)
