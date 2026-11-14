import unittest
import numpy as np
from ai_service.social_population import DEFAULTS, generate, validate, experiment

class SocialPopulationTests(unittest.TestCase):
    def test_default_roles_and_identity(self):
        p=generate({}); a=p['agents']
        self.assertEqual(len(a),100)
        self.assertEqual(sum(x['role']=='Authority' for x in a),35)
        self.assertEqual(len({x['id'] for x in a}),100)
        named={x['display_name']:x for x in a if x.get('display_name')}
        self.assertEqual(set(named),{'Zack Kamili','I Am Legend'})
        self.assertEqual(named['Zack Kamili']['id'],'SPECIAL_ZACK_KAMILI')
        self.assertEqual(named['I Am Legend']['id'],'SPECIAL_I_AM_LEGEND')
        self.assertEqual(named['I Am Legend']['companion_id'],'DOG_GSD_001')
        self.assertEqual(named['I Am Legend']['visual_skin_tone'],'deep_brown')
        self.assertEqual(len({x['id'] for x in a}),100)
        self.assertTrue(all(x['role']=='Civilian' and x['age']>=18 for x in named.values()))
        self.assertEqual([named['Zack Kamili']['age'],named['I Am Legend']['age']],[32,30])
        self.assertTrue(all(x.get('personality_description') for x in named.values()))
        self.assertEqual(named['Zack Kamili']['relationships']['SPECIAL_I_AM_LEGEND'],'friend')
        self.assertEqual(named['I Am Legend']['relationships']['SPECIAL_ZACK_KAMILI'],'friend')
        self.assertEqual([sum(x['occupation']==r for x in a) for r in ('Police','Fire','Medical','Civil protection','Crisis commander')],[12,8,7,5,3])
        self.assertEqual([sum(x["role_profile"]==r for x in a) for r in ("Resident","Family member","Student","Elderly","Technician")],[25,15,10,8,7])
        self.assertEqual(p,generate({}))
        self.assertNotEqual(p,generate({'seed':43}))

    def test_normal_sampling_and_parameters(self):
        draws=[]
        for seed in range(100): draws += [a['iq'] for a in generate({'seed':seed})['agents']]
        self.assertAlmostEqual(np.mean(draws),100,delta=.6)
        self.assertAlmostEqual(np.std(draws),15,delta=.6)
        self.assertAlmostEqual(np.mean(np.abs((np.array(draws)-100)/15)<1),.683,delta=.025)
        first=generate({}); changed=generate({'iq_mean':110.,'iq_std':20.})
        for a,b in zip(first['agents'],changed['agents']):
            self.assertAlmostEqual((a['iq']-100)/15,(b['iq']-110)/20)
            self.assertEqual(a['role'],b['role'])

    def test_families_guardians_and_schools(self):
        p=generate({}); agents={a['id']:a for a in p['agents']}
        for a in agents.values():
            for relative in a['relationships']: self.assertIn(relative,agents)
            if a['age']<18:
                self.assertTrue(a['guardians'])
                for guardian in a['guardians']:
                    self.assertGreaterEqual(agents[guardian]['age'],18)
                    self.assertEqual(agents[guardian]['family_id'],a['family_id'])
                    self.assertEqual(agents[guardian]['relationships'][a['id']],'child')
        self.assertEqual(len(p['school']['students']),10)
        self.assertTrue(p['school']['staff'])
        for id in p['school']['students']: self.assertLess(agents[id]['age'],18)
        for f in p['families']:
            self.assertEqual(len(f['members']),len(set(f['members'])))

    def test_invalid_configuration(self):
        for invalid in ({'total':99},{'children':101},{'iq_std':0},{'iq_mean':float('nan')},
                        {'seed':-1},{'phone_rate':2},{'execution_mode':'blocking'},{'concurrency':0},
                        {'authorities':0,'civilians':100},{'schema_version':2},{'total':100.5}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError): validate(invalid)

    def test_small_and_custom_populations(self):
        p=generate(dict(total=1,civilians=1,authorities=0,children=0,school_students=0,
            police_vehicles=0,ambulances=0,fire_trucks=0,civil_protection_vehicles=0,llm_agents=0,named_agents_enabled=False))
        self.assertEqual(len(p['agents']),1)
        self.assertEqual(p['families'],[])
        self.assertFalse(any(x.get('display_name') for x in p['agents']))

    def test_named_agents_stay_inside_civilian_quota_and_can_be_configured(self):
        p=generate({'zack_age':45,'legend_age':41})
        named={a['display_name']:a for a in p['agents'] if a.get('display_name')}
        self.assertEqual(len(p['agents']),p['config']['total'])
        self.assertEqual(sum(a['role']=='Civilian' for a in p['agents']),p['config']['civilians'])
        self.assertEqual((named['Zack Kamili']['age'],named['I Am Legend']['age']),(45,41))
        self.assertEqual(p,generate({'zack_age':45,'legend_age':41}))
        self.assertEqual(sum(a['role']=='Civilian' for a in generate({'named_agents_enabled':False})['agents']),65)
        with self.assertRaises(ValueError): validate({'zack_age':17})
        with self.assertRaises(ValueError): validate({'dog_shelter_access_restricted':1})
        with self.assertRaises(ValueError): validate({'total':1,'civilians':1,'authorities':0})

    def test_experiments(self):
        for variant in list('ABCDEFGHIJK')+['L_sync','L_async']:
            self.assertEqual(generate(experiment(variant))['config']['total'],100)
        self.assertEqual(experiment('A')['phone_rate'],0)
        self.assertEqual(experiment('L_sync')['execution_mode'],'sync')

if __name__=='__main__': unittest.main()
