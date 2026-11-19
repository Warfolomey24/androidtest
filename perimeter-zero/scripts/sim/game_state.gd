extends RefCounted
## Deterministic, saveable gameplay logic. UI never mutates resources directly.
const Db = preload("res://scripts/sim/database.gd")
const SAVE_PATH := "user://perimeter_zero_save.json"
const GRID_W := 12
const GRID_H := 8

var cycle: int = 1
var world_seed: int = 148833
var resources: Dictionary = {}
var sectors: Array = []
var mine: Array = []
var mine_queue: Array = []
var miners: Array = []
var mine_stockpile: Dictionary = {}
var shuttle: Dictionary = {}
var cargo_priority: String = "ore"
var colonies: Array = []
var faction_standing: Dictionary = {}
var faction_economy: Dictionary = {}
var trade_flights: Array = []
var faction_fleets: Array = []
var pirate_threat: int = 18
var patrol_cover: Dictionary = {}
var pending_battle: Dictionary = {}
var contract_ready: Array = []
var contracts_completed: int = 0
var campaign_stage: int = 0
var pending_story: String = ""
var resolved_stories: Array = []
var story_history: Array = []
var ship_serial: int = 2
var ships: Array = []
var researched: Array = []
var discovered: Array = [0]
var current_system: int = 0
var trust: float = 80.0
var hull: float = 88.0
var crew: int = 110
var event_log: Array = []
var victory: bool = false
var defeated: bool = false
var rng := RandomNumberGenerator.new()

func _init() -> void:
    start_new()

func start_new(seed: int = 148833) -> void:
    world_seed = seed
    rng.seed = world_seed
    cycle = 1
    resources = {"ore":42, "alloy":88, "polymer":45, "food":72, "water":70,
                 "fuel":45, "science":12, "credits":650, "silicon":22, "copper":0, "ice":0, "components":12}
    sectors = []
    for i in range(6):
        sectors.append({"open":i == 0, "buildings":[], "population":110 if i == 0 else 0})
    var initial = [
        ["reactor",1,1], ["habitat",3,1], ["farm",5,1],
        ["recycler",7,1], ["habitat",9,1], ["laboratory",2,4], ["warehouse",5,4],
        ["smelter",8,4]
    ]
    for entry in initial:
        sectors[0]["buildings"].append({"id":entry[0], "x":entry[1], "y":entry[2], "level":1})
    researched = []
    discovered = [0]
    current_system = 0
    trust = 80.0
    hull = 88.0
    crew = 110
    victory = false
    defeated = false
    mine_queue = []
    miners = [
        {"name":"Шахтёр-01","x":3,"y":3,"target_x":-1,"target_y":-1,"eta":0,"total_eta":0},
        {"name":"Шахтёр-02","x":3,"y":3,"target_x":-1,"target_y":-1,"eta":0,"total_eta":0}
    ]
    mine_stockpile = {"ore":0,"silicon":0,"copper":0,"ice":0}
    shuttle = {"eta":0,"cargo":{}}
    cargo_priority = "ore"
    ships = [
        {"name":"Следопыт-01", "target":-1, "eta":0, "health":100, "runs":0, "type":"scout", "mission":"explore", "assigned_colony":-1,"cargo_eta":0},
        {"name":"Грузовик-02", "target":-1, "eta":0, "health":100, "runs":0, "type":"freighter", "mission":"explore", "assigned_colony":0,"cargo_eta":0}
    ]
    faction_standing = {"Союз":20, "Консорциум":0, "Рой":-45}
    faction_economy = _default_faction_economy()
    trade_flights = []
    faction_fleets = []
    pirate_threat = 18
    patrol_cover = {}
    pending_battle = {}
    contract_ready = [1,1,1]
    contracts_completed = 0
    campaign_stage = 0
    pending_story = ""
    resolved_stories = []
    story_history = []
    ship_serial = 2
    colonies = [_make_colony(0, "Форпост «Терра»", true)]
    mine = []
    for y in range(GRID_H):
        var row: Array = []
        for x in range(GRID_W):
            var ore_kind := "ore"
            var roll := rng.randi_range(0, 100)
            if x > 8:
                ore_kind = "copper" if roll < 60 else "ice"
            elif x > 5:
                ore_kind = "silicon" if roll < 67 else "ore"
            elif roll > 87:
                ore_kind = "ice"
            row.append({"kind":ore_kind, "amount":rng.randi_range(3, 9),
                        "visible": abs(x-3) <= 2 and abs(y-3) <= 2})
        mine.append(row)
    event_log = ["Связь восстановлена. Станция «Периметр» готова к работе."]

func log_message(message: String) -> void:
    event_log.push_front("Цикл %d · %s" % [cycle, message])
    if event_log.size() > 12:
        event_log.pop_back()

func can_afford(costs: Dictionary) -> bool:
    for id in costs.keys():
        if float(resources.get(id, 0)) < float(costs[id]):
            return false
    return true

func spend(costs: Dictionary) -> bool:
    if not can_afford(costs):
        return false
    for id in costs.keys():
        resources[id] = float(resources.get(id, 0)) - float(costs[id])
    return true

func earn(goods: Dictionary) -> void:
    for id in goods.keys():
        resources[id] = float(resources.get(id, 0)) + float(goods[id])

func total_buildings(building_id: String) -> int:
    var count := 0
    for sector in sectors:
        if not sector["open"]:
            continue
        for building in sector["buildings"]:
            if building["id"] == building_id:
                count += 1
    return count

func occupied(sector_index: int, x: int, y: int) -> bool:
    if sector_index < 0 or sector_index >= sectors.size():
        return true
    for building in sectors[sector_index]["buildings"]:
        if int(building["x"]) == x and int(building["y"]) == y:
            return true
    return false

func build(building_id: String, sector_index: int, x: int, y: int) -> String:
    if defeated or victory:
        return "Игра завершена"
    if not Db.BUILDINGS.has(building_id):
        return "Неизвестный тип здания"
    if sector_index < 0 or sector_index >= sectors.size() or not sectors[sector_index]["open"]:
        return "Сектор закрыт"
    if x < 0 or x >= GRID_W or y < 0 or y >= GRID_H or occupied(sector_index,x,y):
        return "Клетка недоступна"
    var building: Dictionary = Db.BUILDINGS[building_id]
    if not spend(building["cost"]):
        return "Недостаточно материалов"
    sectors[sector_index]["buildings"].append({"id":building_id,"x":x,"y":y,"level":1})
    log_message("Построено: %s" % building["name"])
    return ""

func open_sector(sector_index: int) -> String:
    if sector_index < 0 or sector_index >= sectors.size():
        return "Сектор не существует"
    if sectors[sector_index]["open"]:
        return "Сектор уже открыт"
    if not spend({"alloy":45,"polymer":20}):
        return "Для открытия нужны 45 сплавов и 20 полимеров"
    sectors[sector_index]["open"] = true
    log_message("Герметизирован сектор %d" % (sector_index+1))
    return ""

func population_capacity() -> int:
    var capacity := 0
    for sector in sectors:
        if not bool(sector["open"]):
            continue
        for entry in sector["buildings"]:
            if entry["id"] == "habitat":
                capacity += 55 * int(entry.get("level",1))
    return capacity

func sector_capacity(index: int) -> int:
    var cap := 0
    if index < 0 or index >= sectors.size():
        return 0
    for building in sectors[index]["buildings"]:
        if building["id"] == "habitat":
            cap += 55 * int(building.get("level",1))
    return cap

func transfer_crew(source: int, destination: int, amount: int = 10) -> String:
    if source < 0 or source >= sectors.size() or destination < 0 or destination >= sectors.size() or source == destination or amount <= 0:
        return "Некорректный перевод экипажа"
    if not bool(sectors[destination]["open"]):
        return "Целевой сектор закрыт"
    if int(sectors[source]["population"]) < amount:
        return "Недостаточно людей в исходном секторе"
    if int(sectors[destination]["population"]) + amount > sector_capacity(destination):
        return "Недостаточно жилых мест в целевом секторе"
    sectors[source]["population"] = int(sectors[source]["population"]) - amount
    sectors[destination]["population"] = int(sectors[destination]["population"]) + amount
    log_message("Переведено %d работников: сектор %d → %d" % [amount,source+1,destination+1])
    return ""

func upgrade_station_building(sector_index: int, x: int, y: int) -> String:
    if sector_index < 0 or sector_index >= sectors.size() or not bool(sectors[sector_index]["open"]):
        return "Сектор недоступен"
    for building in sectors[sector_index]["buildings"]:
        if int(building["x"]) != x or int(building["y"]) != y:
            continue
        var lvl := int(building.get("level",1))
        if lvl >= 10:
            return "Максимальный уровень — 10"
        if not spend({"alloy":6+lvl*5,"polymer":3+lvl*2}):
            return "Недостаточно материалов для улучшения"
        building["level"] = lvl+1
        log_message("Сектор %d: улучшен %s до уровня %d" % [sector_index+1,Db.BUILDINGS[building["id"]]["name"],lvl+1])
        return ""
    return "Строение не найдено"

func dismantle_station_building(sector_index: int, x: int, y: int) -> String:
    if sector_index < 0 or sector_index >= sectors.size() or not bool(sectors[sector_index]["open"]):
        return "Сектор недоступен"
    var items: Array = sectors[sector_index]["buildings"]
    for i in range(items.size()):
        var building: Dictionary = items[i]
        if int(building["x"]) == x and int(building["y"]) == y:
            if building["id"] == "habitat" and population_capacity() - 55*int(building.get("level",1)) < crew:
                return "Сначала обеспечьте жильём экипаж"
            var cost: Dictionary = Db.BUILDINGS[building["id"]]["cost"]
            var refunded: Dictionary = {}
            for resource_id in cost.keys():
                refunded[resource_id] = int(int(cost[resource_id]) / 2)
            items.remove_at(i)
            earn(refunded)
            log_message("Здание демонтировано; возвращена часть материалов")
            return ""
    return "Строение не найдено"

