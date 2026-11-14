"""Explicit nested allowlists: never serialize a world or director record."""
import json
import math

from .schemas import Decision
ACTIONS = ['MOVE_TO_SHELTER', 'WAIT', 'OBSERVE', 'COMMUNICATE', 'DANCE', 'FLEE_RANDOMLY', 'HELP_AGENT', 'FOLLOW_AGENT',
           'CALL', 'TEXT', 'POST', 'FIND_FAMILY', 'DRIVE_TO_SHELTER', 'CREATE_ROADBLOCK', 'REMOVE_ROADBLOCK', 'ISSUE_ALERT']
FIELDS = {
    'profile': ['id', 'role', 'primary_personality', 'secondary_personality',
                'panic_level', 'trust_level', 'skepticism', 'cooperation',
                'risk_tolerance', 'self_preservation', 'empathy', 'authority_trust',
                'sociability', 'companion_id', 'courage', 'leadership', 'name', 'age', 'occupation', 'iq',
                'stress_tolerance', 'adaptability', 'family_id', 'fatigue', 'health', 'family_concern', 'home_location', 'workplace', 'school', 'has_phone', 'social_user', 'vehicle_id', 'safety', 'social_attachment', 'stress', 'routine', 'location_mode'],
    'beliefs': ['accessible', 'safety_status', 'subject','claimed_value','acquired_at','status','position', 'capacity', 'capacity_exact', 'size_description',
                'estimated_occupancy', 'resource_score', 'risk', 'popularity',
                'official_support', 'existence_probability', 'confidence',
                'unavailable', 'observed_at', 'source', 'last_update_time',
                'evidence_type', 'original_source'],
    'memories': ['time', 'text'],
    'messages': ['rumor_id', 'claim', 'original_source', 'current_speaker',
                 'timestamp', 'perceived_credibility', 'hops', 'kind', 'shelter_id',
                 'reaction'],
    'nearby_agents': ['id', 'role', 'position', 'state'],
}


def pick(record, fields):
    if not isinstance(record, dict):
        raise ValueError('Expected observation object')
    return {key: record[key] for key in fields if key in record}


def observation(raw):
    result = pick(raw, ['position', 'destination', 'goal', 'estimated_time_remaining',
                        'simulation_time', 'trust_relationships'])
    result['profile'] = pick(raw.get('profile', {}), FIELDS['profile'])
    if not result['profile'].get('id') or result['profile'].get('role') not in ['Civilian', 'Authority']:
        raise ValueError('Missing agent identity or valid role')
    result['beliefs'] = {key: pick(value, FIELDS['beliefs'])
                         for key, value in raw.get('beliefs', {}).items()
                         if key in ['S1', 'S2', 'S3', 'S4', 'S5']}
    exclusions = raw.get('excluded_shelters', [])
    if not isinstance(exclusions, list) or any(not isinstance(key, str) for key in exclusions):
        raise ValueError('Invalid shelter exclusions')
    result['excluded_shelters'] = [key for key in exclusions[:5] if key in result['beliefs']]
    verified_required = raw.get('requires_verified_shelter', False)
    if not isinstance(verified_required, bool): raise ValueError('Invalid shelter verification rule')
    result['requires_verified_shelter'] = verified_required
    for key, limit in [('memories', 12), ('messages', 8), ('nearby_agents', 20)]:
        result[key] = [pick(item, FIELDS[key]) for item in raw.get(key, [])[-limit:]]
    # Relationships are source IDs and numeric trust, not arbitrary nested objects.
    result['trust_relationships'] = {
        str(key)[:64]: value for key, value in result.get('trust_relationships', {}).items()
        if type(value) in (int, float) and math.isfinite(value) and 0 <= value <= 1}
    # Reject complex values smuggled into otherwise permitted scalar fields.
    for group in ['profile', 'beliefs', 'memories', 'messages', 'nearby_agents']:
        records = ([result[group]] if group == 'profile' else list(result[group].values())
                   if group == 'beliefs' else result[group])
        for record in records:
            for key, value in record.items():
                if key in ('position','home_location'):
                    if not isinstance(value, list) or len(value) != 2 or any(type(v) not in (int, float) or not math.isfinite(v) for v in value):
                        raise ValueError('Invalid position')
                elif not isinstance(value, (str, int, float, bool, type(None))):
                    raise ValueError('Nested observation field rejected')
                elif isinstance(value, str) and len(value) > 800:
                    record[key] = value[:800]
    for key in ['destination', 'goal']:
        if key in result and not isinstance(result[key], str):
            raise ValueError('Invalid observation text')
    for key in ['simulation_time', 'estimated_time_remaining']:
        if type(result.get(key)) not in (int, float) or not math.isfinite(result[key]):
            raise ValueError('Invalid observation time')
    point = result.get('position')
    if not isinstance(point, list) or len(point) != 2 or any(type(v) not in (int, float) or not math.isfinite(v) for v in point):
        raise ValueError('Invalid agent position')
    # Social records originate in the private Godot observation builder. Keep explicit
    # nested allowlists and limits; no Director families, live positions or traffic map.
    def scalar(value):
        if type(value) in (int, float):
            if not math.isfinite(value): raise ValueError('Nonfinite social value')
            return value
        if isinstance(value, str): return value[:800]
        if value is None or isinstance(value, bool): return value
        raise ValueError('Nested social scalar rejected')
    result['family_relationships'] = {str(k)[:64]: scalar(v) for k,v in raw.get('family_relationships',{}).items()}
    result['social_beliefs'] = {str(k)[:100]: {field:scalar(v) for field,v in record.items()
        if field in ('subject','claimed_value','source','acquired_at','confidence','evidence','last_update','status') and not isinstance(v,(dict,list))}
        for k,record in list(raw.get('social_beliefs',{}).items())[-32:]}
    result['known_family_locations'] = {}
    for identity, record in list(raw.get('known_family_locations',{}).items())[:30]:
        location=record.get('position')
        if not isinstance(location,list) or len(location)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) for v in location):
            raise ValueError('Invalid remembered family position')
        result['known_family_locations'][str(identity)[:64]] = dict(position=location,
            **{k:scalar(v) for k,v in record.items() if k in ('source','timestamp','confidence')})
    result['received_phone_messages'] = []
    for message in raw.get('received_phone_messages',[])[-8:]:
        body=message.get('content',{})
        result['received_phone_messages'].append(dict(
            **{k:scalar(v) for k,v in message.items() if k in ('id','sender','recipient','timestamp','channel')},
            content={k:scalar(v) for k,v in body.items() if k in ('subject','value','message','alert_id') and not isinstance(v,(dict,list))}))
    # Local sensors are projected by Godot, never copied from director world records.
    for group in ('perceptions', 'experience'):
        result[group] = []
        records = raw.get(group, [])
        if not isinstance(records, list):
            raise ValueError('Invalid sensor collection')
        for record in records[-24:]:
            item = pick(record, ('kind', 'id', 'position', 'distance', 'severity',
                                 'confidence', 'timestamp', 'speed', 'heading', 'state'))
            point = item.get('position')
            if not isinstance(point, list) or len(point) != 2 or any(
                    type(v) not in (int, float) or not math.isfinite(v) for v in point):
                raise ValueError('Invalid sensor position')
            for key in ('distance', 'severity', 'confidence', 'timestamp'):
                value = item.get(key)
                if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                    raise ValueError('Invalid sensor number')
            if item['severity'] > 1 or item['confidence'] > 1:
                raise ValueError('Invalid sensor probability')
            for key in ('kind', 'id', 'state'):
                if key in item:
                    if not isinstance(item[key], str): raise ValueError('Invalid sensor text')
                    item[key] = item[key][:100]
            for key in ('speed', 'heading'):
                if key in item and (type(item[key]) not in (int, float) or not math.isfinite(item[key])):
                    raise ValueError('Invalid sensor motion')
            result[group].append(item)
    traits = raw.get('cognitive_traits', {})
    if not isinstance(traits, dict): raise ValueError('Invalid cognitive traits')
    result['cognitive_traits'] = {}
    for key in ('fear', 'courage', 'aggression', 'altruism', 'risk_tolerance', 'curiosity',
                'sociability', 'trust', 'self_preservation', 'family_attachment'):
        if key in traits:
            value = traits[key]
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 100:
                raise ValueError('Invalid cognitive trait')
            result['cognitive_traits'][key] = value
    return result


