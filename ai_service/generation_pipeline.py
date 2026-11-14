"""Dependency/priority scheduling and content-addressed pure-data artifacts."""
from __future__ import annotations
import copy
import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path

def fingerprint(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

@dataclass(frozen=True)
class Stage:
    name: str
    dependencies: tuple[str,...]
    priority: int
    build: object
    version: int=1

class ArtifactCache:
    def __init__(self,directory=None):
        self.directory=Path(directory) if directory else None
        self.memory={}
        self.hits=0; self.misses=0
        if self.directory: self.directory.mkdir(parents=True,exist_ok=True)
    def get(self,key):
        if key in self.memory:
            self.hits+=1; return copy.deepcopy(self.memory[key])
        if self.directory:
            try:
                entry=json.loads((self.directory/f'{key}.json').read_text())
                if fingerprint(entry['value'])==entry['hash']:
                    self.memory[key]=entry['value']; self.hits+=1
                    return copy.deepcopy(entry['value'])
            except (OSError,ValueError,KeyError,TypeError): pass
        self.misses+=1; return None
    def put(self,key,value):
        self.memory[key]=copy.deepcopy(value)
        if self.directory:
            path=self.directory/f'{key}.{os.getpid()}.tmp'
            path.write_text(json.dumps(dict(value=value,hash=fingerprint(value)),separators=(',',':')),encoding='utf-8')
            path.replace(self.directory/f'{key}.json')

def publish_progress(percent, stage):
    destination=os.environ.get('ESSAIM_PROGRESS_FILE')
    if not destination: return
    path=Path(destination)
    try:
        temporary=path.with_suffix('.progress.tmp')
        temporary.write_text(json.dumps({'percent':percent,'stage':stage}),encoding='utf-8')
        temporary.replace(path)
    except OSError: pass

class GenerationPipeline:
    def __init__(self,stages,cache=None):
        self.stages={s.name:s for s in stages}
        if len(self.stages)!=len(stages): raise ValueError('Duplicate generation stage')
        self.cache=cache if cache is not None else ArtifactCache()
        self.last_run=[]
    def order(self):
        pending=set(self.stages); result=[]
        for stage in self.stages.values():
            if set(stage.dependencies)-set(self.stages): raise ValueError('Missing generation dependency')
        while pending:
            ready=[self.stages[k] for k in pending if set(self.stages[k].dependencies)<=set(result)]
            if not ready: raise ValueError('Cyclic generation dependencies')
            next_stage=min(ready,key=lambda s:(-s.priority,s.name))
            result.append(next_stage.name); pending.remove(next_stage.name)
        return result
    def run(self,inputs):
        order=self.order(); values={}; self.last_run=[]
        weights={'geography':5,'districts':5,'shelters':10,'layout':40,'environment':15,'infrastructure':5,'validation':20}
        finished=0
        total=sum(weights.get(name,1) for name in order)
        for name in order:
            publish_progress(round(finished/total*100),name)
            stage=self.stages[name]
            dependencies={k:values[k] for k in stage.dependencies}
            supplied=inputs.get(name,{})
            key=fingerprint(dict(stage=name,version=stage.version,inputs=supplied,dependencies=dependencies))
            value=self.cache.get(key); hit=value is not None
            if hit and isinstance(value,dict) and '__generation_error__' in value:
                raise ValueError(value['__generation_error__'])
            if not hit:
                try:
                    value=stage.build(copy.deepcopy(supplied),copy.deepcopy(dependencies))
                except ValueError as exc:
                    self.cache.put(key,{'__generation_error__':str(exc)})
                    raise
                value=json.loads(json.dumps(value,allow_nan=False))
                self.cache.put(key,value)
            values[name]=value
            finished+=weights.get(name,1)
            publish_progress(round(finished/total*100),name)
            self.last_run.append(dict(stage=name,reused=hit,priority=stage.priority,dependencies=list(stage.dependencies)))
        return values