func power_balance() -> int:
    var power := 0
    for sector in sectors:
        if sector["open"]:
            for building in sector["buildings"]:
                if building["id"] != "reactor" or float(resources.get("fuel",0)) > 0:
                    var base: int = int(Db.BUILDINGS[building["id"]]["power"])
                    var lvl: int = int(building.get("level",1))
                    power += base + (8 * (lvl-1) if base > 0 else -1 * (lvl-1))
                    if building["id"] == "reactor" and "fusion_cores" in researched:
                        power += 14
    return power

func workers_required() -> int:
    var workers := 0
    for sector in sectors:
        if sector["open"]:
            for building in sector["buildings"]:
                workers += int(Db.BUILDINGS[building["id"]]["workers"])
    return workers

func step() -> void:
    # Story decisions are resolved by the player; pause simulation, not only the UI.
    if not pending_story.is_empty() or not pending_battle.is_empty():
        return
    if victory or defeated:
        return
    cycle += 1
    _run_production()
    _crew_needs()
    _advance_ships()
    _advance_faction_trade()
    _advance_faction_fleets()
    _advance_mining()
    _advance_shuttle()
    _advance_colonies()
    if cycle % 4 == 0:
        _advance_faction_economy()
    if cycle % 9 == 0:
        _random_event()
        pirate_threat = mini(75,pirate_threat+3)
    if hull <= 0.0 or trust <= 0.0 or crew <= 0:
        defeated = true
        log_message("Станция потеряна. Эвакуация невозможна")
    _advance_campaign()
    _advance_story()
    if 4 in discovered and "singularity" in researched and campaign_stage >= 3 and hull >= 30.0 and trust >= 20.0:
        victory = true
        log_message("Нулевая орбита стабилизирована. Поколение поселенцев спасено")

func _run_production() -> void:
    var enough_power := power_balance() >= 0
    var enough_workers := workers_required() <= crew
    if not enough_power:
        trust = maxf(0.0, trust - 1.4)
    if not enough_workers:
        trust = maxf(0.0, trust - 0.6)
    if not enough_power or not enough_workers:
        log_message("Нарушено снабжение: проверьте энергию и персонал")
        return
    for sector in sectors:
        if not sector["open"]:
            continue
        var workers_left := int(sector.get("population",0))
        for entry in sector["buildings"]:
            var spec: Dictionary = Db.BUILDINGS[entry["id"]]
            var workers: int = int(spec["workers"])
            if workers_left < workers:
                continue
            workers_left -= workers
            if spend(spec["consume"]):
                var prod: Dictionary = spec["produce"].duplicate(true)
                var lvl: int = int(entry.get("level",1))
                for res in prod.keys():
                    prod[res] = int(prod[res]) + (lvl-1)
                if entry["id"] == "farm" and "hydroponics" in researched:
                    prod["food"] = int(prod["food"]) + 1
                earn(prod)
                if spec.has("repair"):
                    hull = minf(100.0,hull + float(spec["repair"]) + float(lvl-1))
                if spec.has("morale"):
                    trust = minf(100.0, trust + 0.15)
    var loss := 0.65 if "shielding" in researched else 1.0
    hull = maxf(0.0,hull - loss)

func _crew_needs() -> void:
    var daily_food := maxi(1, ceili(float(crew) / 40.0))
    var daily_water := maxi(1, ceili(float(crew) / 40.0))
    if spend({"food":daily_food,"water":daily_water}):
        trust = minf(100.0, trust+0.12)
    else:
        trust = maxf(0.0, trust-4.0)
        crew = maxi(0, crew-2)
        log_message("Пайки исчерпаны. Экипаж теряет доверие")
    if crew > population_capacity():
        trust = maxf(0.0, trust - 0.7)

func _advance_ships() -> void:
    for ship_index in range(ships.size()):
        var ship: Dictionary = ships[ship_index]
        if int(ship["eta"]) <= 0:
            continue
        ship["eta"] = int(ship["eta"]) - 1
        if int(ship["eta"]) > 0:
            continue
        var destination := int(ship["target"])
        var star: Dictionary = Db.SYSTEMS[destination]
        var ship_type: String = str(ship.get("type","scout"))
        var template: Dictionary = Db.SHIP_TYPES[ship_type]
        var is_patrol := str(ship.get("mission","explore")) == "patrol"
        if is_patrol:
            if not pending_battle.is_empty():
                ship["eta"] = 1
                continue
            _begin_patrol_battle(ship_index, destination)
            continue
        else:
            var found_resource: String = star["ore"]
            var amount: int = mini(int(template["cargo"]),8 + int(int(template["cargo"])/2) + int(ship["runs"])%5 + (10 if "logistic_ai" in researched else 0))
            earn({found_resource:amount,"science":4})
            if not destination in discovered:
                discovered.append(destination)
            var severity: int = maxi(0,int(star["risk"]) - (1 if "deep_scanners" in researched else 0))
            ship["health"] = maxi(0,int(ship["health"]) - severity * 9)
            if severity > 1:
                hull = maxf(0.0, hull - severity*0.8)
            log_message("%s: экспедиция завершена, +%d %s" % [ship["name"],amount,Db.label_for(found_resource)])
        if int(ship["health"]) == 0:
            log_message("Потерян корабль %s; необходим новый корабль" % ship["name"])
        ship["runs"] = int(ship["runs"]) + 1
        ship["target"] = -1
        ship["mission"] = "explore"

# Tactical encounters interrupt strategic time until the player issues an order.
# All statistics are deterministic for a given random state and survive save/load.
func _begin_patrol_battle(ship_index: int, destination: int) -> void:
    var enemy_risk: int = int(Db.SYSTEMS[destination]["risk"])
    var enemy_hull: int = 28 + enemy_risk * 19 + int(pirate_threat / 5)
    pending_battle = {
        "ship_index":ship_index, "destination":destination,
        "enemy_hp":enemy_hull, "enemy_max_hp":enemy_hull,
        "enemy_attack":8+enemy_risk*5, "enemy_defense":4+enemy_risk*3,
        "turn":1, "scanned":false
    }
    log_message("Тревога: %s вступил в бой в системе %s" % [ships[ship_index]["name"],Db.SYSTEMS[destination]["name"]])

func battle_action(action: String) -> String:
    if pending_battle.is_empty():
        return "Активного столкновения нет"
    if not action in ["salvo","precision","brace","retreat","scan"]:
        return "Неизвестная команда"
    var battle: Dictionary = pending_battle
    var ship_index: int = int(battle["ship_index"])
    var ship: Dictionary = ships[ship_index]
    var ship_type: String = str(ship.get("type","scout"))
    var spec: Dictionary = Db.SHIP_TYPES[ship_type]
    if action == "scan":
        if bool(battle["scanned"]):
            return "Сканирование уже выполнено"
        battle["scanned"] = true
        log_message("Сканер: вражеский корпус %d, атака %d, защита %d" % [int(battle["enemy_hp"]),int(battle["enemy_attack"]),int(battle["enemy_defense"])])
        return ""
    if action == "retreat":
        ship["health"] = maxi(1,int(ship["health"])-maxi(2,int(battle["enemy_attack"] / 4)))
        log_message("Корабль %s отступил; корпус %d%%" % [ship["name"],int(ship["health"])])
        _finish_battle(false)
        return ""
    var attack: int = int(spec["attack"]) + (12 if "fleet_tactics" in researched else 0)
    var damage: int = 0
    if action == "salvo":
        damage = maxi(2,attack + rng.randi_range(1,6) - int(battle["enemy_defense"]/3))
    elif action == "precision":
        damage = maxi(2,int(attack/2)+rng.randi_range(2,6)-int(battle["enemy_defense"]/4))
        battle["enemy_attack"] = maxi(2,int(battle["enemy_attack"])-4)
    else: # brace: survive a dangerous round and recharge the weapons
        damage = 0
    battle["enemy_hp"] = maxi(0,int(battle["enemy_hp"])-damage)
    if int(battle["enemy_hp"]) <= 0:
        _finish_battle(true)
        return ""
    var defense: int = int(spec["defense"])+(6 if "fleet_tactics" in researched else 0)
    var incoming: int = maxi(1,int(battle["enemy_attack"])+rng.randi_range(0,4)-int(defense/2))
    if action == "brace":
        incoming = maxi(1,int(ceili(float(incoming)*0.35)))
    ship["health"] = maxi(0,int(ship["health"])-incoming)
    battle["turn"] = int(battle["turn"])+1
    if int(ship["health"]) <= 0:
        log_message("Боевая потеря: %s уничтожен" % ship["name"])
        _finish_battle(false)
    else:
        log_message("Бой: враг −%d, наш корпус −%d" % [damage,incoming])
    return ""

func _finish_battle(won: bool) -> void:
    if pending_battle.is_empty():
        return
    var battle: Dictionary = pending_battle
    var ship: Dictionary = ships[int(battle["ship_index"])]
    if won:
        var star: Dictionary = Db.SYSTEMS[int(battle["destination"])]
        earn({"credits":60+int(star["risk"])*35,"components":2})
        change_faction_standing(str(star["faction"]),-3)
        pirate_threat = maxi(0,pirate_threat-12)
        patrol_cover[str(star["faction"])] = cycle+9
        log_message("Победа в системе %s. Трофеи доставлены" % star["name"])
    ship["runs"] = int(ship["runs"])+1
    ship["target"] = -1
    ship["eta"] = 0
    ship["mission"] = "explore"
    pending_battle = {}

