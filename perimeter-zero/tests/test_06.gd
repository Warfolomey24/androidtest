extends SceneTree
## Alpha 0.6: tactical combat, pausing strategic clock, rewards and save migration.
const State = preload("res://scripts/sim/game_state.gd")
var failures := 0

func expect(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL test_06: " + message)

func _initialize() -> void:
    var game = State.new()
    expect(int(game.snapshot()["version"]) == 8, "snapshot version 8")
    expect(game.battle_action("scan") != "", "no orders without combat")
    game.discovered.append(1)
    game.ships[0]["type"] = "escort"
    game.pirate_threat = 0
    var fuel_before: int = int(game.resources["fuel"])
    expect(game.send_patrol(0,1) == "", "patrol mission booked")
    expect(int(game.resources["fuel"]) == fuel_before-6, "fuel spent once on patrol")
    var travel: int = int(game.ships[0]["eta"])
    for _cycle in range(travel):
        game._advance_ships()
    expect(not game.pending_battle.is_empty(), "patrol becomes tactical encounter")
    expect(int(game.ships[0]["target"]) == 1, "ship committed to battle")
    expect(game.send_patrol(1,1) != "", "cannot book more patrols during battle")
    var frozen_cycle: int = int(game.cycle)
    game.step()
    expect(game.cycle == frozen_cycle, "combat pauses strategic clock")
    var health_before: int = int(game.ships[0]["health"])
    expect(game.battle_action("scan") == "", "first scan works")
    expect(game.battle_action("scan") != "", "scan cannot be repeated")
    expect(int(game.ships[0]["health"]) == health_before, "scan does not cost health")
    expect(game.save_game(1) == "", "battle saved")
    var loaded = State.new()
    expect(loaded.load_game(1) == "", "battle loaded")
    expect(not loaded.pending_battle.is_empty(), "active combat persists")
    expect(bool(loaded.pending_battle["scanned"]), "scanner intel persists")
    var before_credits: int = int(loaded.resources["credits"])
    var before_pirates: int = int(loaded.pirate_threat)
    for _turn in range(25):
        if loaded.pending_battle.is_empty():
            break
        expect(loaded.battle_action("salvo") == "", "combat order resolves")
    expect(loaded.pending_battle.is_empty(), "battle eventually terminates")
    expect(int(loaded.ships[0]["health"]) > 0, "escort survives low-risk encounter")
    expect(int(loaded.resources["credits"]) > before_credits, "battle rewards paid on victory")
    expect(int(loaded.pirate_threat) <= before_pirates, "pirate threat decreases")
    expect(int(loaded.ships[0]["target"]) == -1, "ship returns to base")
    var rewarded_credits: int = int(loaded.resources["credits"])
    expect(loaded.battle_action("salvo") != "", "no more actions after victory")
    expect(int(loaded.resources["credits"]) == rewarded_credits, "rewards not duplicated")

    # Retreat path has a health cost but no loot or reduced pirate threat.
    var retreat_game = State.new()
    retreat_game.discovered.append(1)
    retreat_game.ships[0]["type"] = "escort"
    expect(retreat_game.send_patrol(0,1) == "", "retreat scenario patrol")
    var travel_two: int = int(retreat_game.ships[0]["eta"])
    for _cycle in range(travel_two):
        retreat_game._advance_ships()
    var retreat_credits: int = int(retreat_game.resources["credits"])
    var retreat_health: int = int(retreat_game.ships[0]["health"])
    expect(retreat_game.battle_action("retreat") == "", "retreat accepted")
    expect(retreat_game.pending_battle.is_empty(), "retreat completes battle")
    expect(int(retreat_game.resources["credits"]) == retreat_credits, "no rewards for retreat")
    expect(int(retreat_game.ships[0]["health"]) < retreat_health, "retreat has hull cost")

    var corrupt: Dictionary = game.snapshot().duplicate(true)
    corrupt["pending_battle"]["ship_index"] = 9999
    expect(not game._valid_snapshot(corrupt), "invalid battle ship rejected")
    var legacy: Dictionary = loaded.snapshot().duplicate(true)
    legacy["version"] = 5
    legacy.erase("pending_battle")
    var file := FileAccess.open("user://perimeter_zero_slot_2.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(legacy))
    file.close()
    var migrated = State.new()
    expect(migrated.load_game(2) == "", "v5 save migration")
    expect(migrated.pending_battle.is_empty(), "legacy game has no active battle")

    if failures == 0:
        print("PASS: Alpha 0.6 tactical combat, retreat, freeze, autosave compatibility")
        quit(0)
    else:
        print("FAIL: %d Alpha 0.6 regression cases" % failures)
        quit(1)
