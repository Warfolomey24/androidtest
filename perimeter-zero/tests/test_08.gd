extends SceneTree
## Alpha 0.8: trade escorts, fuel escrow, ship exclusivity and v7 migration.
const State = preload("res://scripts/sim/game_state.gd")
var failures := 0

func expect(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL 0.8: " + description)

func _initialize() -> void:
    var game = State.new()
    expect(int(game.snapshot()["version"]) == 8,"schema v8")
    game.discovered.append(5)
    expect(game.assign_freighter(1,-1) == "","release initial freighter")
    game.ships[0]["type"] = "escort"
    game.pirate_threat = 75
    expect(game.faction_trade("Союз","food",5,true) == "","create trade cargo")
    expect(game.trade_flights.size() == 1,"trade created once")
    expect(int(game.trade_flights[0]["escort_index"]) == -1,"initially unprotected")
    expect(game.escort_trade_flight(1,0) != "","freighter cannot escort itself")
    var fuel_before: int = int(game.resources["fuel"])
    var risk_before: int = game.trade_raid_chance(game.trade_flights[0])
    expect(game.escort_trade_flight(0,0) == "","escort ordered")
    expect(int(game.resources["fuel"]) == fuel_before - 3,"fuel charged exactly once")
    expect(game.trade_raid_chance(game.trade_flights[0]) == maxi(0,risk_before - 20),"escort reduces piracy chance")
    expect(game.escort_trade_flight(0,0) != "","duplicate escort rejected")
    expect(int(game.resources["fuel"]) == fuel_before - 3,"failed order does not charge fuel")
    game.discovered.append(1)
    expect(game.send_ship(0,1) != "","escort cannot explore while guarding")
    expect(game.send_patrol(0,1) != "","escort cannot patrol simultaneously")
    expect(game.repair_ship(0) != "","escort cannot repair during voyage")
    expect(game.save_game(1) == "","save guarded flight")
    var loaded = State.new()
    expect(loaded.load_game(1) == "","load guarded flight")
    expect(int(loaded.trade_flights[0]["escort_index"]) == 0,"escort link saved")
    expect(int(loaded.ships[0]["cargo_eta"]) == int(loaded.trade_flights[0]["eta"]),"escort ETA preserved")
    loaded.pirate_threat = 0
    var food_before: int = int(loaded.resources["food"])
    var eta: int = int(loaded.trade_flights[0]["eta"])
    for i in range(eta - 1):
        loaded._advance_faction_trade()
    expect(int(loaded.resources["food"]) == food_before,"no instant delivery")
    loaded._advance_faction_trade()
    expect(int(loaded.resources["food"]) == food_before + 5,"delivery exactly once")
    expect(loaded.trade_flights.is_empty(),"trade removed after arrival")
    expect(int(loaded.ships[0]["cargo_eta"]) == 0,"escort released")
    expect(int(loaded.ships[1]["cargo_eta"]) == 0,"freighter released")

    var corrupt: Dictionary = game.snapshot().duplicate(true)
    corrupt["trade_flights"][0]["escort_index"] = 999
    expect(not game._valid_snapshot(corrupt),"reject out-of-range escort")
    corrupt = game.snapshot().duplicate(true)
    corrupt["trade_flights"][0]["escort_index"] = 1
    expect(not game._valid_snapshot(corrupt),"reject freighter as escort")
    corrupt = game.snapshot().duplicate(true)
    corrupt["ships"][0]["cargo_eta"] = 0
    expect(not game._valid_snapshot(corrupt),"reject mismatched escort ETA")

    var old: Dictionary = game.snapshot().duplicate(true)
    old["version"] = 7
    old["trade_flights"][0].erase("escort_index")
    old["ships"][0]["cargo_eta"] = 0
    old["ships"][0]["type"] = "scout"
    var file := FileAccess.open("user://perimeter_zero_slot_3.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(old))
    file.close()
    var migrated = State.new()
    expect(migrated.load_game(3) == "","load v7 save")
    expect(int(migrated.trade_flights[0].get("escort_index",-99)) == -1,"default missing escort to none")
    print("PASS: escort locks, risk, fuel, exactly-once settlement, save validation and migration" if failures == 0 else "FAIL: %d Alpha 0.8 cases" % failures)
    quit(0 if failures == 0 else 1)