func can_send_to(destination: int) -> bool:
    if destination <= 0 or destination >= Db.SYSTEMS.size():
        return false
    if destination == 4 and not "fold_drive" in researched:
        return false
    if destination == 7 and not "stellar_cartography" in researched:
        return false
    for connection in Db.LINKS:
        if (int(connection[0]) == destination and int(connection[1]) in discovered) or (int(connection[1]) == destination and int(connection[0]) in discovered):
            return true
    return false

func send_ship(ship_index: int, destination: int) -> String:
    if not pending_battle.is_empty():
        return "Сначала завершите бой"
    if ship_index < 0 or ship_index >= ships.size():
        return "Корабль не найден"
    if not can_send_to(destination):
        return "Маршрут закрыт. Требуется новая технология"
    var ship: Dictionary = ships[ship_index]
    if int(ship["eta"]) > 0:
        return "Корабль уже в экспедиции"
    if int(ship.get("health",100)) <= 0:
        return "Корабль потерян и не может лететь"
    if int(ship.get("cargo_eta",0)) > 0:
        return "Грузовоз уже выполняет рейс"
    if int(ship.get("assigned_colony",-1)) >= 0:
        return "Грузовоз назначен на колониальный маршрут. Сначала снимите назначение"
    if not spend({"fuel":4}):
        return "Недостаточно топлива (4)"
    ship["target"] = destination
    ship["mission"] = "explore"
    ship["eta"] = 3 + int(Db.SHIP_TYPES[str(ship.get("type","scout"))]["speed"]) + int(Db.SYSTEMS[destination]["risk"])
    log_message("%s направлен в систему %s" % [ship["name"],Db.SYSTEMS[destination]["name"]])
    return ""

func reveal_around(x: int, y: int, radius: int = 1) -> void:
    for oy in range(maxi(0,y-radius),mini(GRID_H,y+radius+1)):
        for ox in range(maxi(0,x-radius),mini(GRID_W,x+radius+1)):
            mine[oy][ox]["visible"] = true

func mine_tile(x: int, y: int, auto_chain: bool = true) -> String:
    if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H:
        return "За пределами шахты"
    var tile: Dictionary = mine[y][x]
    if not tile["visible"]:
        return "Область ещё не разведана"
    if int(tile["amount"]) <= 0:
        return "Пласт уже выработан"
    var ore_id: String = tile["kind"]
    var amount := mini(int(tile["amount"]),5 if "better_drills" in researched else 3)
    if total_mine_storage() + amount > 140 + total_buildings("warehouse") * 80:
        return "Склад шахты переполнен. Дождитесь грузового рейса"
    tile["amount"] = int(tile["amount"]) - amount
    mine_stockpile[ore_id] = int(mine_stockpile.get(ore_id,0)) + amount
    reveal_around(x,y)
    if auto_chain:
        mine_queue.clear()
        var visited: Dictionary = {}
        var pending: Array = [[x,y]]
        while not pending.is_empty():
            var pos: Array = pending.pop_front()
            var px: int = int(pos[0])
            var py: int = int(pos[1])
            var key := "%d:%d" % [px,py]
            if visited.has(key):
                continue
            visited[key] = true
            if mine[py][px]["kind"] != ore_id:
                continue
            if (px != x or py != y) and int(mine[py][px]["amount"]) > 0:
                mine_queue.append([px,py])
            for side in [[1,0],[-1,0],[0,1],[0,-1]]:
                var nx: int = px + int(side[0])
                var ny: int = py + int(side[1])
                if nx >= 0 and nx < GRID_W and ny >= 0 and ny < GRID_H:
                    if mine[ny][nx]["kind"] == ore_id:
                        pending.append([nx,ny])
    log_message("Склад шахты: +%d %s (ожидает перевозки)" % [amount,Db.label_for(ore_id)])
    return ""

func _advance_mining() -> void:
    for miner in miners:
        if int(miner["eta"]) > 0:
            miner["eta"] = int(miner["eta"])-1
            if int(miner["eta"]) == 0:
                var x := int(miner["target_x"])
                var y := int(miner["target_y"])
                miner["x"] = x
                miner["y"] = y
                miner["target_x"] = -1
                miner["target_y"] = -1
                if x >= 0 and y >= 0 and int(mine[y][x]["amount"]) > 0:
                    reveal_around(x,y)
                    var result := mine_tile(x,y,false)
                    if result != "":
                        mine_queue.push_front([x,y])
                    elif int(mine[y][x]["amount"]) > 0:
                        mine_queue.append([x,y])
            continue
        while not mine_queue.is_empty():
            var pos: Array = mine_queue.pop_front()
            var tx := int(pos[0])
            var ty := int(pos[1])
            if int(mine[ty][tx]["amount"]) <= 0:
                continue
            miner["target_x"] = tx
            miner["target_y"] = ty
            var distance := absi(int(miner["x"])-tx) + absi(int(miner["y"])-ty)
            miner["eta"] = maxi(1,int(ceili(float(distance)/float(5 if "better_drills" in researched else 3))))
            miner["total_eta"] = int(miner["eta"])
            break

func hire_miner() -> String:
    if miners.size() >= 8:
        return "В шахте максимум 8 шахтёров. Необходимо расширение инфраструктуры"
    if not spend({"credits":70}):
        return "Найм шахтёра стоит 70 кредитов"
    var number := miners.size()+1
    miners.append({"name":"Шахтёр-%02d" % number,"x":3,"y":3,"target_x":-1,"target_y":-1,"eta":0,"total_eta":0})
    log_message("В шахту назначен шахтёр №%d" % number)
    return ""

func total_mine_storage() -> int:
    var total := 0
    for key in mine_stockpile.keys():
        total += int(mine_stockpile[key])
    return total

func set_cargo_priority(id: String) -> void:
    if mine_stockpile.has(id):
        cargo_priority = id

func _advance_shuttle() -> void:
    ## Cargo takes actual cycles to reach the station. No teleporting ore.
    if int(shuttle["eta"]) > 0:
        shuttle["eta"] = int(shuttle["eta"]) - 1
        if int(shuttle["eta"]) == 0:
            var delivered: Dictionary = shuttle["cargo"]
            earn(delivered)
            log_message("Грузовой шаттл доставил %d единиц сырья" % _cargo_amount(delivered))
            shuttle["cargo"] = {}
        return
    var volume := 8 + (4 if "logistic_ai" in researched else 0)
    var ids := [cargo_priority]
    for key in mine_stockpile.keys():
        if key != cargo_priority:
            ids.append(key)
    var loading: Dictionary = {}
    for id in ids:
        if volume <= 0:
            break
        var units := mini(volume,int(mine_stockpile.get(id,0)))
        if units <= 0:
            continue
        mine_stockpile[id] = int(mine_stockpile[id]) - units
        loading[id] = units
        volume -= units
    if not loading.is_empty():
        shuttle["cargo"] = loading
        shuttle["eta"] = 2

func _cargo_amount(goods: Dictionary) -> int:
    var total := 0
    for value in goods.values():
        total += int(value)
    return total

func survey_mine() -> String:
    if not spend({"credits":55}):
        return "Разведка стоит 55 кредитов"
    var discovered_tiles := 0
    for y in range(GRID_H):
        for x in range(GRID_W):
            if not mine[y][x]["visible"] and discovered_tiles < 8:
                mine[y][x]["visible"] = true
                discovered_tiles += 1
    log_message("Разведка раскрыла %d участков" % discovered_tiles)
    return ""

func research(id: String) -> String:
    var spec := Db.tech_by_id(id)
    if spec.is_empty():
        return "Неизвестная технология"
    if id in researched:
        return "Технология уже изучена"
    for dependency in spec["requires"]:
        if not dependency in researched:
            return "Не выполнены условия исследования"
    if not spend({"science":spec["cost"]}):
        return "Недостаточно научных очков"
    researched.append(id)
    if id == "ore_vision":
        reveal_around(6,4,2)
    log_message("Открыта технология: %s" % spec["name"])
    return ""

func market_price(resource_id: String) -> int:
    var base := int(Db.MARKETS.get(resource_id,0))
    var change := (cycle % 7) - 3
    return maxi(1,base + change)

func trade(resource_id: String, quantity: int, buying: bool) -> String:
    if not Db.MARKETS.has(resource_id) or quantity <= 0:
        return "Операция недоступна"
    var unit := market_price(resource_id)
    if buying:
        if not spend({"credits":unit*quantity}):
            return "Недостаточно кредитов"
        earn({resource_id:quantity})
    else:
        if not spend({resource_id:quantity}):
            return "Недостаточно товара"
        earn({"credits":unit*quantity})
    log_message("Торговая сделка: %s ×%d" % [Db.label_for(resource_id),quantity])
    return ""

func complete_contract(index: int) -> String:
    if index < 0 or index >= Db.CONTRACTS.size():
        return "Контракт не найден"
    var contract: Dictionary = Db.CONTRACTS[index]
    if cycle < int(contract_ready[index]):
        return "Контракт снова доступен через %d циклов" % (int(contract_ready[index])-cycle)
    var good: String = contract["resource"]
    if not spend({good:contract["amount"]}):
        return "Недостаточно ресурсов для контракта"
    earn({"credits":contract["reward"]})
    trust = minf(100.0, trust + float(contract["trust"]))
    contract_ready[index] = cycle+7
    contracts_completed += 1
    if "colony_governance" in researched:
        change_faction_standing("Союз",2)
    log_message("Контракт выполнен: %s" % contract["name"])
    return ""

func emergency_repair() -> String:
    if not spend({"alloy":8}):
        return "Нужно 8 сплавов"
    hull = minf(100.0,hull+12.0)
    log_message("Восстановлена обшивка станции")
    return ""

