extends SceneTree
## Alpha 0.4 runtime regression: no local teleportation, road-based hauling,
## warehouse limits, save compatibility, and UI visibility prerequisites.
const State = preload("res://scripts/sim/game_state.gd")
var failures := 0

func expect(condition: bool, reason: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + reason)

func _initialize() -> void:
    var game = State.new()
    var road: Array = game.colony_haul_path(0,4,3)
    expect(road.size() >= 4,"quarry must connect through roads to landing pad")
    expect(road[0] == [4,3] and road.back() == [1,3],"haul follows quarry -> landing")
    for i in range(road.size()-1):
        var first: Array = road[i]
        var second: Array = road[i+1]
        expect(abs(int(first[0])-int(second[0])) + abs(int(first[1])-int(second[1])) == 1,"only cardinal moves allowed")
    expect(game.colony_haul_capacity(0) == 2,"landing plus starter depot make two vehicles")

    var colony: Dictionary = game.colonies[0]
    colony["stock"] = {"ore":0,"ice":0,"food":100,"water":100}
    # Freeze space convoy to distinguish internal delivery from interplanetary delivery.
    colony["convoy"]["eta"] = 100
    game._advance_colonies()
    expect(int(colony["stock"].get("ore",0)) == 0,"quarry output may not teleport to shared inventory")
    expect(colony["hauls"].size() > 0,"connected production creates local haul job")
    expect(colony["hauls"].size() <= game.colony_haul_capacity(0),"concurrent hauls capped by vehicle count")
    expect(game.colony_haul_reserved(0) >= 4,"in-transit cargo is reserved")
    var start_eta := int(colony["hauls"][0]["eta"])
    expect(start_eta >= 2,"hauls must take multiple turns")
    for i in range(start_eta):
        game._advance_colony_hauls(0)
    expect(int(colony["stock"].get("ore",0)) >= 4,"hauling actually delivers to local inventory")

    var disconnected = State.new()
    disconnected.colonies[0]["buildings"] = [
        {"id":"landing","x":1,"y":3,"level":1},
        {"id":"quarry","x":11,"y":7,"level":1}]
    expect(disconnected.colony_haul_path(0,11,7).is_empty(),"disconnected factory has no road path")
    disconnected._advance_colonies()
    expect(disconnected.colonies[0]["hauls"].is_empty(),"disconnected factory cannot produce remote cargo")

    var full = State.new()
    full.colonies[0]["stock"] = {"ore":190,"food":50,"water":50}
    full.colonies[0]["convoy"]["eta"] = 100
    full._advance_colonies()
    expect(full.colonies[0]["hauls"].is_empty(),"fully reserved warehouse blocks output")

    var upgraded = State.new()
    var vehicles_before := upgraded.colony_haul_capacity(0)
    upgraded.resources["alloy"] = 100
    upgraded.resources["polymer"] = 100
    expect(upgraded.colony_upgrade(0,2,4) == "","depot can be upgraded")
    expect(upgraded.colony_haul_capacity(0) == vehicles_before+1,"depot upgrade adds delivery vehicle")

    var saving = State.new()
    saving.colonies[0]["stock"] = {"ore":0,"ice":0,"food":100,"water":100}
    saving.colonies[0]["convoy"]["eta"] = 100
    saving._advance_colonies()
    expect(saving.save_game(1) == "","v4 in-flight hauling can be saved")
    var loaded = State.new()
    expect(loaded.load_game(1) == "","v4 hauling save can be loaded")
    expect(loaded.colonies[0]["hauls"].size() == saving.colonies[0]["hauls"].size(),"in-flight cargo survives load")
    expect(int(loaded.snapshot()["version"]) == 8,"Current save schema is version 8")
    var broken: Dictionary = saving.snapshot().duplicate(true)
    broken["colonies"][0]["hauls"][0]["path"] = [[1000,5]]
    expect(not saving._valid_snapshot(broken),"invalid hauls cannot corrupt state")

    var old: Dictionary = saving.snapshot().duplicate(true)
    old["version"] = 3
    for c in old["colonies"]:
        c.erase("hauls")
    var f := FileAccess.open("user://perimeter_zero_slot_3.json",FileAccess.WRITE)
    f.store_string(JSON.stringify(old))
    f.close()
    var migrated = State.new()
    expect(migrated.load_game(3) == "","v3 can be loaded by v4")
    expect(migrated.colonies[0].has("hauls"),"legacy colonies get empty delivery queue")
    expect(migrated.colonies[0]["hauls"].is_empty(),"legacy deliveries start empty")

    var seed_a = State.new()
    var seed_b = State.new()
    var seed_c = State.new()
    seed_a.start_new(2026)
    seed_b.start_new(2026)
    seed_c.start_new(2027)
    expect(seed_a.mine == seed_b.mine,"same random seed reproduces geological map")
    expect(seed_a.mine != seed_c.mine,"different random seeds change geological map")
    expect(seed_a.snapshot()["world_seed"] == 2026,"world generation seed is saved")

    if failures == 0:
        print("PASS: local hauling / delivery timing / roads / capacity / v3->v4 saves")
        quit(0)
    else:
        print("FAIL: %d Alpha 0.4 regression cases" % failures)
        quit(1)
