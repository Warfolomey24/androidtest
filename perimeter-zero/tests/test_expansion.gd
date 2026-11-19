extends SceneTree
## Runtime regression tests for new connected simulation systems.
const State = preload("res://scripts/sim/game_state.gd")

var failures := 0

func expect(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error("FAIL: " + message)

func _initialize() -> void:
    var game = State.new()
    expect(game.colonies.size() == 1, "test_expansion.gd: assertion 1")
    expect(game.faction_standing.has("Союз"), "test_expansion.gd: assertion 2")
    expect(game.miners.size() == 2, "test_expansion.gd: assertion 3")
    expect(game.population_capacity() >= game.crew, "test_expansion.gd: assertion 4")
    expect(game.campaign_stage == 0, "test_expansion.gd: assertion 5")

    # Road connectivity and separately stored production.
    expect(game.colony_connected(0,3,4), "test_expansion.gd: assertion 6")
    expect(not game.colony_connected(0,11,7), "test_expansion.gd: assertion 7")
    expect(game.colony_build(0,"purifier",11,7) != "", "test_expansion.gd: assertion 8")
    expect(game.colony_build(0,"purifier",3,4) == "", "test_expansion.gd: assertion 9")
    expect(game.colony_upgrade(0,3,4) == "", "test_expansion.gd: assertion 10")
    expect(int(game.colonies[0]["buildings"].back()["level"]) == 2, "test_expansion.gd: assertion 11")
    expect(game.colony_build(0,"purifier",3,4) != "", "test_expansion.gd: assertion 12")

    # Colonies never add stock to station before the convoy ETA reaches zero.
    var logistic = State.new()
    logistic.sectors[0]["buildings"].clear()
    logistic.resources["ore"] = 0
    logistic.colonies[0]["stock"]["ore"] = 80
    logistic.step()
    expect(int(logistic.resources["ore"]) == 0, "test_expansion.gd: assertion 13")
    expect(int(logistic.colonies[0]["convoy"]["eta"]) > 0, "test_expansion.gd: assertion 14")
    for i in range(7):
        logistic.step()
    expect(int(logistic.resources["ore"]) > 0, "test_expansion.gd: assertion 15")

    # Miners need time to move between tiles. Hiring is capped.
    expect(game.hire_miner() == "", "test_expansion.gd: assertion 16")
    expect(game.miners.size() == 3, "test_expansion.gd: assertion 17")
    for i in range(5):
        game.hire_miner()
    expect(game.miners.size() == 8, "test_expansion.gd: assertion 18")
    expect(game.hire_miner() != "", "test_expansion.gd: assertion 19")

    # Explore first; colonies cannot be founded in unknown systems.
    var colony_game = State.new()
    expect(colony_game.found_colony(1) != "", "test_expansion.gd: assertion 20")
    colony_game.discovered.append(1)
    expect(colony_game.found_colony(1) == "", "test_expansion.gd: assertion 21")
    expect(colony_game.colonies.size() == 2, "test_expansion.gd: assertion 22")
    expect(colony_game.found_colony(1) != "", "test_expansion.gd: assertion 23")
    expect(colony_game.colony_assign_priority(1,"alloy") == "", "test_expansion.gd: assertion 24")

    # Shipyard has a real prerequisite, ships have classes and health.
    var fleet_game = State.new()
    expect(fleet_game.build_ship("escort") != "", "test_expansion.gd: assertion 25")
    expect(fleet_game.build("hangar",0,0,0) == "", "test_expansion.gd: assertion 26")
    expect(fleet_game.build_ship("scout") == "", "test_expansion.gd: assertion 27")
    expect(fleet_game.ships.size() == 3, "test_expansion.gd: assertion 28")
    expect(fleet_game.send_patrol(2,1) != "", "test_expansion.gd: assertion 29")
    fleet_game.discovered.append(1)
    expect(fleet_game.send_patrol(2,1) == "", "test_expansion.gd: assertion 30")
    expect(fleet_game.send_patrol(2,1) != "", "test_expansion.gd: assertion 31")

    # Contract cooldown, diplomacy and science prerequisites.
    var policy = State.new()
    expect(policy.complete_contract(0) == "", "test_expansion.gd: assertion 32")
    expect(policy.complete_contract(0) != "", "test_expansion.gd: assertion 33")
    expect(policy.contracts_completed == 1, "test_expansion.gd: assertion 34")
    var before := int(policy.faction_standing["Союз"])
    expect(policy.negotiate("Союз") == "", "test_expansion.gd: assertion 35")
    expect(int(policy.faction_standing["Союз"]) > before, "test_expansion.gd: assertion 36")
    expect(policy.research("singularity") != "", "test_expansion.gd: assertion 37")

    # JSON version 2, fleet/miners/colonies/diplomacy survive save and load.
    expect(colony_game.save_game() == "", "test_expansion.gd: assertion 38")
    var restored = State.new()
    expect(restored.load_game() == "", "test_expansion.gd: assertion 39")
    expect(restored.colonies.size() == 2, "test_expansion.gd: assertion 40")
    expect(restored.colonies[1]["priority"] == "alloy", "test_expansion.gd: assertion 41")
    expect(restored.miners.size() == 2, "test_expansion.gd: assertion 42")
    expect(int(restored.snapshot()["version"]) == 8, "test_expansion.gd: assertion 43")
    # The campaign win is gated behind the final technology and narrative progress.
    var victory_game = State.new()
    victory_game.discovered.append(4)
    victory_game.researched.append("singularity")
    victory_game.campaign_stage = 3
    victory_game.step()
    expect(victory_game.victory, "test_expansion.gd: assertion 44")

    print("PASS: colonies / road network / convoys / miners / fleet / contracts / diplomacy / save / victory")
    quit(0 if failures == 0 else 1)