func _random_event() -> void:
    var roll := rng.randi_range(0,2)
    match roll:
        0:
            hull = maxf(0.0,hull-6.0)
            log_message("Метеоритное облако: обшивка повреждена")
        1:
            earn({"food":12})
            log_message("Соседняя колония отправила гуманитарный груз")
        _:
            trust = maxf(0.0,trust-2.0)
            earn({"science":8})
            log_message("Перегруженный эксперимент: наука +8, доверие −2")

func snapshot() -> Dictionary:
    return {"version":8,"cycle":cycle,"world_seed":world_seed,"resources":resources,"sectors":sectors,
            "pending_story":pending_story,"resolved_stories":resolved_stories,"story_history":story_history,
            "colonies":colonies,"faction_standing":faction_standing,
            "faction_economy":faction_economy,"trade_flights":trade_flights,"faction_fleets":faction_fleets,
            "pirate_threat":pirate_threat,"patrol_cover":patrol_cover,"pending_battle":pending_battle,
            "contract_ready":contract_ready,
            "contracts_completed":contracts_completed,"campaign_stage":campaign_stage,"ship_serial":ship_serial,
            "mine":mine,"mine_queue":mine_queue,"miners":miners,"mine_stockpile":mine_stockpile,
            "shuttle":shuttle,"cargo_priority":cargo_priority,"ships":ships,"researched":researched,
            "discovered":discovered,"current_system":current_system,
            "trust":trust,"hull":hull,"crew":crew,"event_log":event_log,
            "victory":victory,"defeated":defeated,"rng_state":str(rng.state)}

# Three manual slots (1–3) and a rolling autosave (0), with validated .bak recovery.
func _save_path(slot: int) -> String:
    return SAVE_PATH if slot == 0 else "user://perimeter_zero_slot_%d.json" % slot

func _valid_snapshot(data: Variant) -> bool:
    if typeof(data) != TYPE_DICTIONARY or int(data.get("version",0)) not in [1,2,3,4,5,6,7,8]:
        return false
    for key in ["resources","sectors","ships","mine","researched","discovered"]:
        if not data.has(key):
            return false
    if typeof(data["resources"]) != TYPE_DICTIONARY or typeof(data["sectors"]) != TYPE_ARRAY or data["sectors"].size() != 6:
        return false
    if typeof(data["mine"]) != TYPE_ARRAY or data["mine"].size() != GRID_H:
        return false
    if typeof(data["ships"]) != TYPE_ARRAY or typeof(data["researched"]) != TYPE_ARRAY or typeof(data["discovered"]) != TYPE_ARRAY:
        return false
    for sector in data["sectors"]:
        if typeof(sector) != TYPE_DICTIONARY or not sector.has("buildings") or not sector.has("open") or not sector.has("population"):
            return false
        if typeof(sector["buildings"]) != TYPE_ARRAY:
            return false
    for row in data["mine"]:
        if typeof(row) != TYPE_ARRAY or row.size() != GRID_W:
            return false
        for tile in row:
            if typeof(tile) != TYPE_DICTIONARY or not tile.has("kind") or not tile.has("amount") or not tile.has("visible"):
                return false
    for ship in data["ships"]:
        if typeof(ship) != TYPE_DICTIONARY:
            return false
        for key in ["name","target","eta","health","runs"]:
            if not ship.has(key):
                return false
    if data.has("colonies"):
        if typeof(data["colonies"]) != TYPE_ARRAY:
            return false
        for colony in data["colonies"]:
            if typeof(colony) != TYPE_DICTIONARY:
                return false
            for key in ["name","system","population","stock","priority","convoy","buildings","morale"]:
                if not colony.has(key):
                    return false
            if typeof(colony["stock"]) != TYPE_DICTIONARY or typeof(colony["convoy"]) != TYPE_DICTIONARY or typeof(colony["buildings"]) != TYPE_ARRAY:
                return false
            if not colony["convoy"].has("eta") or not colony["convoy"].has("cargo"):
                return false
            if colony.has("hauls"):
                if typeof(colony["hauls"]) != TYPE_ARRAY:
                    return false
                for job in colony["hauls"]:
                    if typeof(job) != TYPE_DICTIONARY:
                        return false
                    for field in ["cargo","path","eta","total_eta"]:
                        if not job.has(field):
                            return false
                    if typeof(job["cargo"]) != TYPE_DICTIONARY or typeof(job["path"]) != TYPE_ARRAY or job["path"].size() < 2:
                        return false
                    if int(job["eta"]) < 0 or int(job["total_eta"]) <= 0 or int(job["eta"]) > int(job["total_eta"]):
                        return false
                    for resource in job["cargo"].keys():
                        if not Db.RESOURCE_LABELS.has(resource) or int(job["cargo"][resource]) < 0:
                            return false
                    for point in job["path"]:
                        if typeof(point) != TYPE_ARRAY or point.size() != 2:
                            return false
                        if int(point[0]) < 0 or int(point[0]) >= GRID_W or int(point[1]) < 0 or int(point[1]) >= GRID_H:
                            return false
            for building in colony["buildings"]:
                if typeof(building) != TYPE_DICTIONARY or not building.has("id") or not Db.COLONY_BUILDINGS.has(str(building["id"])):
                    return false
    if int(data.get("version",0)) >= 5:
        if typeof(data.get("faction_economy")) != TYPE_DICTIONARY or typeof(data.get("trade_flights")) != TYPE_ARRAY:
            return false
        if int(data.get("pirate_threat",-1)) < 0 or int(data.get("pirate_threat",-1)) > 100:
            return false
        for faction in Db.FACTION_IDS:
            if not data["faction_economy"].has(faction):
                return false
            var economy: Variant = data["faction_economy"][faction]
            if typeof(economy) != TYPE_DICTIONARY or typeof(economy.get("stock")) != TYPE_DICTIONARY or int(economy.get("treasury",-1)) < 0:
                return false
            for res in economy["stock"].keys():
                if not Db.RESOURCE_LABELS.has(res) or int(economy["stock"][res]) < 0:
                    return false
        var used_freighters: Array = []
        var used_escorts: Array = []
        for flight in data["trade_flights"]:
            if typeof(flight) != TYPE_DICTIONARY:
                return false
            for key in ["faction","resource","amount","buy","payment","eta","duration","ship_index"]:
                if not flight.has(key):
                    return false
            if not str(flight["faction"]) in ["Союз","Консорциум"]:
                return false
            if not str(flight["resource"]) in Db.FACTION_TRADE[str(flight["faction"])]["goods"]:
                return false
            if int(flight["amount"]) <= 0 or int(flight["eta"]) <= 0 or int(flight["duration"]) < int(flight["eta"]) or int(flight["payment"]) < 0:
                return false
            var si: int = int(flight["ship_index"])
            if si < 0 or si >= data["ships"].size() or si in used_freighters:
                return false
            used_freighters.append(si)
            if str(data["ships"][si].get("type","")) != "freighter":
                return false
            if int(data["ships"][si].get("cargo_eta",0)) != int(flight["eta"]):
                return false
            if int(data["ships"][si].get("assigned_colony",-1)) >= 0 or int(data["ships"][si].get("eta",0)) > 0:
                return false
            if int(data.get("version",0)) >= 8:
                if not flight.has("escort_index"):
                    return false
                var escort_index: int = int(flight["escort_index"])
                if escort_index < -1 or escort_index >= data["ships"].size():
                    return false
                if escort_index >= 0:
                    if escort_index == si or escort_index in used_escorts:
                        return false
                    used_escorts.append(escort_index)
                    var escort: Dictionary = data["ships"][escort_index]
                    if str(escort.get("type","")) != "escort" or int(escort.get("health",0)) <= 0:
                        return false
                    if int(escort.get("eta",0)) != 0 or int(escort.get("assigned_colony",-1)) >= 0:
                        return false
                    if int(escort.get("cargo_eta",0)) != int(flight["eta"]):
                        return false
    if int(data.get("version",0)) >= 6:
        if typeof(data.get("pending_battle")) != TYPE_DICTIONARY:
            return false
        var saved_battle: Dictionary = data["pending_battle"]
        if not saved_battle.is_empty():
            for field in ["ship_index","destination","enemy_hp","enemy_max_hp","enemy_attack","enemy_defense","turn","scanned"]:
                if not saved_battle.has(field):
                    return false
            var battle_ship: int = int(saved_battle["ship_index"])
            var battle_destination: int = int(saved_battle["destination"])
            if battle_ship < 0 or battle_ship >= data["ships"].size():
                return false
            if battle_destination <= 0 or battle_destination >= Db.SYSTEMS.size():
                return false
            if int(saved_battle["enemy_max_hp"]) <= 0 or int(saved_battle["enemy_hp"]) <= 0 or int(saved_battle["enemy_hp"]) > int(saved_battle["enemy_max_hp"]):
                return false
            if int(saved_battle["enemy_attack"]) <= 0 or int(saved_battle["enemy_defense"]) < 0 or int(saved_battle["turn"]) <= 0:
                return false
            if int(data["ships"][battle_ship].get("target",-1)) != battle_destination or int(data["ships"][battle_ship].get("eta",-1)) != 0:
                return false
            if str(data["ships"][battle_ship].get("mission","")) != "patrol" or int(data["ships"][battle_ship].get("health",0)) <= 0:
                return false
    if int(data.get("version",0)) >= 7:
        if typeof(data.get("faction_fleets")) != TYPE_ARRAY:
            return false
        if data["faction_fleets"].size() > 4:
            return false
        for flight in data["faction_fleets"]:
            if typeof(flight) != TYPE_DICTIONARY:
                return false
            for field in ["source","destination","resource","amount","payment","eta","duration"]:
                if not flight.has(field):
                    return false
            var origin: String = str(flight["source"])
            var destination: String = str(flight["destination"])
            if origin == destination or not origin in ["Союз","Консорциум"] or not destination in ["Союз","Консорциум"]:
                return false
            if not str(flight["resource"]) in ["food","fuel"]:
                return false
            if int(flight["amount"]) < 1 or int(flight["amount"]) > 18 or int(flight["payment"]) < 0:
                return false
            if int(flight["eta"]) <= 0 or int(flight["duration"]) < int(flight["eta"]):
                return false
    for id in ["ore","alloy","polymer","food","water","fuel","science","credits"]:
        if not data["resources"].has(id):
            return false
    return true

