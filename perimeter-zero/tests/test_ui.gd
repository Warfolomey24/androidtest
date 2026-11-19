extends SceneTree
## Headless smoke test: instantiate UI and exercise all eleven navigation modes.
const MODES := ["station","mine","colony","galaxy","fleet","battle","research","market","contracts","diplomacy","campaign"]
var frames := 0
var ui

var failures := 0

func expect(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + message)

func _initialize() -> void:
    var scene: PackedScene = load("res://scenes/Main.tscn")
    expect(scene != null, "test_ui.gd: assertion 1")
    ui = scene.instantiate()
    root.add_child(ui)

func _process(_delta: float) -> bool:
    if frames < MODES.size():
        ui._change_view(MODES[frames])
        frames += 1
    else:
        expect(ui.sidebar.get_child_count() > 0, "test_ui.gd: assertion 2")
        ui._on_sidebar_touch_started()
        expect(ui.sidebar_touch_scrolling,"touch scroll enters protected mode")
        var first_control: Node = ui.sidebar.get_child(0)
        ui._refresh()
        expect(ui.sidebar.get_child(0) == first_control,"live update does not replace scroll controls mid-gesture")
        ui._on_sidebar_touch_ended()
        expect(not ui.sidebar_touch_scrolling,"touch scroll exits protected mode")
        print("PASS: main scene / 11 navigation views / Android sidebar scroll")
        quit(0 if failures == 0 else 1)
    return false
