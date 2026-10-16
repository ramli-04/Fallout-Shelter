"""Kafka transport and durable decision identity ledger; Kafka never schedules GPUs."""
import asyncio
import hashlib
import json
import os
import uuid
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from .engine import BusyError

TOPICS = ('agent.observations', 'agent.decision_requests', 'agent.decisions',
          'agent.communications', 'world.events', 'shelter.events', 'simulation.metrics')


class EventBus:
    def __init__(self):
        self.producer = None
        self.consumer = None
        self.status = 'DISABLED'
        self.last_error = ''
        self.waiters = {}

    async def start(self, callback):
        if os.getenv('KAFKA_ENABLED', 'false').lower() != 'true':
            return
        from aiokafka import AIOKafkaProducer, AIOKafkaConsumer
        from aiokafka.admin import AIOKafkaAdminClient, NewTopic
        from aiokafka.errors import TopicAlreadyExistsError
        address = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
        try:
            admin = AIOKafkaAdminClient(bootstrap_servers=address)
            await admin.start()
            try:
                for topic in TOPICS:
                    try:
                        await admin.create_topics([NewTopic('essaim.' + topic, 30, 1)])
                    except TopicAlreadyExistsError:
                        pass
            finally:
                await admin.close()
            self.producer = AIOKafkaProducer(bootstrap_servers=address, enable_idempotence=True)
            await self.producer.start()
            self.consumer = AIOKafkaConsumer('essaim.agent.decision_requests',
                bootstrap_servers=address, group_id='essaim-decisions-v4',
                enable_auto_commit=False, max_poll_records=30, session_timeout_ms=45000)
            await self.consumer.start()
            self.results = AIOKafkaConsumer('essaim.agent.decisions', bootstrap_servers=address,
                group_id='essaim-http-' + uuid.uuid4().hex, auto_offset_reset='latest',
                enable_auto_commit=False, session_timeout_ms=45000)
            await self.results.start()
            await self.results.getmany(timeout_ms=1000)
            self.status = 'CONNECTED'
            self.task = asyncio.create_task(self.consume(callback))
            self.result_task = asyncio.create_task(self.receive_results())
        except Exception:
            self.status = 'DISCONNECTED'
            await self.close()

    async def receive_results(self):
        async for record in self.results:
            try:
                packet = json.loads(record.value)['payload']
                key = (packet['run_id'], packet['agent_id'], packet['request_id'])
                future = self.waiters.get(key)
                if future and not future.done():
                    future.set_result(packet)
            except (ValueError, KeyError, TypeError):
                continue

    async def request_decision(self, packet):
        if not hasattr(self, 'waiters'):
            self.waiters = {}
        if len(self.waiters) >= 120:
            raise BusyError('HTTP bridge capacity exhausted')
        key = (packet['run_id'], packet['observation']['profile']['id'], packet['request_id'])
        if key in self.waiters:
            raise ValueError('Duplicate active HTTP request')
        future = asyncio.get_running_loop().create_future()
        self.waiters[key] = future
        try:
            await self.publish('agent.decision_requests', packet, key[0], key[1], key[2])
            return await asyncio.wait_for(future, 28)
        finally:
            self.waiters.pop(key, None)

    async def consume(self, callback):
        from collections import defaultdict, deque
        from aiokafka.errors import CommitFailedError, IllegalStateError
        pending = defaultdict(deque)
        async def dispatch(record):
            try:
                await callback(json.loads(record.value)['payload'])
            except (ValueError, KeyError, TypeError, BusyError):
                return
        try:
            while True:
                offsets = {}
                for partition, records in pending.items():
                    while records and records[0][1].done():
                        offset, task = records.popleft()
                        task.result()
                        offsets[partition] = offset + 1
                if offsets:
                    try:
                        await self.consumer.commit(offsets)
                    except (CommitFailedError, IllegalStateError):
                        # Completed identities are already durable. A rebalance may replay them.
                        await asyncio.sleep(.1)
                count = sum(len(records) for records in pending.values())
                if count >= 120:
                    running = [task for records in pending.values() for _, task in records if not task.done()]
                    if running:
                        await asyncio.wait(running, return_when=asyncio.FIRST_COMPLETED)
                    continue
                batches = await self.consumer.getmany(timeout_ms=100, max_records=min(30, 120-count))
                for partition, records in batches.items():
                    for record in records:
                        # Start every delivered actor independently, without waiting for a batch's inference.
                        pending[partition].append((record.offset, asyncio.create_task(dispatch(record))))
        except asyncio.CancelledError:
            tasks = [task for records in pending.values() for _, task in records]
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            raise
        except Exception as error:
            self.status = 'DEGRADED'
            self.last_error = type(error).__name__
            # Uncommitted offsets replay using durable decision IDs after restart.

    async def publish(self, topic, payload, run='', agent='', correlation=''):
        if self.producer is None:
            return
        identity = hashlib.sha256(json.dumps([topic, run, agent, correlation, payload], sort_keys=True).encode()).hexdigest()
        event = dict(event_id=identity, run_id=run, agent_id=agent,
                     correlation_id=correlation, timestamp=datetime.now(timezone.utc).isoformat(), payload=payload)
        try:
            await asyncio.wait_for(self.producer.send_and_wait('essaim.' + topic,
                key=(agent or run).encode(), value=json.dumps(event, allow_nan=False).encode()), 3)
        except Exception:
            self.status = 'DEGRADED'

    async def close(self):
        result_task = getattr(self, 'result_task', None)
        if result_task:
            result_task.cancel()
            await asyncio.gather(result_task, return_exceptions=True)
        if getattr(self, 'results', None):
            await self.results.stop()
        task = getattr(self, 'task', None)
        if task:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        if self.consumer:
            await self.consumer.stop()
        if self.producer:
            await self.producer.stop()
        self.consumer = self.producer = None


class Ledger:
    def __init__(self, path=None):
        path = path or os.getenv('DECISION_LEDGER_PATH', 'outputs/phase4/decisions.sqlite')
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=NORMAL')
        self.db.execute('CREATE TABLE IF NOT EXISTS decisions (identity TEXT PRIMARY KEY, result TEXT)')

    def claim(self, identity):
        row = self.db.execute('SELECT result FROM decisions WHERE identity=?', (identity,)).fetchone()
        if row:
            return False, json.loads(row[0]) if row[0] else None
        self.db.execute('INSERT INTO decisions VALUES (?, NULL)', (identity,))
        self.db.commit()
        return True, None

    def finish(self, identity, result):
        self.db.execute('UPDATE decisions SET result=? WHERE identity=?', (json.dumps(result), identity))
        self.db.commit()