func _read_snapshot(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path,FileAccess.READ)
    if file == null:
        return {}
    var data: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return data if _valid_snapshot(data) else {}

func save_game(slot: int = 0) -> String:
    if slot < 0 or slot > 3:
        return "Доступны слоты сохранения 0–3"
    var path := _save_path(slot)
    var tmp := path + ".tmp"
    var file := FileAccess.open(tmp,FileAccess.WRITE)
    if file == null:
        return "Не удалось создать временный файл сохранения"
    file.store_string(JSON.stringify(snapshot()))
    file.flush()
    file.close()
    if _read_snapshot(tmp).is_empty():
        return "Не удалось проверить записанное сохранение"
    var old := _read_snapshot(path)
    if not old.is_empty():
        var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak"))
        if copy_error != OK:
            return "Не удалось создать резервную копию"
    var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),ProjectSettings.globalize_path(path))
    if rename_error != OK:
        return "Не удалось завершить сохранение"
    return ""

func load_game(slot: int = 0) -> String:
    if slot < 0 or slot > 3:
        return "Доступны слоты сохранения 0–3"
    var path := _save_path(slot)
    var data := _read_snapshot(path)
    var restored_from_backup := false
    if data.is_empty():
        data = _read_snapshot(path+".bak")
        restored_from_backup = not data.is_empty()
    if data.is_empty():
        return "Сохранение отсутствует или повреждено (включая резервную копию)"
    cycle = maxi(1,int(data.get("cycle",1)))
    world_seed = int(data.get("world_seed",148833))
    colonies = data.get("colonies",[_make_colony(0,"Форпост «Терра»",true)])
    if typeof(colonies) != TYPE_ARRAY or colonies.is_empty():
        colonies = [_make_colony(0,"Форпост «Терра»",true)]
    faction_standing = data.get("faction_standing",{"Союз":20,"Консорциум":0,"Рой":-45})
    faction_economy = data.get("faction_economy",_default_faction_economy())
    trade_flights = data.get("trade_flights",[])
    for flight in trade_flights:
        if not flight.has("escort_index"):
            flight["escort_index"] = -1
    faction_fleets = data.get("faction_fleets",[])
    pirate_threat = clampi(int(data.get("pirate_threat",18)),0,100)
    patrol_cover = data.get("patrol_cover",{})
    pending_battle = data.get("pending_battle",{})
    contract_ready = data.get("contract_ready",[1,1,1])
    contracts_completed = int(data.get("contracts_completed",0))
    campaign_stage = int(data.get("campaign_stage",0))
    pending_story = str(data.get("pending_story",""))
    resolved_stories = data.get("resolved_stories",[])
    story_history = data.get("story_history",[])
    ship_serial = int(data.get("ship_serial",2))
    resources = data["resources"]
    for id in Db.RESOURCE_LABELS.keys():
        if not resources.has(id):
            resources[id] = 0
    sectors = data["sectors"]
    ships = data["ships"]
    mine = data["mine"]
    mine_queue = data.get("mine_queue",[])
    miners = data.get("miners",[
        {"name":"Шахтёр-01","x":3,"y":3,"target_x":-1,"target_y":-1,"eta":0,"total_eta":0},
        {"name":"Шахтёр-02","x":3,"y":3,"target_x":-1,"target_y":-1,"eta":0,"total_eta":0}])
    mine_stockpile = data.get("mine_stockpile",{"ore":0,"silicon":0,"copper":0,"ice":0})
    shuttle = data.get("shuttle",{"eta":0,"cargo":{}})
    cargo_priority = str(data.get("cargo_priority","ore"))
    researched = data["researched"]
    discovered = []
    for number in data["discovered"]:
        discovered.append(int(number))
    current_system = int(data.get("current_system",0))
    trust = float(data.get("trust",80.0))
    hull = float(data.get("hull",88.0))
    crew = int(data.get("crew",110))
    event_log = data.get("event_log",[])
    victory = bool(data.get("victory",false))
    defeated = bool(data.get("defeated",false))
    if data.has("rng_state"):
        rng.state = int(data["rng_state"])
    for sector in sectors:
        for building in sector["buildings"]:
            if not building.has("level"):
                building["level"] = 1
    for ship in ships:
        if not ship.has("type"):
            ship["type"] = "scout"
        if not ship.has("mission"):
            ship["mission"] = "explore"
        if not ship.has("assigned_colony"):
            ship["assigned_colony"] = -1
        if not ship.has("cargo_eta"):
            ship["cargo_eta"] = 0
    for colony in colonies:
        if not colony["convoy"].has("ship_ids"):
            colony["convoy"]["ship_ids"] = []
        if not colony.has("hauls"):
            colony["hauls"] = []
    if restored_from_backup:
        log_message("Основное сохранение повреждено. Восстановлена резервная копия")
    return ""

# Story choice uses real costs, rewards and permanent consequences.
func story_event() -> Dictionary:
    for event in Db.STORY_EVENTS:
        if str(event["id"]) == pending_story:
            return event
    return {}

func _advance_story() -> void:
    if not pending_story.is_empty():
        return
    for event in Db.STORY_EVENTS:
        if cycle >= int(event["cycle"]) and not str(event["id"]) in resolved_stories:
            pending_story = str(event["id"])
            log_message("СРОЧНОЕ РЕШЕНИЕ: %s" % event["title"])
            return

func resolve_story(choice_index: int) -> String:
    var event := story_event()
    if event.is_empty() or choice_index < 0 or choice_index >= event["options"].size():
        return "Нет такого сюжетного решения"
    var option: Dictionary = event["options"][choice_index]
    if not spend(option.get("cost",{})):
        return "Недостаточно ресурсов для выбранного решения"
    earn(option.get("reward",{}))
    crew = maxi(0,crew+int(option.get("crew",0)))
    trust = clampf(trust+float(option.get("trust",0)),0.0,100.0)
    hull = clampf(hull+float(option.get("hull",0)),0.0,100.0)
    var faction: String = str(option.get("faction",""))
    if not faction.is_empty():
        change_faction_standing(faction,int(option.get("relation",0)))
    resolved_stories.append(pending_story)
    story_history.append({"id":pending_story,"choice":choice_index,"cycle":cycle})
    log_message("Выбор: %s — %s" % [event["title"],option["text"]])
    pending_story = ""
    return ""

# --- Planetary colonies / road-dependent industry ---
func _make_colony(system_index: int, colony_name: String, starter: bool = false) -> Dictionary:
    var buildings: Array = [
        {"id":"landing","x":1,"y":3,"level":1},
        {"id":"road","x":2,"y":3,"level":1},
        {"id":"road","x":3,"y":3,"level":1},
        {"id":"quarry","x":4,"y":3,"level":1},
        {"id":"habitat","x":1,"y":4,"level":1}
    ]
    if not starter:
        var mineral: String = str(Db.SYSTEMS[system_index]["ore"])
        var native_building: String = str({"ice":"ice_drill","silicon":"silicon_pit","copper":"copper_pit"}.get(mineral,"quarry"))
        buildings[3]["id"] = native_building
    if starter:
        buildings.append({"id":"ice_drill","x":3,"y":2,"level":1})
        buildings.append({"id":"depot","x":2,"y":4,"level":1})
    return {"name":colony_name,"system":system_index,"population":34 if starter else 24,
            "buildings":buildings,"stock":{"ore":8,"ice":18,"food":36,"water":36,"silicon":5},
            "priority":"ore","convoy":{"eta":0,"cargo":{},"ship_ids":[]},"hauls":[],"morale":90.0}

func colony_storage(colony_index: int) -> int:
    var capacity := 130
    if colony_index < 0 or colony_index >= colonies.size():
        return capacity
    for building in colonies[colony_index]["buildings"]:
        if building["id"] == "depot":
            capacity += 160*int(building.get("level",1))
    return capacity

func colony_stored(colony_index: int) -> int:
    if colony_index < 0 or colony_index >= colonies.size():
        return 0
    var total := 0
    for units in colonies[colony_index]["stock"].values():
        total += int(units)
    return total

func colony_occupied(colony_index: int, x: int, y: int) -> bool:
    if colony_index < 0 or colony_index >= colonies.size():
        return true
    for building in colonies[colony_index]["buildings"]:
        if int(building["x"]) == x and int(building["y"]) == y:
            return true
    return false

func colony_connected(colony_index: int, x: int, y: int) -> bool:
    if colony_index < 0 or colony_index >= colonies.size():
        return false
    var buildings: Array = colonies[colony_index]["buildings"]
    var roads: Dictionary = {}
    var queue: Array = []
    for building in buildings:
        if building["id"] == "road":
            roads["%d:%d" % [int(building["x"]),int(building["y"])]] = true
        elif building["id"] == "landing":
            queue.append([int(building["x"]),int(building["y"])])
    var visited: Dictionary = {}
    while not queue.is_empty():
        var point: Array = queue.pop_front()
        var px := int(point[0])
        var py := int(point[1])
        var key := "%d:%d" % [px,py]
        if visited.has(key):
            continue
        visited[key] = true
        if abs(px-x)+abs(py-y) <= 1:
            return true
        for offset in [[1,0],[-1,0],[0,1],[0,-1]]:
            var xx := px+int(offset[0])
            var yy := py+int(offset[1])
            if roads.has("%d:%d" % [xx,yy]) and not visited.has("%d:%d" % [xx,yy]):
                queue.append([xx,yy])
    return false

