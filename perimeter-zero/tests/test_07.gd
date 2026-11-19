extends SceneTree
## Alpha 0.7: independent faction freighters, escrow, piracy and migration.
const State = preload("res://scripts/sim/game_state.gd")
var failures := 0

func expect(condition: bool, reason: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL v0.7: " + reason)

func _initialize() -> void:
    var game = State.new()
    expect(int(game.snapshot()["version"]) == 8,"schema is v8")
    expect(game.faction_fleets.is_empty(),"no initial fleet")
    game.cycle = 6
    game.pirate_threat = 0
    var stock_before := int(game.faction_economy["Союз"]["stock"]["food"])
    var buyer_funds := int(game.faction_economy["Консорциум"]["treasury"])
    game._advance_faction_fleets()
    expect(game.faction_fleets.size() == 1,"autonomous departure on interval")
    var flight: Dictionary = game.faction_fleets[0]
    expect(flight["source"] == "Союз" and flight["destination"] == "Консорциум","faction route assigned")
    var amount: int = int(flight["amount"])
    var payment: int = int(flight["payment"])
    expect(int(game.faction_economy["Союз"]["stock"]["food"]) == stock_before-amount,"stock reserved on departure")
    expect(int(game.faction_economy["Консорциум"]["treasury"]) == buyer_funds-payment,"buyer money is in escrow")
    var received_before := int(game.faction_economy["Консорциум"]["stock"].get("food",0))
    var seller_funds := int(game.faction_economy["Союз"]["treasury"])
    var eta: int = int(flight["eta"])
    for i in range(eta-1):
        game.cycle += 1
        game._advance_faction_fleets()
    expect(int(game.faction_economy["Консорциум"]["stock"].get("food",0)) == received_before,"no delivery before ETA")
    game.cycle += 1
    game._advance_faction_fleets()
    expect(game.faction_fleets.is_empty(),"convoy removed after arrival")
    expect(int(game.faction_economy["Консорциум"]["stock"].get("food",0)) == received_before+amount,"cargo arrives exactly once")
    expect(int(game.faction_economy["Союз"]["treasury"]) == seller_funds+payment,"seller paid only after delivery")

    var interrupted = State.new()
    interrupted.cycle = 6
    interrupted.pirate_threat = 0
    interrupted._advance_faction_fleets()
    expect(interrupted.save_game(1) == "","save NPC voyage")
    var loaded = State.new()
    expect(loaded.load_game(1) == "","load NPC voyage")
    expect(loaded.faction_fleets.size() == 1,"NPC fleet persists")
    var buyer_refund: int = int(loaded.faction_economy["Консорциум"]["treasury"])
    loaded.pirate_threat = 100
    # Find a reproducible random seed which intercepts at threat 100 (risk 33%).
    var intercepted_seed: int = -1
    for candidate in range(1,200):
        loaded.rng.seed = candidate
        if loaded.rng.randi_range(1,100) <= 33:
            intercepted_seed = candidate
            break
    expect(intercepted_seed != -1,"random test finds a pirate hit")
    var pending: Dictionary = loaded.faction_fleets[0]
    var refund_amount: int = int(pending["payment"])
    pending["eta"] = 1
    loaded.cycle = 7
    loaded.rng.seed = maxi(1,intercepted_seed)
    var seller_before: int = int(loaded.faction_economy["Союз"]["treasury"])
    loaded._advance_faction_fleets()
    expect(loaded.faction_fleets.is_empty(),"last leg settled")
    expect(int(loaded.faction_economy["Консорциум"]["treasury"]) == buyer_refund+refund_amount,"piracy returns buyer escrow")
    expect(int(loaded.faction_economy["Союз"]["treasury"]) == seller_before,"piracy does not pay seller")
    var corrupt: Dictionary = loaded.snapshot().duplicate(true)
    corrupt["faction_fleets"] = [{"source":"Рой","destination":"Рой","resource":"food","amount":19,"payment":-1,"eta":0,"duration":0}]
    expect(not loaded._valid_snapshot(corrupt),"invalid NPC voyage rejected")
    var old: Dictionary = loaded.snapshot().duplicate(true)
    old["version"] = 6
    old.erase("faction_fleets")
    var f := FileAccess.open("user://perimeter_zero_slot_3.json",FileAccess.WRITE)
    f.store_string(JSON.stringify(old))
    f.close()
    var migrated = State.new()
    expect(migrated.load_game(3) == "","v6 save loads in v7")
    expect(migrated.faction_fleets.is_empty(),"legacy saves get empty NPC queue")
    print("PASS: NPC faction fleets, delayed settlement, escrow, save validation, v6 migration" if failures == 0 else "FAIL: %d v7 cases" % failures)
    quit(0 if failures == 0 else 1)
