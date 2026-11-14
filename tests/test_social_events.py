import sqlite3
import unittest
from ai_service.social_events import SocialEvent, SocialEventStore, EVENT_TYPES
from ai_service.contracts import observation

class SocialEventsTests(unittest.TestCase):
    def event(self,kind='phone.message_sent'):
        return dict(schema_version=1,event_id='run:1',run_id='run',event_type=kind,
            simulation_timestamp=12.,wall_timestamp='2026-10-27T12:00:00Z',source_entity='A001',payload={'recipient':'A002'})

    def test_schemas_and_idempotence(self):
        db=sqlite3.connect(':memory:'); store=SocialEventStore(db)
        for kind in EVENT_TYPES: self.assertEqual(SocialEvent.model_validate(self.event(kind)).event_type,kind)
        self.assertTrue(store.accept(self.event()))
        self.assertFalse(store.accept(self.event()))
        self.assertEqual(len(store.pending()),1)
        store.mark_published('run:1'); self.assertEqual(store.pending(),[])
        with self.assertRaises(ValueError): store.accept(dict(self.event(),payload={'changed':True}))
        for data in (dict(self.event(),schema_version=2),dict(self.event(),simulation_timestamp=float('inf')),
                     dict(self.event(),event_type='invalid'),dict(self.event(),wall_timestamp='2026-01-01')):
            with self.assertRaises(ValueError): SocialEvent.model_validate(data)
        db.close()

    def test_private_social_allowlists(self):
        packet=dict(profile={'id':'A001','role':'Civilian','iq':101,'hidden':'SECRET'},position=[1,2],
            simulation_time=1.,estimated_time_remaining=300.,family_relationships={'A002':'child'},
            social_beliefs={'school_status':dict(subject='school',claimed_value='evacuated',source='A002',
                confidence=.5,private_memory='SECRET')},
            known_family_locations={'A002':dict(position=[3,4],source='text',timestamp=1.,confidence=.8,secret='SECRET')},
            received_phone_messages=[dict(sender='A002',recipient='A001',channel='text',content=dict(subject='family',value='hello',world={'secret':True}))],
            nuclear={'impact':[10,20]},families={'secret':True})
        result=observation(packet)
        self.assertNotIn('SECRET',str(result)); self.assertNotIn('nuclear',result); self.assertNotIn('families',result)
        self.assertEqual(result['known_family_locations']['A002']['position'],[3,4])
        self.assertNotIn('world',result['received_phone_messages'][0]['content'])
        packet['profile']['iq']={'private':True}
        with self.assertRaises(ValueError): observation(packet)

if __name__=='__main__': unittest.main()
