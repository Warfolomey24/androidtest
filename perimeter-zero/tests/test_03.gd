extends SceneTree
## Regression tests: colony-specific freight, player decisions, robust saves and migration.
const State = preload("res://scripts/sim/game_state.gd")
var failures := 0

func expect(condition: bool, message: String) -> void:
    if not condition:
        push_error("FAIL: " + message)
        failures += 1

func _initialize() -> void:
    var station = State.new()
    expect(station.ships[1]["assigned_colony"] == 0, "Starter freighter assigned only to starter colony")
    expect(station.assign_freighter(0,0) != "", "Scout cannot become a freighter")
    expect(station.send_ship(1,1) != "", "Assigned ship must not depart on another mission")
    expect(station.assign_freighter(1,-1) == "", "Freighter can be unassigned")
    expect(station.send_ship(1,1) == "", "Unassigned freighter may explore")
    expect(station.assign_freighter(1,0) != "", "Freighter in flight cannot be reassigned")

    var logistics = State.new()
    logistics.discovered.append(1)
    expect(logistics.found_colony(1) == "", "Second colony can be founded")
    logistics.assign_freighter(1,-1)
    logistics.colonies[0]["stock"] = {"ore":140,"food":20,"water":20}
    logistics.colonies[1]["stock"] = {"ore":140,"food":20,"water":20}
    var ore_before: int = int(logistics.resources["ore"])
    logistics._advance_convoy(0)
    logistics._advance_convoy(1)
    var cargo0: int = int(logistics.colonies[0]["convoy"]["cargo"].get("ore",0))
    var cargo1: int = int(logistics.colonies[1]["convoy"]["cargo"].get("ore",0))
    expect(cargo0 == cargo1, "Both colonies without freighters have equal charter capacity")
    expect(int(logistics.resources["ore"]) == ore_before, "Departing cargo never teleports to station")
    logistics.assign_freighter(1,1)
    logistics.colonies[0]["convoy"] = {"eta":0,"cargo":{}}
    logistics.colonies[1]["convoy"] = {"eta":0,"cargo":{}}
    logistics._advance_convoy(0)
    logistics._advance_convoy(1)
    expect(int(logistics.colonies[1]["convoy"]["cargo"].get("ore",0)) > int(logistics.colonies[0]["convoy"]["cargo"].get("ore",0)), "Only assigned colony receives extra cargo capacity")
    expect(int(logistics.ships[1]["cargo_eta"]) > 0, "Assigned vessel is in a freight run")
    expect(logistics.assign_freighter(1,0) != "", "Vessel cannot teleport to another route during flight")
    var run_length: int = int(logistics.colonies[1]["convoy"]["eta"])
    for i in range(run_length):
        logistics._advance_convoy(1)
    expect(int(logistics.ships[1]["cargo_eta"]) == 0, "Freighter unlocks when delivery arrives")

    var story = State.new()
    story.cycle = 11
    story.step()
    expect(story.pending_story == "distress", "First campaign choice appears on cycle 12")
    var locked_cycle: int = int(story.cycle)
    story.step()
    expect(story.cycle == locked_cycle, "World time stops until decision is made")
    var previous_crew: int = int(story.crew)
    expect(story.resolve_story(0) == "", "Valid choice can be accepted")
    expect(story.crew == previous_crew + 8, "Refugee decision increases crew")
    expect(story.story_history.size() == 1, "Story decision persists in history")
    expect(story.resolve_story(0) != "", "No event can be resolved twice")
    story.step()
    expect(story.cycle == locked_cycle+1, "World resumes after a decision")

    var save = State.new()
    save.resources["ore"] = 91
    expect(save.save_game(2) == "", "Save to second manual slot")
    save.resources["ore"] = 23
    expect(save.save_game(2) == "", "Second save creates backup")
    var f := FileAccess.open("user://perimeter_zero_slot_2.json",FileAccess.WRITE)
    f.store_string("{corrupted")
    f.close()
    var loaded = State.new()
    expect(loaded.load_game(2) == "", "Corrupt main save can be recovered")
    expect(int(loaded.resources["ore"]) == 91, "Restored backup contains previous resources")
    expect(loaded.load_game(4) != "", "Out-of-range save slot is rejected")

    # Legacy v2 migration assigns -1 to ships without a route field.
    var legacy: Dictionary = save.snapshot().duplicate(true)
    legacy["version"] = 2
    legacy.erase("pending_story")
    legacy.erase("resolved_stories")
    legacy.erase("story_history")
    for ship in legacy["ships"]:
        ship.erase("assigned_colony")
    var file := FileAccess.open("user://perimeter_zero_slot_3.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(legacy))
    file.close()
    var migrated = State.new()
    expect(migrated.load_game(3) == "", "Legacy v2 loads")
    expect(int(migrated.ships[1].get("assigned_colony",-99)) == -1, "Legacy ships migrate to unassigned status")
    expect(int(migrated.snapshot()["version"]) == 8, "Current saves have schema v8")

    if failures > 0:
        print("FAIL: " + str(failures) + " Alpha 0.3 regression checks")
        quit(1)
    else:
        print("PASS: per-colony logistics / story freeze / save backups / v2 migration")
        quit(0)
