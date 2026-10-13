"""Explicit nested allowlists: never serialize a world or director record."""
import json
import math

from .schemas import Decision
ACTIONS = ['MOVE_TO_SHELTER', 'WAIT', 'OBSERVE', 'COMMUNICATE']
FIELDS = {
    'profile': ['id', 'role', 'primary_personality', 'secondary_personality',
                'panic_level', 'trust_level', 'skepticism', 'cooperation',
                'risk_tolerance', 'self_preservation', 'empathy', 'authority_trust',
                'sociability', 'companion_id'],
    'beliefs': ['position', 'capacity', 'capacity_exact', 'size_description',
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
                if key == 'position':
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
    return result


DECISION_SCHEMA = Decision.model_json_schema()


def decision(text, obs):
    data = Decision.model_validate_json(text).model_dump()
    if data['action'] in ['MOVE_TO_SHELTER', 'CHANGE_DESTINATION'] and data['target'] not in obs['beliefs']:
        raise ValueError('Unknown shelter')
    if data['action'] in ['FOLLOW_AGENT', 'HELP_AGENT'] and data['target'] not in [a['id'] for a in obs['nearby_agents']]:
        raise ValueError('Agent not observed nearby')
    if data['action'] == 'COMMUNICATE' and not data['message'].strip():
        raise ValueError('Empty communication')
    return data