func colony_build(colony_index: int, building_id: String, x: int, y: int) -> String:
    if colony_index < 0 or colony_index >= colonies.size():
        return "Колония не найдена"
    if not Db.COLONY_BUILDINGS.has(building_id):
        return "Неизвестная постройка"
    if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H or colony_occupied(colony_index,x,y):
        return "Клетка занята или недоступна"
    if not colony_connected(colony_index,x,y):
        return "Постройте дорожное соединение с посадочным терминалом"
    if building_id == "landing":
        return "Посадочный терминал уже существует"
    var spec: Dictionary = Db.COLONY_BUILDINGS[building_id]
    if not spend(spec["cost"]):
        return "Не хватает ресурсов станции"
    colonies[colony_index]["buildings"].append({"id":building_id,"x":x,"y":y,"level":1})
    log_message("%s: построено %s" % [colonies[colony_index]["name"],spec["name"]])
    return ""

func colony_upgrade(colony_index: int, x: int, y: int) -> String:
    if colony_index < 0 or colony_index >= colonies.size():
        return "Колония не найдена"
    for building in colonies[colony_index]["buildings"]:
        if int(building["x"]) != x or int(building["y"]) != y:
            continue
        if building["id"] == "road" or building["id"] == "landing":
            return "Этот объект нельзя улучшать"
        var level := int(building.get("level",1))
        if level >= 10:
            return "Достигнут уровень 10"
        if not spend({"alloy":4+level*4,"polymer":2+level*2}):
            return "Недостаточно ресурсов для улучшения"
        building["level"] = level+1
        log_message("%s: улучшение до уровня %d" % [colonies[colony_index]["name"],level+1])
        return ""
    return "Постройка не найдена"

func colony_assign_priority(colony_index: int, resource_id: String) -> String:
    if colony_index < 0 or colony_index >= colonies.size() or not Db.RESOURCE_LABELS.has(resource_id):
        return "Неизвестный товар или колония"
    colonies[colony_index]["priority"] = resource_id
    return ""

func found_colony(system_index: int) -> String:
    if system_index <= 0 or system_index >= Db.SYSTEMS.size() or not system_index in discovered:
        return "Сначала исследуйте выбранную систему"
    if Db.SYSTEMS[system_index]["kind"] == "hazard":
        return "Зона непригодна для колонизации"
    for colony in colonies:
        if int(colony["system"]) == system_index:
            return "Колония уже существует"
    if not spend({"credits":280,"alloy":38,"polymer":15,"components":3}):
        return "Для основания нужны кредиты, сплавы, полимеры и компоненты"
    colonies.append(_make_colony(system_index,"Форпост «%s»" % Db.SYSTEMS[system_index]["name"]))
    log_message("Основана колония в системе %s" % Db.SYSTEMS[system_index]["name"])
    return ""

# Local supply is not instantly shared: products travel along the colony road grid.
# Each depot supports a separate delivery vehicle. A delivery reserves warehouse space
# before leaving its factory, so a full warehouse cannot be bypassed by queued cargo.
func colony_haul_capacity(colony_index: int) -> int:
    if colony_index < 0 or colony_index >= colonies.size():
        return 0
    var count := 1
    for building in colonies[colony_index]["buildings"]:
        if building["id"] == "depot":
            count += int(building.get("level",1))
    if "cargo_drones" in researched:
        count += 1
    return count

func colony_haul_reserved(colony_index: int) -> int:
    if colony_index < 0 or colony_index >= colonies.size():
        return 0
    var reserved := 0
    for job in colonies[colony_index].get("hauls",[]):
        for amount in job["cargo"].values():
            reserved += int(amount)
    return reserved

# Returns a shortest route: factory -> contiguous road tiles -> landing pad.
# Production is stopped if the road path is disconnected.
func colony_haul_path(colony_index: int, from_x: int, from_y: int) -> Array:
    if colony_index < 0 or colony_index >= colonies.size():
        return []
    var colony: Dictionary = colonies[colony_index]
    var roads: Dictionary = {}
    var landing: Array = []
    for building in colony["buildings"]:
        var bx := int(building["x"])
        var by := int(building["y"])
        if building["id"] == "road":
            roads["%d:%d" % [bx,by]] = true
        elif building["id"] == "landing":
            landing = [bx,by]
    if landing.is_empty():
        return []
    var origin: Array = [from_x,from_y]
    var target_key := "%d:%d" % [int(landing[0]),int(landing[1])]
    var first_key := "%d:%d" % [from_x,from_y]
    var frontier: Array = [origin]
    var parents: Dictionary = {first_key:[]}
    var cursor := 0
    while cursor < frontier.size():
        var current: Array = frontier[cursor]
        cursor += 1
        var cx := int(current[0])
        var cy := int(current[1])
        var key := "%d:%d" % [cx,cy]
        if key == target_key:
            var route: Array = [current]
            while key != first_key:
                current = parents[key]
                route.append(current)
                key = "%d:%d" % [int(current[0]),int(current[1])]
            route.reverse()
            return route
        for direction in [[1,0],[-1,0],[0,1],[0,-1]]:
            var nx := cx + int(direction[0])
            var ny := cy + int(direction[1])
            if nx < 0 or ny < 0 or nx >= GRID_W or ny >= GRID_H:
                continue
            var neighbor_key := "%d:%d" % [nx,ny]
            if parents.has(neighbor_key):
                continue
            if not roads.has(neighbor_key) and neighbor_key != target_key:
                continue
            parents[neighbor_key] = [cx,cy]
            frontier.append([nx,ny])
    return []

func _advance_colony_hauls(colony_index: int) -> void:
    var colony: Dictionary = colonies[colony_index]
    var jobs: Array = colony["hauls"]
    for i in range(jobs.size()-1,-1,-1):
        var job: Dictionary = jobs[i]
        job["eta"] = maxi(0,int(job["eta"])-1)
        if int(job["eta"]) > 0:
            continue
        for resource in job["cargo"].keys():
            colony["stock"][resource] = int(colony["stock"].get(resource,0))+int(job["cargo"][resource])
        jobs.remove_at(i)

func _advance_colonies() -> void:
    for index in range(colonies.size()):
        var colony: Dictionary = colonies[index]
        var stock: Dictionary = colony["stock"]
        _advance_colony_hauls(index)
        var workers_left := int(colony["population"])
        var active_storage: int = colony_storage(index)
        var used_storage: int = colony_stored(index) + colony_haul_reserved(index)
        for building in colony["buildings"]:
            var id: String = str(building["id"])
            if id in ["road","landing","habitat","depot"]:
                continue
            if colony["hauls"].size() >= colony_haul_capacity(index):
                break
            var x := int(building["x"])
            var y := int(building["y"])
            var path := colony_haul_path(index,x,y)
            if path.size() < 2:
                continue
            var spec: Dictionary = Db.COLONY_BUILDINGS[id]
            var workers: int = int(spec["workers"])
            if workers_left < workers:
                continue
            var consume: Dictionary = spec["consume"]
            var produce: Dictionary = spec["produce"]
            var level: int = int(building.get("level",1))
            var possible := true
            for res in consume.keys():
                if int(stock.get(res,0)) < int(consume[res]):
                    possible = false
                    break
            var output: Dictionary = {}
            var produced_units := 0
            for res in produce.keys():
                var quantity: int = int(produce[res]) + level-1
                if id in ["quarry","ice_drill","silicon_pit","copper_pit"] and "orbital_mining" in researched:
                    quantity += 1
                if id == "foundry" and "alloy_forging" in researched:
                    quantity += 1
                if "industrial_ai" in researched:
                    quantity += 1
                output[res] = quantity
                produced_units += quantity
            var consumed_units := 0
            for res in consume.keys():
                consumed_units += int(consume[res])
            if used_storage + produced_units - consumed_units > active_storage:
                possible = false
            if not possible:
                continue
            workers_left -= workers
            for res in consume.keys():
                stock[res] = int(stock.get(res,0))-int(consume[res])
            var travel_steps := path.size()-1
            var haul_speed := 2 if "logistic_ai" in researched else 1
            var travel_cycles := maxi(2,1+ceili(float(travel_steps)/float(haul_speed)))
            colony["hauls"].append({"x":x,"y":y,"cargo":output,"path":path,
                                   "eta":travel_cycles,"total_eta":travel_cycles})
            used_storage = colony_stored(index) + colony_haul_reserved(index)
        var food_needed := maxi(1,ceili(float(colony["population"])/40.0))
        var water_needed := food_needed
        if int(stock.get("food",0)) >= food_needed and int(stock.get("water",0)) >= water_needed:
            stock["food"] = int(stock["food"])-food_needed
            stock["water"] = int(stock["water"])-water_needed
            colony["morale"] = minf(100.0,float(colony["morale"])+0.1)
        else:
            colony["morale"] = maxf(0.0,float(colony["morale"])-2.2)
            if cycle % 4 == 0 and int(colony["population"]) > 8:
                colony["population"] = int(colony["population"])-1
        _advance_convoy(index)

