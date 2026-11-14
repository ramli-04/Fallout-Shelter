"""Versioned social event validation and idempotent durable ingestion."""
import json
import sqlite3
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field, field_validator

EVENT_TYPES = ('building.entered','building.exited','routine.changed','family.travel_planned','family.negotiated','family.left_behind','family.boarded','school.pickup_started','school.pickup_completed','agent.spontaneous_action','vehicle.driving_decision','agent.observation','agent.belief_updated','agent.decision','family.member_missing',
    'family.reunited','phone.call_started','phone.call_ended','phone.message_sent','social.post_created',
    'social.rumor_shared','authority.alert_issued','authority.order_issued','roadblock.created',
    'roadblock.removed','vehicle.departed','vehicle.arrived','vehicle.accident','traffic.congestion',
    'school.evacuation_started','school.evacuation_completed','traffic.casualty',
    'emergency.evacuation_started','emergency.patient_evacuated','emergency.dispatched','emergency.scene_secured','emergency.treatment_started','traffic.recovered')

class SocialEvent(BaseModel):
    model_config=ConfigDict(extra='forbid')
    schema_version: int = Field(ge=1,le=1)
    event_id: str = Field(min_length=1,max_length=180)
    run_id: str = Field(min_length=1,max_length=128)
    event_type: str
    simulation_timestamp: float = Field(ge=0,allow_inf_nan=False)
    wall_timestamp: str
    source_entity: str = Field(min_length=1,max_length=64)
    payload: dict

    @field_validator('event_type')
    @classmethod
    def known_type(cls,v):
        if v not in EVENT_TYPES: raise ValueError('Unknown social event type')
        return v

    @field_validator('wall_timestamp')
    @classmethod
    def timestamp(cls,v):
        if datetime.fromisoformat(v.replace('Z','+00:00')).tzinfo is None: raise ValueError('Timezone required')
        return v

    @field_validator('payload')
    @classmethod
    def bounded_payload(cls,v):
        if len(json.dumps(v,allow_nan=False))>65536: raise ValueError('Event too large')
        return v

class SocialEventStore:
    def __init__(self, db):
        self.db=db
        db.execute('CREATE TABLE IF NOT EXISTS social_events (id TEXT PRIMARY KEY, run TEXT, source TEXT, data TEXT, published INTEGER DEFAULT 0)')
        db.commit()

    def accept(self,event):
        data=SocialEvent.model_validate(event).model_dump()
        existing=self.db.execute('SELECT data FROM social_events WHERE id=?',(data['event_id'],)).fetchone()
        encoded=json.dumps(data,sort_keys=True,allow_nan=False)
        if existing:
            if existing[0]!=encoded: raise ValueError('Event ID reused with different payload')
            return False
        self.db.execute('INSERT INTO social_events(id,run,source,data) VALUES (?,?,?,?)',
            (data['event_id'],data['run_id'],data['source_entity'],encoded))
        self.db.commit()
        return True

    def pending(self,limit=128):
        return [json.loads(row[0]) for row in self.db.execute('SELECT data FROM social_events WHERE published=0 ORDER BY rowid LIMIT ?',(limit,))]

    def mark_published(self,identity):
        self.db.execute('UPDATE social_events SET published=1 WHERE id=?',(identity,)); self.db.commit()
