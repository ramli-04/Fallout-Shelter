"""Versioned experimental population. IQ is a synthetic, weak analytical covariate."""
import copy
import hashlib
import json
from pathlib import Path
import numpy as np

DEFAULTS = dict(schema_version=1, total=100, civilians=65, authorities=35,
    family_rate=.6, children=10, school_students=10, seed=42, iq_mean=100., iq_std=15.,
    iq_influence=.05, stress_tolerance=.55, cooperation=.6, authority_trust=.6,
    skepticism=.5, risk_tolerance=.5, sociability=.6, vehicle_rate=.45,
    police_vehicles=6, ambulances=3, fire_trucks=3, civil_protection_vehicles=2, traffic_density=.5,
    vehicles_in_use_rate=.3, vehicle_collisions=True, accident_probability=.0002, roadblock_frequency=.3, phone_rate=.95,
    social_adoption=.65, rumor_probability=.2, credibility_sensitivity=.6,
    network_availability=.95, alert_reach=.95, warning_min=300, warning_max=600,
    simulation_speed=1, random_impact=True, shelter_availability=1., event_frequency=1.,
    llm_agents=30, inference_interval=12., concurrency=8, execution_mode='async',
    group_a='A', group_b='B', group_c='C', family_priority=.65,
    provider_concurrency=2, provider_a='ollama', provider_b='ollama', provider_c='ollama',
    model_a='qwen2.5:0.5b', model_b='llama3.2:1b', model_c='qwen2.5:1.5b', pre_disaster_seconds=180., automatic_warning=True, day_start_hour=8., routine_clock_rate=60., spontaneous_actions=True,
    named_agents_enabled=True, zack_age=32, legend_age=30, dog_shelter_access_restricted=False)

def validate(config):
    c = copy.deepcopy(DEFAULTS)
    if not isinstance(config, dict) or set(config) - set(c):
        raise ValueError('Unknown configuration fields')
    c.update(config)
    for k, default in DEFAULTS.items():
        v = c[k]
        if isinstance(default, bool):
            if not isinstance(v, bool): raise ValueError(k + ' must be boolean')
        elif isinstance(default, (int, float)):
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not np.isfinite(v):
                raise ValueError(k + ' must be finite')
            if isinstance(default, int):
                if int(v) != v: raise ValueError(k + ' must be integer')
                c[k] = int(v)
    if not 0<=c['pre_disaster_seconds']<=86400 or not 0<=c['day_start_hour']<24 or not 1<=c['routine_clock_rate']<=3600: raise ValueError('Invalid daily routine timing')
    if not 18 <= c['zack_age'] <= 100 or not 18 <= c['legend_age'] <= 100: raise ValueError('Named civilian ages must be 18-100')
    if c['schema_version'] != 1: raise ValueError('Unsupported schema version')
    if not 1 <= c['total'] <= 400 or min(c['civilians'], c['authorities']) < 0 or c['civilians'] + c['authorities'] != c['total']:
        raise ValueError('Civilians + authorities must equal total (1–400)')
    if not 0 <= c['school_students'] <= c['children'] <= c['civilians'] or c['children'] and c['total']-c['children'] < 1:
        raise ValueError('Students ≤ children ≤ civilians; children need adult guardians')
    if c['named_agents_enabled'] and c['civilians'] - c['children'] < 2:
        raise ValueError('Named agents require at least two adult civilian slots; disable named_agents_enabled for smaller test populations')
    for k in ('family_rate','iq_influence','stress_tolerance','cooperation','authority_trust','skepticism','risk_tolerance','sociability','vehicle_rate','vehicles_in_use_rate','traffic_density','accident_probability','roadblock_frequency','phone_rate','social_adoption','rumor_probability','credibility_sensitivity','network_availability','alert_reach','shelter_availability','family_priority'):
        if not 0 <= c[k] <= 1: raise ValueError(k + ' must be in [0,1]')
    for k in ('police_vehicles','ambulances','fire_trucks','civil_protection_vehicles'):
        if not 0 <= c[k] <= c['authorities']: raise ValueError(k + ' exceeds authority population')
    if sum(c[k] for k in ('police_vehicles','ambulances','fire_trucks','civil_protection_vehicles')) > c['authorities']:
        raise ValueError('Emergency vehicles require distinct authority drivers')
    if not 0 <= c['llm_agents'] <= c['total']-c['children'] or not 1 <= c['concurrency'] <= 120:
        raise ValueError('Invalid AI population or concurrency')
    if c['iq_influence']>.1: raise ValueError('Synthetic IQ influence must be at most 0.1')
    if not 1<=c['provider_concurrency']<=16: raise ValueError('Provider concurrency must be 1-16')
    if not 1 <= c['iq_mean'] <= 200 or not 0 < c['iq_std'] <= 50: raise ValueError('Invalid IQ parameters')
    if not 30 <= c['warning_min'] <= c['warning_max'] <= 3600: raise ValueError('Invalid warning interval')
    if c['simulation_speed'] not in (1,2,5,10) or c['execution_mode'] not in ('async','sync'):
        raise ValueError('Invalid speed or execution mode')
    if not 1 <= c['inference_interval'] <= 300 or not 0 <= c['event_frequency'] <= 10:
        raise ValueError('Invalid scheduling interval')
    if not 0 <= c['seed'] <= 2147483647: raise ValueError('Invalid seed')
    if any(c[k] not in ('A','B','C','rules') for k in ('group_a','group_b','group_c')):
        raise ValueError('Provider assignment must reference a configured backend group or rules')
    for suffix in 'abc':
        if c['provider_'+suffix] not in ('ollama','gemini','grok','openai'): raise ValueError('Unknown provider')
        if not isinstance(c['model_'+suffix],str) or not 1<=len(c['model_'+suffix])<=120: raise ValueError('Invalid model')
    return c