func _advance_convoy(colony_index: int) -> void:
    var colony: Dictionary = colonies[colony_index]
    var convoy: Dictionary = colony["convoy"]
    if int(convoy["eta"]) > 0:
        convoy["eta"] = int(convoy["eta"])-1
        for ship_index in convoy.get("ship_ids",[]):
            if int(ship_index) >= 0 and int(ship_index) < ships.size():
                ships[int(ship_index)]["cargo_eta"] = int(convoy["eta"])
        if int(convoy["eta"]) == 0:
            var delivered: Dictionary = convoy["cargo"]
            earn(delivered)
            convoy["cargo"] = {}
            convoy["ship_ids"] = []
            log_message("%s: доставлено %d грузовых единиц" % [colony["name"],_cargo_amount(delivered)])
        return
    # A ship only transports goods for its assigned colony, never for all colonies.
    # The default contracted shuttle can still carry a small cargo if all freighters are busy.
    var capacity := 6 + (4 if "logistic_ai" in researched else 0)
    var freighters := 0
    var vessel_ids: Array = []
    for i in range(ships.size()):
        var ship: Dictionary = ships[i]
        if str(ship.get("type","scout")) == "freighter" and int(ship.get("health",0)) > 0 and int(ship.get("eta",0)) == 0 and int(ship.get("cargo_eta",0)) == 0 and int(ship.get("assigned_colony",-1)) == colony_index:
            freighters += 1
            vessel_ids.append(i)
            capacity += int(Db.SHIP_TYPES["freighter"]["cargo"])
    if freighters > 0 and not can_afford({"fuel":freighters}):
        capacity = 6 + (4 if "logistic_ai" in researched else 0)
        freighters = 0
        vessel_ids.clear()
    var priority: String = str(colony["priority"])
    var ids: Array = [priority]
    for res in colony["stock"].keys():
        if res != priority:
            ids.append(res)
    var cargo: Dictionary = {}
    for res in ids:
        if capacity <= 0:
            break
        var reserve := 12 if res in ["food","water"] else 0
        var units := mini(capacity,maxi(0,int(colony["stock"].get(res,0))-reserve))
        if units > 0:
            colony["stock"][res] = int(colony["stock"][res])-units
            cargo[res] = units
            capacity -= units
    if not cargo.is_empty():
        if freighters > 0:
            spend({"fuel":freighters})
        convoy["cargo"] = cargo
        convoy["eta"] = maxi(2,int(4 - (1 if "cargo_drones" in researched else 0) - (1 if freighters > 0 else 0) + int(Db.SYSTEMS[int(colony["system"])]["risk"])/2))
        convoy["ship_ids"] = vessel_ids
        for ship_index in vessel_ids:
            ships[int(ship_index)]["cargo_eta"] = int(convoy["eta"])

# --- Living factions and delayed, ship-bound interstellar contracts ---
func _default_faction_economy() -> Dictionary:
    var result: Dictionary = {}
    for faction in Db.FACTION_IDS:
        var profile: Dictionary = Db.FACTION_TRADE[faction]
        result[faction] = {"stock":profile["stock"].duplicate(true),"treasury":int(profile["treasury"])}
    return result

func _advance_faction_economy() -> void:
    for faction in Db.FACTION_IDS:
        if faction == "Рой":
            continue
        var economy: Dictionary = faction_economy[faction]
        var stock: Dictionary = economy["stock"]
        var profile: Dictionary = Db.FACTION_TRADE[faction]
        for resource_id in profile["production"].keys():
            stock[resource_id] = mini(300,int(stock.get(resource_id,0))+int(profile["production"][resource_id]))
        for resource_id in profile["consumption"].keys():
            stock[resource_id] = maxi(0,int(stock.get(resource_id,0))-int(profile["consumption"][resource_id]))
        economy["treasury"] = mini(10000,int(economy["treasury"])+45)

func faction_price(faction: String, resource_id: String, buying: bool) -> int:
    if not Db.FACTION_TRADE.has(faction) or not resource_id in Db.FACTION_TRADE[faction]["goods"]:
        return 0
    var base: int = int(Db.MARKETS.get(resource_id,0))
    var reserve: int = int(faction_economy[faction]["stock"].get(resource_id,0))
    var shortage: int = 5 if reserve < 20 else (-3 if reserve > 80 else 0)
    var relation: int = int(faction_standing.get(faction,0))
    var premium: int = 4 if buying else -4
    var discount: int = -3 if relation >= 40 and buying else 0
    return maxi(1,base+shortage+premium+discount)

func _free_trade_ship() -> int:
    for i in range(ships.size()):
        var ship: Dictionary = ships[i]
        if str(ship.get("type","")) == "freighter" and int(ship.get("health",0)) > 0 and int(ship.get("eta",0)) == 0 and int(ship.get("cargo_eta",0)) == 0 and int(ship.get("assigned_colony",-1)) < 0:
            return i
    return -1

func faction_trade(faction: String, resource_id: String, amount: int, buying: bool) -> String:
    if not pending_battle.is_empty():
        return "Сначала завершите бой"
    if defeated or victory or not pending_story.is_empty():
        return "Сейчас нельзя оформлять сделку"
    if not faction in ["Союз","Консорциум"] or not resource_id in Db.FACTION_TRADE[faction]["goods"]:
        return "Эта фракция не торгует выбранным ресурсом"
    if int(faction_standing.get(faction,0)) < -35:
        return "Отношения слишком плохи для торговли"
    var destination: int = int(Db.FACTION_TRADE[faction]["system"])
    if not destination in discovered:
        return "Сначала разведайте торговую систему фракции"
    var ship_index := _free_trade_ship()
    if ship_index < 0:
        return "Нет свободного грузовоза: снимите его с маршрута колонии"
    var capacity: int = int(Db.SHIP_TYPES["freighter"]["cargo"])
    if amount <= 0 or amount > capacity:
        return "Объём превышает грузоподъёмность"
    var unit_price := faction_price(faction,resource_id,buying)
    var payment := unit_price * amount
    var fuel_cost := maxi(2,3+int(Db.SYSTEMS[destination]["risk"]))
    var economy: Dictionary = faction_economy[faction]
    var stock: Dictionary = economy["stock"]
    if buying:
        if int(stock.get(resource_id,0)) < amount:
            return "На рынке фракции недостаточно товара"
        if not can_afford({"credits":payment,"fuel":fuel_cost}):
            return "Недостаточно кредитов или топлива"
    else:
        if int(economy["treasury"]) < payment:
            return "У фракции пока недостаточно средств"
        var export_cost: Dictionary = {resource_id:amount}
        export_cost["fuel"] = int(export_cost.get("fuel",0))+fuel_cost
        if not can_afford(export_cost):
            return "Недостаточно товара или топлива"
    var ship: Dictionary = ships[ship_index]
    if buying:
        spend({"credits":payment,"fuel":fuel_cost})
        stock[resource_id] = int(stock[resource_id])-amount
        economy["treasury"] = int(economy["treasury"])+payment
    else:
        var export_cost: Dictionary = {resource_id:amount}
        export_cost["fuel"] = int(export_cost.get("fuel",0))+fuel_cost
        spend(export_cost)
        economy["treasury"] = int(economy["treasury"])-payment
    var eta := 3+int(Db.SYSTEMS[destination]["risk"])+(1 if pirate_threat >= 45 else 0)
    ship["cargo_eta"] = eta
    trade_flights.append({"faction":faction,"resource":resource_id,"amount":amount,
        "buy":buying,"payment":payment,"eta":eta,"duration":eta,
        "ship_index":ship_index,"escort_index":-1})
    log_message("Торговый рейс с %s: %s ×%d, ETA %d" % [faction,Db.label_for(resource_id),amount,eta])
    return ""

# Escort craft intercept threats on a specific trade route. Both ships are
# locked until arrival, and escort fuel is charged only for a valid dispatch.
func escort_trade_flight(ship_index: int, flight_index: int) -> String:
    if not pending_battle.is_empty() or not pending_story.is_empty() or defeated or victory:
        return "Сопровождение сейчас недоступно"
    if flight_index < 0 or flight_index >= trade_flights.size():
        return "Торговый рейс не найден"
    if ship_index < 0 or ship_index >= ships.size():
        return "Корабль не найден"
    var flight: Dictionary = trade_flights[flight_index]
    if int(flight.get("escort_index",-1)) >= 0:
        return "Рейс уже сопровождается"
    if int(flight["eta"]) <= 1:
        return "Слишком поздно: груз уже прибывает"
    var ship: Dictionary = ships[ship_index]
    if str(ship.get("type","")) != "escort":
        return "Для сопровождения нужен боевой корабль класса «Эскорт»"
    if int(ship.get("health",0)) <= 0 or int(ship.get("eta",0)) > 0 or int(ship.get("cargo_eta",0)) > 0 or int(ship.get("assigned_colony",-1)) >= 0:
        return "Эскорт занят или повреждён"
    if not spend({"fuel":3}):
        return "Для сопровождения нужно 3 топлива"
    flight["escort_index"] = ship_index
    ship["cargo_eta"] = int(flight["eta"])
    log_message("Эскорт %s направлен на защиту рейса с %s" % [ship["name"],flight["faction"]])
    return ""

# Pure calculation shared by simulation and regression tests.
func trade_raid_chance(flight: Dictionary) -> int:
    var risk: int = maxi(0,int(pirate_threat / 3))
    if cycle <= int(patrol_cover.get(str(flight["faction"]),0)):
        risk = maxi(0,risk - 15)
    if int(flight.get("escort_index",-1)) >= 0:
        risk = maxi(0,risk - 20)
    return risk

