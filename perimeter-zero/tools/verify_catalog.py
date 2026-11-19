"""Offline data integrity checks for GDScript catalog constants.
Checks content schemas, graph reachability and production invariants without Godot.
"""
from __future__ import annotations
from pathlib import Path
import json
import sys

SOURCE = (Path(__file__).resolve().parents[1] / 'scripts/sim/database.gd').read_text('utf-8')
issues: list[str] = []

def constant(name: str):
    head = f'const {name} := '
    at = SOURCE.index(head) + len(head)
    start = SOURCE[at]
    assert start in '[{', (name, start)
    brackets = {']':'[', '}':'{'}
    stack = []
    quoted = False
    slash = False
    for i in range(at, len(SOURCE)):
        c = SOURCE[i]
        if quoted:
            if slash:
                slash = False
            elif c == '\\':
                slash = True
            elif c == '"':
                quoted = False
        elif c == '"':
            quoted = True
        elif c in '[{':
            stack.append(c)
        elif c in ']}' and stack:
            if stack[-1] != brackets[c]:
                raise ValueError(f'bracket mismatch in {name}')
            stack.pop()
            if not stack:
                return json.loads(SOURCE[at:i+1])
    raise ValueError(f'Unclosed {name}')

def problem(message: str):
    issues.append(message)

def validate_costs(label: str, data: dict, resources: set[str]):
    if not isinstance(data,dict):
        problem(f'{label}: not a dictionary')
        return
    for id, value in data.items():
        if id not in resources or not isinstance(value,(int,float)) or value < 0:
            problem(f'{label}: invalid resource {id}={value}')

labels = constant('RESOURCE_LABELS')
resources = set(labels)
assert len(resources) == 12, 'expected 12 resources'
station = constant('BUILDINGS')
colony = constant('COLONY_BUILDINGS')
ships = constant('SHIP_TYPES')
techs = constant('TECHS')
stars = constant('SYSTEMS')
links = constant('LINKS')
contracts = constant('CONTRACTS')
stories = constant('STORY_EVENTS')
factions = constant('FACTION_TRADE')


for collection, kind in [(station,'Station'),(colony,'Colony')]:
    for id, spec in collection.items():
        for key in ['name','tag','cost','workers','consume','produce']:
            if key not in spec:
                problem(f'{kind}/{id}: missing {key}')
        for field in ['cost','consume','produce']:
            validate_costs(f'{kind}/{id}/{field}',spec.get(field,{}),resources)
        if int(spec.get('workers',-1))<0:
            problem(f'{kind}/{id}: invalid workforce')
for id, spec in ships.items():
    validate_costs(f'Ship/{id}',spec['cost'],resources)
    if min(spec['cargo'],spec['attack'],spec['defense'])<0:
        problem(f'Ship/{id}: invalid attributes')

tech_by_id = {t['id']:t for t in techs}
if len(tech_by_id) != len(techs):
    problem('Technology duplicate ID')
for tech in techs:
    for dependency in tech['requires']:
        if dependency not in tech_by_id or dependency==tech['id']:
            problem(f"Bad tech dependency: {tech['id']} -> {dependency}")
    if tech['cost']<0:
        problem(f"Negative tech cost: {tech['id']}")
visiting,visited=set(),set()
def visit(node:str):
    if node in visiting:
        problem('Technology dependency cycle at '+node);return
    if node in visited or node not in tech_by_id:return
    visiting.add(node)
    for other in tech_by_id[node]['requires']:
        visit(other)
    visiting.remove(node);visited.add(node)
for id in tech_by_id: visit(id)

adj={i:set() for i in range(len(stars))}
for edge in links:
    if len(edge)!=2 or edge[0] not in adj or edge[1] not in adj:
        problem('Invalid galaxy link '+str(edge));continue
    adj[edge[0]].add(edge[1]);adj[edge[1]].add(edge[0])
seen={0}; todo=[0]
while todo:
    now=todo.pop()
    for next_ in adj[now]-seen:
        seen.add(next_);todo.append(next_)
if len(seen)!=len(stars):
    problem(f'Unreachable star systems {sorted(set(adj)-seen)}')
for star in stars:
    if star['ore'] not in resources:
        problem('Star resource not listed: '+star['ore'])
for c in contracts:
    if c['resource'] not in resources:
        problem('Contract unknown resource: '+c['resource'])

# Independent faction markets may only offer resources the shared price catalog knows.
if set(factions) != {'Союз','Консорциум','Рой'}:
    problem('Faction trade catalog must cover all three factions')
for name, profile in factions.items():
    if not (0 <= profile.get('system',-1) < len(stars)):
        problem('Faction trade destination out of bounds: '+name)
    elif name != 'Рой' and stars[profile['system']]['faction'] != name:
        problem('Faction trade destination owner mismatch: '+name)
    if profile.get('treasury',-1) < 0:
        problem('Faction has negative treasury: '+name)
    if len(profile.get('goods',[])) != len(set(profile.get('goods',[]))):
        problem('Faction offers duplicate goods: '+name)
    for item in profile.get('goods',[]):
        if item not in resources or item not in constant('MARKETS'):
            problem('Faction has unsupported commodity: '+name+'/'+item)
    for field in ('production','consumption','stock'):
        validate_costs('Faction/'+name+'/'+field,profile.get(field,{}),resources)
    if name == 'Рой' and profile.get('goods'):
        problem('Swarm must not allow civilian trading')

seen_events=set()
for event in stories:
    if event['id'] in seen_events:
        problem('Duplicate story event ID '+event['id'])
    seen_events.add(event['id'])
    if not event['options']:
        problem('Story event without options '+event['id'])
    for n, opt in enumerate(event['options']):
        for field in ['cost','reward']:
            validate_costs(f'Story/{event["id"]}/{n}/{field}',opt.get(field,{}),resources)

print(f'Catalog verification: {len(station)} station buildings, {len(colony)} colony buildings, {len(techs)} technologies, {len(stars)} stars, {len(links)} links, {len(stories)} story events; {len(issues)} issues')
for issue in issues:print('ERROR:',issue)
sys.exit(1 if issues else 0)