def quotas(total, weights):
    raw = np.array(weights, dtype=float) * total / sum(weights)
    result = np.floor(raw).astype(int)
    for i in np.argsort(-(raw-result), kind='stable')[:total-int(result.sum())]: result[i] += 1
    return result.tolist()

def generate(config):
    c = validate(config)
    streams = [np.random.default_rng(s) for s in np.random.SeedSequence(c['seed']).spawn(5)]
    iq_rng, role_rng, mind_rng, family_rng, device_rng = streams
    # Draw independently of occupations and family membership; never stratify IQ.
    iq = iq_rng.normal(c['iq_mean'], c['iq_std'], int(c['total']))
    roles = ['Authority']*int(c['authorities']) + ['Civilian']*int(c['civilians'])
    role_rng.shuffle(roles)
    authority_jobs = sum(([job]*n for job,n in zip(['Police','Fire','Medical','Civil protection','Crisis commander'], quotas(c['authorities'], [12,8,7,5,3]))), [])
    civilian_jobs = sum(([job]*n for job,n in zip(['Resident','Family member','Student','Elderly','Technician'], quotas(c['civilians'], [25,15,10,8,7]))), [])
    role_rng.shuffle(authority_jobs); role_rng.shuffle(civilian_jobs)
    agents = []
    for i, role in enumerate(roles):
        job = (authority_jobs if role == 'Authority' else civilian_jobs).pop()
        a = dict(id=f'A{i+1:03d}', population_index=i, name=f"{['Nour','Amine','Salma','Idris','Yasmine','Sami','Lina','Adam','Maya','Ilyas','Sara','Nabil','Ines','Rayan','Aya','Omar','Leila','Younes','Meriem','Anas'][i%20]} {['Mansouri','Rami','Amrani','Nouri','Bennani'][i//20%5]}", role=role, occupation=job,
            specialization=job if role == 'Authority' else '', role_profile=job, age=int(mind_rng.integers(20,66)),
            iq=float(iq[i]), family_id='', relationships={}, guardians=[], home_uv=mind_rng.uniform(.08,.85,2).tolist(),
            school='', workplace=job, has_phone=bool(device_rng.random()<c['phone_rate']),
            social_user=bool(device_rng.random()<c['social_adoption']), owns_vehicle=bool(device_rng.random()<c['vehicle_rate']),
            model_tier=c[('group_a','group_b','group_c')[i%3]], llm_enabled=i<c['llm_agents'])
        if job == 'Elderly': a['age'] = int(mind_rng.integers(66,89))
        for trait in ('stress_tolerance','cooperation','authority_trust','skepticism','risk_tolerance','sociability','courage','empathy','leadership','adaptability'):
            a[trait] = float(np.clip(mind_rng.normal(c.get(trait,.5),.16),0,1)*100)
        agents.append(a)
    civilians = [a for a in agents if a['role']=='Civilian']
    family_rng.shuffle(civilians)
    children = civilians[:int(c['children'])]
    adults = [a for a in agents if a not in children]
    family_rng.shuffle(adults)
    for i, child in enumerate(children):
        child.update(age=int(family_rng.integers(6,17)), occupation='School student', workplace='SCHOOL',
            school='SCHOOL' if i<c['school_students'] else '', owns_vehicle=False)
    if c['named_agents_enabled']:
        adult_civilians = [a for a in agents if a['role'] == 'Civilian' and a not in children]
        if len(adult_civilians) < 2:
            raise ValueError('Named agents require at least two adult civilian slots')
        named = [
            (adult_civilians[0], 'SPECIAL_ZACK_KAMILI', 'Zack Kamili', c['zack_age'], 'Thoughtful, practical, and observant', ''),
            (adult_civilians[1], 'SPECIAL_I_AM_LEGEND', 'I Am Legend', c['legend_age'], 'Independent, compassionate, and protective', 'deep_brown'),
        ]
        for agent, identity, display_name, age, description, skin_tone in named:
            agent.update(id=identity, name=display_name, display_name=display_name, age=age,
                personality_description=description, visual_skin_tone=skin_tone, gender='male')
        named[1][0]['companion_id'] = 'DOG_GSD_001'
        named[1][0]['companion_attachment'] = 0.98
        if c['family_rate'] > 0 and named[1][0]['id'] not in named[0][0]['relationships']:
            named[0][0]['relationships'][named[1][0]['id']] = 'friend'
            named[1][0]['relationships'][named[0][0]['id']] = 'friend'
    families = []
    def make_family(members):
        identity = f'F{len(families)+1:03d}'
        home = members[0]['home_uv']
        for a in members: a.update(family_id=identity, home_uv=home)
        families.append(dict(id=identity, members=[a['id'] for a in members], home_uv=home))
    # Every minor has an adult guardian, even if requested family percentage is lower.
    for i, child in enumerate(children):
        guardian = adults[(i//2)%len(adults)]
        guardian["age"]=max(guardian["age"],child["age"]+18)
        if not guardian['family_id']: make_family([guardian,child])
        else:
            f = next(f for f in families if f['id']==guardian['family_id'])
            f['members'].append(child['id']); child.update(family_id=f['id'], home_uv=f['home_uv'])
        child['guardians']=[guardian['id']]
        child['relationships'][guardian['id']]='parent'
        guardian['relationships'][child['id']]='child'
    available = [a for a in adults if not a['family_id']]
    for f in families[:max(1,len(families)//2)]:
        if not available: break
        partner=available.pop()
        parent=next(a for a in agents if a['id']==f['members'][0])
        partner.update(family_id=f['id'],home_uv=f['home_uv'])
        f['members'].append(partner['id'])
        partner['relationships'][parent['id']]='spouse'; parent['relationships'][partner['id']]='spouse'
        for child in children:
            if child['family_id']==f['id']:
                child['guardians'].append(partner['id']); child['relationships'][partner['id']]='parent'
                partner['relationships'][child['id']]='child'; partner['age']=max(partner['age'],child['age']+18)
    if families:
        elder=next((a for a in available if a['age']>=66),None)
        if elder:
            f=families[0]; available.remove(elder); f['members'].append(elder['id'])
            elder.update(family_id=f['id'],home_uv=f['home_uv'])
            for child in children:
                if child['family_id']==f['id']:
                    elder['relationships'][child['id']]='grandchild'; child['relationships'][elder['id']]='grandparent'
    target = max(len(children), round(c['family_rate']*c['total']))
    while len(available)>=2 and sum(bool(a['family_id']) for a in agents)<target:
        a,b = available.pop(),available.pop()
        make_family([a,b]); a['relationships'][b['id']]='spouse'; b['relationships'][a['id']]='spouse'
    for f in families:
        minors = [a for a in children if a['id'] in f['members']]
        for a in minors:
            for b in minors:
                if a!=b: a['relationships'][b['id']]='sibling'
    eligible=[a for a in agents if a['age']>=18 and a['model_tier']!='rules']
    if len(eligible)<c['llm_agents']: raise ValueError('Not enough adult agents assigned to LLM provider groups')
    for a in agents: a['llm_enabled']=False
    for a in eligible[:c['llm_agents']]: a['llm_enabled']=True
    students=[a['id'] for a in children if a['school']]
    staff = next((a for a in adults if a['role']=='Civilian'), adults[0] if adults else None)
    if students and staff: staff['workplace']='SCHOOL'; staff['school']='SCHOOL_STAFF'
    digest=hashlib.sha256(json.dumps(c,sort_keys=True).encode()).hexdigest()
    return dict(schema_version=1, numpy_version=np.__version__, rng_algorithm='PCG64', config=c, config_hash=digest, agents=agents, families=families,
        school=dict(id='SCHOOL', students=students, staff=[staff['id']] if students and staff else []),
        iq_stats=dict(mean=float(iq.mean()), std=float(iq.std()), histogram=np.histogram(iq,bins=[-np.inf,55,70,85,100,115,130,145,np.inf])[0].tolist()))

def experiment(name, config=None):
    c=validate(config or {})
    variants={'A':dict(phone_rate=0,social_adoption=0), 'B':dict(phone_rate=.95,social_adoption=0),
        'C':dict(phone_rate=.95,social_adoption=.8), 'D':dict(rumor_probability=.9),
        'E':dict(authority_trust=.9), 'F':dict(authority_trust=.1), 'G':dict(roadblock_frequency=.9),
        'H':dict(vehicle_rate=.9,traffic_density=.95), 'I':dict(family_priority=.95),
        'J':dict(family_priority=.05), 'K':dict(llm_agents=c['total']//2), 'L_sync':dict(execution_mode='sync'),
        'L_async':dict(execution_mode='async')}
    if name not in variants: raise ValueError('Unknown social experiment')
    return validate(dict(c,**variants[name]))

if __name__ == '__main__':
    import argparse
    p=argparse.ArgumentParser(); p.add_argument('--config',default='resources/social_config.json'); p.add_argument('--output',default='resources/social_population.json')
    args=p.parse_args()
    Path(args.output).write_text(json.dumps(generate(json.loads(Path(args.config).read_text())),indent=2),encoding='utf-8')