func _advance_faction_trade() -> void:
    for i in range(trade_flights.size()-1,-1,-1):
        var flight: Dictionary = trade_flights[i]
        flight["eta"] = maxi(0,int(flight["eta"])-1)
        var ship_index: int = int(flight["ship_index"])
        var ship: Dictionary = ships[ship_index]
        ship["cargo_eta"] = int(flight["eta"])
        var escort_index: int = int(flight.get("escort_index",-1))
        var escorted: bool = escort_index >= 0 and escort_index < ships.size()
        if escorted:
            ships[escort_index]["cargo_eta"] = int(flight["eta"])
        if int(flight["eta"]) > 0:
            continue
        var intercepted: bool = rng.randi_range(1,100) <= trade_raid_chance(flight)
        var resource_id: String = str(flight["resource"])
        var amount: int = int(flight["amount"])
        var faction: String = str(flight["faction"])
        if intercepted:
            if not bool(flight["buy"]):
                # The buyer's funds remain in escrow until successful delivery.
                faction_economy[faction]["treasury"] = int(faction_economy[faction]["treasury"])+int(flight["payment"])
            ship["health"] = maxi(1,int(ship["health"])-(5 if escorted else 15))
            if escorted:
                ships[escort_index]["health"] = maxi(1,int(ships[escort_index]["health"])-12)
            log_message("Перехвачен грузовой рейс %s! Потеряно %d %s" % [ship["name"],amount,Db.label_for(resource_id)])
        elif bool(flight["buy"]):
            earn({resource_id:amount})
            log_message("Торговля с %s: доставлено %d %s" % [faction,amount,Db.label_for(resource_id)])
        else:
            earn({"credits":int(flight["payment"])})
            var faction_stock: Dictionary = faction_economy[faction]["stock"]
            faction_stock[resource_id] = int(faction_stock.get(resource_id,0))+amount
            log_message("Торговля с %s: получено %d кредитов" % [faction,int(flight["payment"])])
        trade_flights.remove_at(i)


# NPC trade lanes are independent of the player's freighters and stock.
# Cargo and funds are reserved on departure and settled exactly once on arrival.
func _advance_faction_fleets() -> void:
    for i in range(faction_fleets.size()-1,-1,-1):
        var flight: Dictionary = faction_fleets[i]
        flight["eta"] = int(flight["eta"]) - 1
        if int(flight["eta"]) > 0:
            continue
        var source: String = str(flight["source"])
        var destination: String = str(flight["destination"])
        var resource_id: String = str(flight["resource"])
        var quantity: int = int(flight["amount"])
        var price: int = int(flight["payment"])
        var danger: int = clampi(int(pirate_threat/3),0,60)
        if cycle <= int(patrol_cover.get(source,0)) or cycle <= int(patrol_cover.get(destination,0)):
            danger = maxi(0,danger-15)
        if rng.randi_range(1,100) <= danger:
            # Buyer recovers escrow, while the seller loses the intercepted shipment.
            faction_economy[destination]["treasury"] = int(faction_economy[destination]["treasury"])+price
            pirate_threat = mini(100,pirate_threat+3)
            log_message("Пираты перехватили чужой конвой: %s → %s" % [source,destination])
        else:
            var destination_stock: Dictionary = faction_economy[destination]["stock"]
            destination_stock[resource_id] = int(destination_stock.get(resource_id,0))+quantity
            faction_economy[source]["treasury"] = int(faction_economy[source]["treasury"])+price
            log_message("Независимая торговля: %s → %s, %d %s" % [source,destination,quantity,Db.label_for(resource_id)])
        faction_fleets.remove_at(i)
    if cycle % 6 != 0 or faction_fleets.size() >= 4:
        return
    var source: String = "Союз" if int(cycle/6) % 2 == 1 else "Консорциум"
    var destination: String = "Консорциум" if source == "Союз" else "Союз"
    var resource_id: String = "food" if source == "Союз" else "fuel"
    var source_stock: Dictionary = faction_economy[source]["stock"]
    var amount: int = mini(18,int(source_stock.get(resource_id,0))-30)
    if amount < 8:
        return
    var price: int = amount * maxi(1,int(Db.MARKETS[resource_id]/3))
    if int(faction_economy[destination]["treasury"]) < price:
        return
    var route_time := 4 + (1 if pirate_threat >= 45 else 0)
    source_stock[resource_id] = int(source_stock[resource_id])-amount
    faction_economy[destination]["treasury"] = int(faction_economy[destination]["treasury"])-price
    faction_fleets.append({"source":source,"destination":destination,
        "resource":resource_id,"amount":amount,"payment":price,
        "eta":route_time,"duration":route_time})
    log_message("Фракция %s отправила конвой к %s: %d %s" % [source,destination,amount,Db.label_for(resource_id)])

# --- Fleet shipyard, repair, patrols and diplomacy ---
func build_ship(ship_type: String) -> String:
    if not Db.SHIP_TYPES.has(ship_type):
        return "Неизвестный класс корабля"
    if total_buildings("hangar") <= 0:
        return "Постройте ангар флота на станции"
    var active := 0
    for ship in ships:
        if int(ship["health"]) > 0:
            active += 1
    if active >= 12:
        return "Флот достиг лимита 12 действующих кораблей"
    var spec: Dictionary = Db.SHIP_TYPES[ship_type]
    if not spend(spec["cost"]):
        return "Недостаточно ресурсов для строительства корабля"
    ship_serial += 1
    ships.append({"name":"%s-%02d" % [spec["name"],ship_serial],"type":ship_type,
                  "target":-1,"eta":0,"health":100,"runs":0,"mission":"explore","assigned_colony":-1,"cargo_eta":0})
    log_message("Верфь выпустила корабль класса %s" % spec["name"])
    return ""

func assign_freighter(ship_index: int, colony_index: int) -> String:
    if not pending_battle.is_empty():
        return "Сначала завершите бой"
    if ship_index < 0 or ship_index >= ships.size():
        return "Корабль не найден"
    var ship: Dictionary = ships[ship_index]
    if str(ship.get("type","")) != "freighter":
        return "Для грузовых линий нужен корабль класса «Грузовоз»"
    if int(ship.get("health",0)) <= 0 or int(ship.get("eta",0)) > 0 or int(ship.get("cargo_eta",0)) > 0:
        return "Корабль выполняет рейс, находится в экспедиции или повреждён"
    if colony_index < -1 or colony_index >= colonies.size():
        return "Колония не существует"
    ship["assigned_colony"] = colony_index
    if colony_index < 0:
        log_message("%s освобождён от грузового маршрута" % ship["name"])
    else:
        log_message("%s закреплён за %s" % [ship["name"],colonies[colony_index]["name"]])
    return ""

func repair_ship(ship_index: int) -> String:
    if not pending_battle.is_empty():
        return "Ремонт недоступен во время боя"
    if ship_index < 0 or ship_index >= ships.size():
        return "Корабль не найден"
    var ship: Dictionary = ships[ship_index]
    if int(ship["eta"]) > 0 or int(ship.get("cargo_eta",0)) > 0:
        return "Ремонт возможен только на базе"
    if int(ship["health"]) <= 0:
        return "Корабль уничтожен; восстановлению не подлежит"
    if int(ship["health"]) >= 100:
        return "Корпус уже цел"
    var alloy_cost := maxi(2,int(ceili((100.0-float(ship["health"]))/12.0)))
    if "fleet_repair" in researched:
        alloy_cost = maxi(1,int(alloy_cost/2))
    if not spend({"alloy":alloy_cost,"components":1}):
        return "Недостаточно сплавов и компонентов для ремонта"
    ship["health"] = 100
    log_message("Отремонтирован %s" % ship["name"])
    return ""

func send_patrol(ship_index: int, destination: int) -> String:
    if not pending_battle.is_empty():
        return "Сначала завершите бой"
    if ship_index < 0 or ship_index >= ships.size():
        return "Корабль не найден"
    if destination <= 0 or destination >= Db.SYSTEMS.size() or not destination in discovered:
        return "Боевой патруль возможен только в разведанных системах"
    var ship: Dictionary = ships[ship_index]
    if int(ship["eta"]) > 0 or int(ship.get("cargo_eta",0)) > 0 or int(ship["health"]) <= 0:
        return "Корабль недоступен"
    if int(ship.get("assigned_colony",-1)) >= 0:
        return "Корабль закреплён за колонией. Сначала снимите назначение"
    if not spend({"fuel":6}):
        return "Патруль требует 6 топлива"
    ship["target"] = destination
    ship["eta"] = 3+int(Db.SYSTEMS[destination]["risk"])
    ship["mission"] = "patrol"
    log_message("Боевой патруль %s вышел в систему %s" % [ship["name"],Db.SYSTEMS[destination]["name"]])
    return ""

func change_faction_standing(faction: String, change: int) -> void:
    if faction_standing.has(faction):
        faction_standing[faction] = clampi(int(faction_standing[faction])+change,-100,100)

func negotiate(faction: String) -> String:
    if not faction_standing.has(faction):
        return "Переговоры с этой фракцией невозможны"
    if faction == "Рой":
        return "Рой не отвечает на дипломатические сигналы"
    if int(faction_standing[faction]) >= 100:
        return "Отношения уже максимальны"
    if not spend({"credits":65,"food":5}):
        return "Необходимы 65 кредитов и 5 пищи"
    change_faction_standing(faction,12)
    trust = minf(100.0,trust+1.0)
    log_message("Дипломатическая миссия: отношения с %s улучшены" % faction)
    return ""

func campaign_progress() -> String:
    if campaign_stage >= Db.OBJECTIVES.size():
        return "Основная кампания завершена"
    return str(Db.OBJECTIVES[campaign_stage]["desc"])

func _advance_campaign() -> void:
    if campaign_stage == 0:
        var industrial := 0
        for colony in colonies:
            for building in colony["buildings"]:
                if building["id"] in ["quarry","ice_drill","greenhouse","foundry","assembler","fuel_lab","silicon_pit","copper_pit","purifier"]:
                    industrial += 1
        if industrial >= 3:
            campaign_stage = 1
            earn({"credits":150,"science":12})
            log_message("Глава I: промышленная база укреплена")
    elif campaign_stage == 1 and discovered.size() >= 4 and contracts_completed >= 3:
        campaign_stage = 2
        earn({"science":50})
        log_message("Глава II: торговые маршруты открыты")
    elif campaign_stage == 2 and researched.size() >= 10 and colonies.size() >= 2:
        campaign_stage = 3
        earn({"components":15,"science":60})
        log_message("Глава III: управление колониями стабилизировано")
