"""Validate project and CI wiring without pretending to run the Godot runtime."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
issues: list[str] = []

def check(condition: bool, message: str):
    if not condition:
        issues.append(message)

project = (ROOT/'project.godot').read_text(encoding='utf-8')
check('run/main_scene="res://scenes/Main.tscn"' in project, 'main scene not configured')
check((ROOT/'scenes/Main.tscn').is_file(), 'missing main scene')
scene = (ROOT/'scenes/Main.tscn').read_text(encoding='utf-8')
check('scripts/ui/main.gd' in scene, 'scene does not load main UI script')
for source in ROOT.rglob('*.gd'):
    for path in re.findall(r'preload\("res://([^"\n]+)"\)', source.read_text(encoding='utf-8')):
        check((ROOT/path).is_file(), f'{source}: missing preload {path}')
workflow = (ROOT/'.github/workflows/android.yml').read_text(encoding='utf-8')
checks = re.search(r'for test in ([^;]+); do', workflow)
check(checks is not None, 'CI does not run test loop')
actual_tests = set(checks.group(1).split()) if checks else set()
expected_tests = {'test_sim','test_expansion','test_ui','test_03','test_04','test_05','test_06','test_07','test_08'}
check(actual_tests == expected_tests, f'CI tests mismatch: {actual_tests ^ expected_tests}')
for test in expected_tests:
    check((ROOT/f'tests/{test}.gd').is_file(), f'missing {test}')
export = (ROOT/'export_presets.cfg').read_text(encoding='utf-8')
check('version/name="0.9.0"' in export, 'export version should be 0.9.0')
check('version/code=9' in export, 'APK version code should be 9')
check('package/unique_name="com.frontier.perimeterzero"' in export, 'APK package ID changed unexpectedly')
check('test_08' in (ROOT/'README.md').read_text(encoding='utf-8'), 'README missing test_08 instructions')
check('"version":8' in (ROOT/'scripts/sim/game_state.gd').read_text(encoding='utf-8'), 'snapshot schema not v8')
print(f'Release wiring check: {len(expected_tests)} CI tests, {len(issues)} issues')
for i in issues:
    print('ERROR:', i)
sys.exit(1 if issues else 0)
