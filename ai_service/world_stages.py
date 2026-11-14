"""Independent world-generation modules; their scheduler owns execution order."""
import random
from . import city_generator as city
from .shelter_generation import reserve
from .generation_pipeline import GenerationPipeline,Stage

def geography(inputs,_):
    rng=random.Random(inputs['seed'])
    return dict(size=[round(v*rng.uniform(.965,1.025),3) for v in inputs['size']],noise_seed=inputs['seed'])

def districts(inputs,deps):
    return city.district_centers(deps['geography']['size'],random.Random(inputs['seed']),True,inputs['count'])

def shelters(inputs,deps):
    return reserve(deps['geography']['size'],deps['districts'],inputs['seed'])

def layout(inputs,deps):
    result=city.generate(seed=inputs['world_seed'],size=deps['geography']['size'],procedural=True,
        layout=inputs['pattern'],district_density=inputs['density'],streams=inputs['streams'],
        max_buildings=inputs['buildings'],parking_count=inputs['parking'],district_count=inputs['district_count'],
        road_width_multiplier=inputs['width'],straight_road_ratio=inputs['straight_road_ratio'],
        shelter_plan=deps['shelters'],district_plan=deps['districts'])
    result.pop('generation_ms',None)
    return result

def make_pipeline(decorate,validate,cache=None,priorities=None):
    priorities=priorities or {}
    priority=lambda name,default:int(priorities.get(name,default))
    def environment(inputs,deps):
        result=deps['layout']
        decorate(result,inputs['streams'],inputs['settings'])
        return result
    def infrastructure(_,deps):
        access=deps['layout']['shelter_access']
        return {'terrain':{'formula_version':1,'noise_seed':deps['geography']['noise_seed'],
                           'mountain_center':access['S5']['position']},
                'infrastructure':[
                    dict(kind='metro_entrance',position=access['S2']['road_entry'],shelter='S2'),
                    dict(kind='communications',position=access['S3']['position'],shelter='S3')]}
    def validation(_,deps):
        result=deps['environment']; result.update(deps['infrastructure']); result['validation']=validate(result)
        if not result['validation']['valid']: raise ValueError('; '.join(result['validation']['errors']))
        return result
    # Registration order is intentionally unrelated to execution order.
    return GenerationPipeline([
        Stage('environment',('layout',),priority('environment',10),environment),
        Stage('validation',('infrastructure','environment'),priority('validation',1000),validation),
        Stage('layout',('geography','districts','shelters'),priority('layout',90),layout),
        Stage('shelters',('geography','districts'),priority('shelters',1000),shelters),
        Stage('geography',(),priority('geography',100),geography),
        Stage('infrastructure',('layout','geography'),priority('infrastructure',80),infrastructure),
        Stage('districts',('geography',),priority('districts',80),districts)
    ],cache)
