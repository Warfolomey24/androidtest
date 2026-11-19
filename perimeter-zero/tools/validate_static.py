"""Best-effort static structural checks, not a substitute for Godot compile or runtime tests."""
from __future__ import annotations
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []
count = 0
for source in sorted(ROOT.rglob("*.gd")):
    count += 1
    raw = source.read_text("utf-8")
    names = re.findall(r"^func\s+([A-Za-z_][A-Za-z0-9_]*)\(", raw, re.M)
    if len(names) != len(set(names)):
        errors.append(f"{source.name}: duplicate function")
    stack = []
    in_string = False
    escaped = False
    in_comment = False
    for n, c in enumerate(raw):
        if c == "\n":
            in_comment = False
        if in_comment:
            continue
        if in_string:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            continue
        if c == "#":
            in_comment = True
            continue
        if c == '"':
            in_string = True
            continue
        if c in "([{":
            stack.append((c, n))
        elif c in ")]}":
            if not stack or {')':'(',']':'[','}':'{'}[c] != stack[-1][0]:
                errors.append(f"{source.name}: mismatch at {n}")
                break
            stack.pop()
    if stack:
        errors.append(f"{source.name}: unclosed delimiter {stack[-1][0]}")
    if in_string:
        errors.append(f"{source.name}: unclosed string")
    if "\t" in raw:
        errors.append(f"{source.name}: tabs in indentation")
    # Godot has separate minf/maxf and mini/maxi overloads: mixing them
    # causes type errors which delimiter-only checks would miss.
    for match in re.finditer(r"\bmini\([^\n)]*\d+\.\d+", raw):
        errors.append(f"{source.name}: mini() received an apparent float at {match.start()}; use minf()")

ui = (ROOT / "scripts/ui/main.gd").read_text("utf-8")
world = (ROOT / "scripts/ui/world_view.gd").read_text("utf-8")
state = (ROOT / "scripts/sim/game_state.gd").read_text("utf-8")
for fn in ["_sidebar_station","_sidebar_mine","_sidebar_colony","_sidebar_galaxy", "_sidebar_fleet","_sidebar_research","_sidebar_market","_sidebar_contracts","_sidebar_battle","_sidebar_diplomacy","_sidebar_campaign"]:
    if not re.search(rf"^func {fn}\(",ui,re.M):
        errors.append(f"main.gd missing {fn}")
for fn in ["_draw_station","_draw_mine","_draw_colony","_draw_galaxy","_draw_fleet","_draw_research","_draw_market","_draw_contracts","_draw_battle","_draw_diplomacy","_draw_campaign"]:
    if not re.search(rf"^func {fn}\(",world,re.M):
        errors.append(f"world_view.gd missing {fn}")
for fn in ["_advance_colonies","_advance_ships","_advance_mining","_advance_campaign","save_game","load_game"]:
    if not re.search(rf"^func {fn}\(",state,re.M):
        errors.append(f"game_state.gd missing {fn}")
current = re.search(r'"version":(\d+),"cycle":cycle', state)
if current is None:
    errors.append("current snapshot schema version not detectable")
else:
    current_version = int(current.group(1))
    for test_file in (ROOT / "tests").glob("test_*.gd"):
        content = test_file.read_text("utf-8")
        for check in re.finditer(r'snapshot\(\)\["version"\]\)?\s*==\s*(\d+)',content):
            if int(check.group(1)) != current_version:
                errors.append(f"{test_file.name}: stale snapshot schema assertion {check.group(1)} (expected {current_version})")

for expected in ["escort_trade_flight", "trade_raid_chance"]:
    if not re.search(rf"^func {expected}\(", state, re.M):
        errors.append(f"game_state.gd missing {expected}")
if not re.search(r"^func _escort_selected\(", ui, re.M):
    errors.append("main.gd missing trade escort button callback")
if "escort_index" not in world:
    errors.append("world_view.gd missing escort indicator")
if not (ROOT / "tests/test_expansion.gd").exists():
    errors.append("expansion test missing")
print(f"Static project check: {count} GDScript files scanned; {len(errors)} issues")
for error in errors:
    print("ERROR:",error)
if errors:
    sys.exit(1)
