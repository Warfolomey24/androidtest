extends SceneTree
## Alpha 0.5: faction production, delayed merchant routes, ship locking, cargo safety and save migrations.
const State = preload("res://scripts/sim/game_state.gd")
var failures := 0

func expect(condition: bool, reason: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + reason)

func _initialize() -> void:
    var game = State.new()
    expect(game.snapshot()["version"] == 8, "schema v8")
    expect(game.faction_economy.has("Союз") and game.faction_economy.has("Рой"), "factions initialized")
    var stock_before := int(game.faction_economy["Союз"]["stock"]["food"])
    game._advance_faction_economy()
    expect(int(game.faction_economy["Союз"]["stock"]["food"]) > stock_before, "foreign industry produces food")
    expect(game.faction_trade("Рой","food",5,true) != "", "swarm refuses trade")
    expect(game.faction_trade("Союз","food",5,true) != "", "unexplored trade route cannot be used")
    game.discovered.append(5)
    expect(game.faction_trade("Союз","food",5,true) != "", "assigned colony freighter cannot trade")
    expect(game.assign_freighter(1,-1) == "", "release freighter for independent mission")
    game.pirate_threat = 0
    var funds_before := int(game.resources["credits"])
    var food_before := int(game.resources["food"])
    var market_stock := int(game.faction_economy["Союз"]["stock"]["food"])
    var price := game.faction_price("Союз","food",true)
    expect(game.faction_trade("Союз","food",5,true) == "", "import booking works")
    expect(game.trade_flights.size() == 1, "cargo gets one scheduled trade flight")
    expect(int(game.resources["food"]) == food_before, "import does not teleport")
    expect(int(game.resources["credits"]) == funds_before - 5*price, "buyer pays once")
    expect(int(game.faction_economy["Союз"]["stock"]["food"]) == market_stock-5, "seller reserves the goods")
    expect(game.send_ship(1,1) != "", "trading ship cannot explore")
    expect(game.assign_freighter(1,0) != "", "trading ship cannot be reassigned")
    var eta: int = int(game.trade_flights[0]["eta"])
    expect(eta > 1, "trade route takes more than one cycle")
    for i in range(eta-1):
        game._advance_faction_trade()
    expect(int(game.resources["food"]) == food_before, "cargo still in transit before deadline")
    game._advance_faction_trade()
    expect(int(game.resources["food"]) == food_before+5, "cargo delivered once")
    expect(game.trade_flights.is_empty(), "finished trade removed")
    expect(int(game.ships[1]["cargo_eta"]) == 0, "ship free after trade")
    game._advance_faction_trade()
    expect(int(game.resources["food"]) == food_before+5, "no repeat delivery")

    # A fuel export must consume cargo fuel and trip fuel, not overwrite one dictionary key.
    game.discovered.append(6)
    game.resources["fuel"] = 7
    expect(game.faction_trade("Консорциум","fuel",5,false) != "", "fuel shipment includes both cargo and transport cost")
    expect(int(game.resources["fuel"]) == 7, "failed booking makes no changes")
    game.resources["fuel"] = 30
    var fuel_before := int(game.resources["fuel"])
    var credits_before := int(game.resources["credits"])
    var fuel_price := game.faction_price("Консорциум","fuel",false)
    expect(game.faction_trade("Консорциум","fuel",5,false) == "", "fuel export books")
    expect(int(game.resources["fuel"]) <= fuel_before-7, "shipment and trip fuel both deducted")
    expect(int(game.resources["credits"]) == credits_before, "payment held until delivery")
    expect(game.save_game(2) == "", "trade shipment saved")
    var loaded = State.new()
    expect(loaded.load_game(2) == "", "trade shipment loaded")
    expect(loaded.trade_flights.size() == 1, "in-flight trade persists")
    expect(int(loaded.ships[1]["cargo_eta"]) == int(loaded.trade_flights[0]["eta"]), "ship assignment remains reserved")
    var export_eta := int(loaded.trade_flights[0]["eta"])
    loaded.pirate_threat = 0
    for i in range(export_eta):
        loaded._advance_faction_trade()
    expect(loaded.trade_flights.is_empty(), "loaded trade completes")
    expect(int(loaded.resources["credits"]) == credits_before+5*fuel_price, "export payment received exactly once")
    var broken: Dictionary = loaded.snapshot().duplicate(true)
    broken["trade_flights"] = [{"faction":"Союз","resource":"food","amount":5,"buy":true,"payment":50,"eta":5,"duration":5,"ship_index":9999}]
    expect(not loaded._valid_snapshot(broken), "invalid ship in save rejected")

    var old: Dictionary = loaded.snapshot().duplicate(true)
    old["version"] = 4
    old.erase("faction_economy")
    old.erase("trade_flights")
    old.erase("pirate_threat")
    old.erase("patrol_cover")
    var file := FileAccess.open("user://perimeter_zero_slot_3.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(old))
    file.close()
    var migrated = State.new()
    expect(migrated.load_game(3) == "", "v4 loads in v5")
    expect(migrated.faction_economy.has("Союз") and migrated.trade_flights.is_empty(), "v4 faction defaults migrated")

    if failures == 0:
        print("PASS: independent factions / delayed trades / freighter exclusivity / fuel cost / v4->v5")
        quit(0)
    else:
        print("FAIL: %d Alpha 0.5 regression cases" % failures)
        quit(1)
