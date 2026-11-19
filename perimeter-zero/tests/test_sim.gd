extends SceneTree
## Usage: godot --headless --path . --script res://tests/test_sim.gd
const State = preload("res://scripts/sim/game_state.gd")

var failures := 0

func expect(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + message)

func _initialize() -> void:
    var game = State.new()
    expect(game.sectors.size() == 6, "test_sim.gd: assertion 1")
    expect(game.sectors[0]["open"], "test_sim.gd: assertion 2")
    expect(not game.sectors[1]["open"], "test_sim.gd: assertion 3")
    expect(game.ships.size() == 2, "test_sim.gd: assertion 4")

    var previous_credits := int(game.resources["credits"])
    expect(game.build("solar",0,0,0) == "", "test_sim.gd: assertion 5")
    expect(game.occupied(0,0,0), "test_sim.gd: assertion 6")
    expect(game.build("solar",0,0,0) != "", "test_sim.gd: assertion 7")

    var found := false
    var mining_x := 3
    var mining_y := 3
    for y in range(1,7):
        for x in range(1,11):
            if game.mine[y][x]["visible"] and game.mine[y][x+1]["kind"] == game.mine[y][x]["kind"]:
                mining_x = x
                mining_y = y
                found = true
                break
        if found:
            break
    expect(found, "test_sim.gd: assertion 8")
    var mineral: String = game.mine[mining_y][mining_x]["kind"]
    var mineral_before := int(game.resources[mineral])
    expect(game.mine_tile(mining_x,mining_y) == "", "test_sim.gd: assertion 9")
    expect(game.total_mine_storage() > 0, "test_sim.gd: assertion 10")
    expect(int(game.resources[mineral]) == mineral_before, "test_sim.gd: assertion 11") # No teleporting cargo
    expect(not game.mine_queue.is_empty(), "test_sim.gd: assertion 12")

    expect(game.send_ship(0,1) == "", "test_sim.gd: assertion 13")
    expect(game.send_ship(0,1) != "", "test_sim.gd: assertion 14")
    for i in range(6):
        game.step()
    expect(game.total_mine_storage() >= 0, "test_sim.gd: assertion 15")
    expect(1 in game.discovered, "test_sim.gd: assertion 16")
    expect(int(game.resources["credits"]) == previous_credits, "test_sim.gd: assertion 17")

    expect(game.research("fold_drive") != "", "test_sim.gd: assertion 18")
    expect(game.research("ore_vision") == "", "test_sim.gd: assertion 19")
    expect("ore_vision" in game.researched, "test_sim.gd: assertion 20")

    expect(game.trade("ore",5,false) == "", "test_sim.gd: assertion 21")
    expect(int(game.resources["credits"]) > previous_credits, "test_sim.gd: assertion 22")
    expect(game.open_sector(1) == "", "test_sim.gd: assertion 23")
    expect(game.sectors[1]["open"], "test_sim.gd: assertion 24")

    var snapshot = game.snapshot()
    expect(snapshot.has("sectors"), "test_sim.gd: assertion 25")
    expect(game.save_game() == "", "test_sim.gd: assertion 26")
    var loaded = State.new()
    expect(loaded.load_game() == "", "test_sim.gd: assertion 27")
    expect(loaded.cycle == game.cycle, "test_sim.gd: assertion 28")
    expect(loaded.sectors[1]["open"], "test_sim.gd: assertion 29")
    expect(loaded.researched.has("ore_vision"), "test_sim.gd: assertion 30")
    expect(loaded.ships.size() == game.ships.size(), "test_sim.gd: assertion 31")
    print("PASS: economy / sectors / mining / fleet / research / trade / save-load")
    quit(0 if failures == 0 else 1)