DECISION_SCHEMA = Decision.model_json_schema()


def decision(text, obs):
    data = Decision.model_validate_json(text).model_dump()
    if data['action'] in ['MOVE_TO_SHELTER', 'CHANGE_DESTINATION', 'DRIVE_TO_SHELTER'] and data['target'] in obs.get('excluded_shelters', []):
        raise ValueError('Shelter excluded by active evacuation')
    if data['action'] in ['MOVE_TO_SHELTER', 'CHANGE_DESTINATION', 'DRIVE_TO_SHELTER'] and obs.get('requires_verified_shelter'):
        belief = obs['beliefs'].get(data['target'], {})
        if (belief.get('existence_probability', 0) < 1 or belief.get('confidence', 0) < .7 or
                belief.get('safety_status') != 'SAFE' or belief.get('unavailable', False)):
            raise ValueError('Shelter not verified safe for transfer')
    if data['action'] in ['MOVE_TO_SHELTER', 'CHANGE_DESTINATION'] and data['target'] not in obs['beliefs']:
        raise ValueError('Unknown shelter')
    if data['action'] in ['FOLLOW_AGENT', 'HELP_AGENT'] and data['target'] not in [a['id'] for a in obs['nearby_agents']]:
        raise ValueError('Agent not observed nearby')
    if data['action'] == 'COMMUNICATE' and not data['message'].strip():
        raise ValueError('Empty communication')
    if data['action'] == 'COMMUNICATE' and data['target'] and data['target'] not in [a['id'] for a in obs['nearby_agents']]:
        raise ValueError('Communication recipient not observed nearby')
    if data['action'] in ('FIND_FAMILY','CALL','TEXT') and data['target'] not in obs.get('family_relationships',{}):
        raise ValueError('Unknown family contact')
    if data['action'] == 'DRIVE_TO_SHELTER' and data['target'] not in obs['beliefs']:
        raise ValueError('Unknown shelter')
    if data['action'] in ('CREATE_ROADBLOCK','REMOVE_ROADBLOCK','ISSUE_ALERT') and obs['profile']['role']!='Authority':
        raise ValueError('Authority action forbidden')
    return data
