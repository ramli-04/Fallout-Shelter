"""Bounded live journal with a persistent append-only JSONL archive."""
import copy
import json
import os
import threading
import uuid
from collections import OrderedDict, deque
from datetime import datetime, timezone
from pathlib import Path


class TraceStore:
    def __init__(self, path=None, capacity=300):
        self.path = Path(path or os.getenv('LLM_TRACE_PATH', 'outputs/ai_backend_runs/inference_traces.jsonl'))
        self.capacity = capacity
        self.lock = threading.Lock()
        self.records = OrderedDict()
        self.write_error = ''
        if self.path.exists():
            with self.path.open(encoding='utf-8') as stream:
                for line in deque(stream, maxlen=capacity * 2):
                    try:
                        record = json.loads(line)
                        self.records[record['trace_id']] = record
                        self.records.move_to_end(record['trace_id'])
                    except (ValueError, KeyError):
                        continue
            while len(self.records) > capacity: self.records.popitem(last=False)
            for record in self.records.values():
                if record.get('status') == 'RUNNING':
                    record.update(status='INTERRUPTED', error='Service restarted before an answer was recorded')

    def start(self, **record):
        identity = uuid.uuid4().hex
        self.update(identity, **record, status='RUNNING', started_at=datetime.now(timezone.utc).isoformat())
        return identity

    def update(self, identity, **values):
        with self.lock:
            record = dict(self.records.get(identity, {}), trace_id=identity, **copy.deepcopy(values))
            self.records[identity] = record
            self.records.move_to_end(identity)
            while len(self.records) > self.capacity: self.records.popitem(last=False)
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                with self.path.open('a', encoding='utf-8') as stream:
                    stream.write(json.dumps(record, ensure_ascii=False, allow_nan=False) + '\n')
                self.write_error = ''
            except (OSError, ValueError) as error:
                self.write_error = str(error)

    def list(self, model=None, agent=None, run=None, limit=100):
        with self.lock:
            matches = [copy.deepcopy(r) for r in reversed(self.records.values())
                if (not model or r.get('model') == model)
                and (not agent or r.get('agent_id') == agent)
                and (not run or r.get('run_id') == run)]
            return matches[:limit]
