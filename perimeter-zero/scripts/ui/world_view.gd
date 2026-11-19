extends Control
## One touch-friendly canvas for the strategic layers; all artwork is original vector geometry.
signal grid_pressed(x: int, y: int)
signal star_pressed(index: int)

const Db = preload("res://scripts/sim/database.gd")
var game
var mode := "station"
var sector_index := 0
var colony_index := 0
var station_tool := "build"
var colony_tool := "build"
var tick_fraction := 0.0
var chosen_star := 0
var grid_origin := Vector2.ZERO
var grid_cell := 32.0
var title_color := Color("e7eff4")
var bg := Color("0b1524")
var accent := Color("55d9d0")
var muted := Color("71899d")

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size), bg)
    _starfield()
    match mode:
        "station": _draw_station()
        "mine": _draw_mine()
        "colony": _draw_colony()
        "galaxy": _draw_galaxy()
        "fleet": _draw_fleet()
        "battle": _draw_battle()
        "research": _draw_research()
        "market": _draw_market()
        "contracts": _draw_contracts()
        "diplomacy": _draw_diplomacy()
        "campaign": _draw_campaign()

func _font() -> Font:
    return ThemeDB.fallback_font

func _text(position: Vector2, message: String, fontsize: int = 20, color: Color = Color("e7eff4")) -> void:
    draw_string(_font(),position,message,HORIZONTAL_ALIGNMENT_LEFT,-1,fontsize,color)

func _starfield() -> void:
    for i in range(68):
        var x := fposmod(float(i*193+41),maxf(1.0,size.x))
        var y := fposmod(float(i*103+31),maxf(1.0,size.y))
        draw_circle(Vector2(x,y),0.8 if i % 4 else 1.4,Color(0.50,0.65,0.78,0.22))

func _caption(title: String, subtitle: String) -> void:
    _text(Vector2(44,45), title, 31)
    _text(Vector2(44,78), subtitle, 17,muted)
    draw_line(Vector2(44,94),Vector2(size.x-44,94),Color("264156"),1.0)

func _grid_metrics() -> void:
    grid_cell = minf((size.x - 110.0)/12.0,(size.y - 165.0)/8.0)
    grid_cell = maxf(grid_cell,12.0)
    grid_origin = Vector2((size.x-grid_cell*12.0)/2.0,118.0 + maxf(0.0,(size.y-150.0-grid_cell*8.0)/2.0))

func _draw_grid_base() -> void:
    _grid_metrics()
    var rect := Rect2(grid_origin-Vector2(17,17),Vector2(grid_cell*12+34,grid_cell*8+34))
    draw_rect(rect,Color("14283b"))
    draw_rect(rect,Color("416177"),false,2)
    for y in range(8):
        for x in range(12):
            var cell := Rect2(grid_origin+Vector2(x,y)*grid_cell+Vector2(2,2),Vector2(grid_cell-4,grid_cell-4))
            draw_rect(cell,Color("142334") if (x+y) % 2 == 0 else Color("17283b"))
            draw_rect(cell,Color("254054"),false,1.0)

func _draw_station() -> void:
    var sector: Dictionary = game.sectors[sector_index]
    _caption("СТАНЦИЯ / СЕКТОР %02d" % (sector_index+1),
        "Клетки 12 × 8 · Строить / улучшать / демонтировать · режим: %s" % station_tool)
    _draw_grid_base()
    if not sector["open"]:
        draw_rect(Rect2(grid_origin,Vector2(grid_cell*12,grid_cell*8)),Color(0.03,0.06,0.10,0.82))
        _text(grid_origin + Vector2(grid_cell*3.4,grid_cell*3.8),"СЕКТОР ЗАКРЫТ",30,Color("e8b875"))
        return
    for entry in sector["buildings"]:
        var id: String = entry["id"]
        var x := int(entry["x"])
        var y := int(entry["y"])
        var cell := Rect2(grid_origin+Vector2(x,y)*grid_cell+Vector2(5,5),Vector2(grid_cell-10,grid_cell-10))
        var shade := Color("2a6e77") if id == "reactor" or id == "recycler" else Color("365268")
        if id == "farm" or id == "habitat":
            shade = Color("376755")
        elif id == "smelter" or id == "workshop":
            shade = Color("776044")
        elif id == "laboratory":
            shade = Color("55588b")
        draw_rect(cell,shade)
        draw_rect(cell,Color("92c9d1"),false,1.3)
        var tag: String = Db.BUILDINGS[id]["tag"]
        _text(cell.position+Vector2(10,grid_cell*0.59),tag,clampi(int(grid_cell*0.31),14,26))
        if int(entry.get("level",1)) > 1:
            _text(cell.position+Vector2(grid_cell*0.56,grid_cell*0.30),str(entry["level"]),12,Color("f4d47b"))
    _text(grid_origin + Vector2(4,grid_cell*8+31),"Строения: %d   •   Энергия: %+d   •   Экипаж: %d" % [sector["buildings"].size(),game.power_balance(),game.crew],17,muted)

func _draw_mine() -> void:
    _caption("ШАХТА / АСТЕРОИДНЫЙ РАЗРЕЗ", "Рудные пласты сохраняют структуру. Повторная добыча идёт автоматически")
    _draw_grid_base()
    for y in range(8):
        for x in range(12):
            var tile: Dictionary = game.mine[y][x]
            var rect := Rect2(grid_origin+Vector2(x,y)*grid_cell+Vector2(3,3),Vector2(grid_cell-6,grid_cell-6))
            if not tile["visible"]:
                draw_rect(rect,Color("070c14"))
                draw_rect(rect,Color("1b2a37"),false,1)
                continue
            if int(tile["amount"]) <= 0:
                draw_rect(rect,Color("16232a"))
                continue
            var col: Color = Db.RESOURCE_COLORS[tile["kind"]]
            draw_rect(rect,col.darkened(0.62))
            draw_rect(rect,col.darkened(0.2),false,2.0)
            _text(rect.position+Vector2(10,grid_cell*0.54),str(tile["amount"]),clampi(int(grid_cell*0.28),13,21),col.lightened(0.25))
    for worker in game.miners:
        var wx := float(worker["x"])
        var wy := float(worker["y"])
        if int(worker["eta"]) > 0:
            var tx := float(worker["target_x"])
            var ty := float(worker["target_y"])
            var duration := maxf(1.0,float(worker.get("total_eta",worker["eta"])))
            var progress := clampf((duration-float(worker["eta"])+tick_fraction)/duration,0.0,1.0)
            draw_line(grid_origin+Vector2(wx+0.5,wy+0.5)*grid_cell,grid_origin+Vector2(tx+0.5,ty+0.5)*grid_cell,Color("53978c",0.65),2)
            wx = lerpf(wx,tx,progress)
            wy = lerpf(wy,ty,progress)
        var pos := grid_origin+Vector2(wx+0.5,wy+0.5)*grid_cell
        draw_circle(pos,minf(9.0,grid_cell*0.17),Color("eac580"))
        draw_circle(pos,minf(4.0,grid_cell*0.09),Color("fff4cf"))
    _text(grid_origin+Vector2(4,grid_cell*8+31),"Автопласт: %d    •    Склад: %d    •    Грузовой рейс: %d циклов" % [game.mine_queue.size(),game.total_mine_storage(),game.shuttle["eta"]],17,muted)

func _star_position(index: int) -> Vector2:
    var star: Dictionary = Db.SYSTEMS[index]
    return Vector2(70+float(star["x"])*(size.x-140),120+float(star["y"])*(size.y-230))

func _draw_galaxy() -> void:
    _caption("ГАЛАКТИКА / РУКАВ ТАЛИЯ", "Коснитесь звезды, выберите корабль и отправьте экспедицию")
    for route in Db.LINKS:
        var p1 := _star_position(int(route[0]))
        var p2 := _star_position(int(route[1]))
        draw_line(p1,p2,Color("2d5262"),2.0,true)
    for i in range(Db.SYSTEMS.size()):
        var s: Dictionary = Db.SYSTEMS[i]
        var pos := _star_position(i)
        var discovered := i in game.discovered
        var star_color := Color("71d8e2") if discovered else Color("c18b61")
        if i == 4:
            star_color = Color("b3a2ed")
        draw_circle(pos,25 if i==chosen_star else 19,star_color.darkened(0.65))
        draw_arc(pos,27 if i==chosen_star else 21,0,TAU,40,star_color,2.5)
        draw_circle(pos,10,star_color)
        _text(pos+Vector2(-18,47),s["name"],18,title_color)
        _text(pos+Vector2(-16,69),"ИССЛЕДОВАНО" if discovered else "НЕИЗВЕСТНО",13,muted)
    for flight in game.trade_flights:
        var faction_name: String = str(flight["faction"])
        var destination_id: int = int(Db.FACTION_TRADE[faction_name]["system"])
        var destination_point := _star_position(destination_id)
        var origin_point := _star_position(0)
        var ship_ref: Dictionary = game.ships[int(flight["ship_index"])]
        var transit: float = clampf(1.0-float(flight["eta"])/maxf(1.0,float(flight["duration"])),0.0,1.0)
        var position := origin_point.lerp(destination_point,transit)
        draw_line(origin_point,destination_point,Color("529c8e").with_alpha(0.7),2.0,true)
        draw_circle(position,8.0,Color("e7c68f"))
        if int(flight.get("escort_index",-1)) >= 0:
            draw_arc(position,14.0,0.0,TAU,24,Color("62d8d0"),2.5)
        _text(position+Vector2(17,-7),"%s · %d" % [ship_ref["name"],int(flight["eta"])],13,Color("e7c68f"))
    # Rival factions operate their own convoys independent of player missions.
    for npc_flight in game.faction_fleets:
        var first: int = int(Db.FACTION_TRADE[str(npc_flight["source"])]["system"])
        var second: int = int(Db.FACTION_TRADE[str(npc_flight["destination"])]["system"])
        var from_point := _star_position(first)
        var to_point := _star_position(second)
        var fraction: float = clampf(1.0-float(npc_flight["eta"])/float(npc_flight["duration"]),0.0,1.0)
        var vehicle_point := from_point.lerp(to_point,fraction)
        draw_line(from_point,to_point,Color("bd96e8",0.55),1.5,true)
        draw_circle(vehicle_point,7.0,Color("cda9fc"))
        _text(vehicle_point+Vector2(9,-9),"НПС · %d" % int(npc_flight["eta"]),13,Color("dac5f0"))
    for ship in game.ships:
        if int(ship["eta"]) > 0:
            var destination := _star_position(int(ship["target"]))
            _text(destination+Vector2(10,-34),"✦",29,Color("f4d688"))
    _text(Vector2(56,size.y-36),"8 систем • 13 маршрутов • Перелёты требуют топлива",19,muted)

func _draw_research() -> void:
    _caption("ИССЛЕДОВАНИЯ / ТЕХНОЛОГИЧЕСКОЕ ДРЕВО", "18 технологий · Зависимости и эффекты доступны в панели справа")
    var columns := 3
    var rows: int = int(ceili(float(Db.TECHS.size())/float(columns)))
    var cw := (size.x-110)/float(columns)
    var ch := (size.y-165)/float(rows)
    for i in range(Db.TECHS.size()):
        var tech: Dictionary = Db.TECHS[i]
        var r := Rect2(Vector2(42+(i%columns)*cw,112+int(i/columns)*ch),Vector2(cw-12,ch-7))
        var done := tech["id"] in game.researched
        var available := true
        for parent in tech["requires"]:
            if not parent in game.researched:
                available = false
        draw_rect(r,Color("164148") if done else (Color("233647") if available else Color("172638")))
        draw_rect(r,Color("70ddce") if done else Color("39596a"),false,1.6)
        _text(r.position+Vector2(10,23),"%02d  %s" % [i+1,tech["name"]],clampi(int(ch*0.24),13,19))
        _text(r.position+Vector2(10,45),"ИЗУЧЕНО" if done else ("%d науки" % tech["cost"] if available else "НЕ ДОСТУПНО"),14,Color("76dacc") if done else muted)

func _draw_market() -> void:
    _caption("РЫНОК / ТОРГОВЫЙ ХАБ", "Цены динамические: цикл %d · сделка моментальная" % game.cycle)
    var x := 80.0
    var y := 140.0
    for id in Db.MARKETS.keys():
        var market_y := y
        var price := game.market_price(id)
        var held := int(game.resources.get(id,0))
        var bar_width := minf(420.0,float(held)*4)
        _text(Vector2(x,market_y+11),"%s   %d кр/ед   •   запас %d" % [Db.label_for(id),price,held],20)
        draw_rect(Rect2(Vector2(x+460,market_y-13),Vector2(450,16)),Color("24394c"))
        draw_rect(Rect2(Vector2(x+460,market_y-13),Vector2(bar_width,16)),Db.RESOURCE_COLORS[id])
        y += 55

func _draw_contracts() -> void:
    _caption("КОНТРАКТЫ / СВОБОДНЫЕ КОЛОНИИ", "Помощь колониям влияет на торговлю и доверие жителей")
    for i in range(Db.CONTRACTS.size()):
        var deal: Dictionary = Db.CONTRACTS[i]
        var y := 137+i*155
        draw_rect(Rect2(Vector2(65,y-24),Vector2(size.x-128,132)),Color("182c3d"))
        draw_rect(Rect2(Vector2(65,y-24),Vector2(size.x-128,132)),Color("385667"),false,1.5)
        _text(Vector2(91,y+13),"КОНТРАКТ %02d  /  %s" % [i+1,deal["name"]],24)
        _text(Vector2(91,y+53),"Требуется: %d × %s" % [deal["amount"],Db.label_for(deal["resource"])],20,muted)
        _text(Vector2(91,y+83),"Награда: %d кредитов, +%d доверия" % [deal["reward"],deal["trust"]],19,Color("71ddcf"))

func _gui_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
        return
    var point: Vector2 = event.position
    if mode == "galaxy":
        for i in range(Db.SYSTEMS.size()):
            if point.distance_to(_star_position(i)) <= 67:
                star_pressed.emit(i)
                accept_event()
                return
    elif mode == "station" or mode == "mine" or mode == "colony":
        _grid_metrics()
        var gx := int(floor((point.x-grid_origin.x)/grid_cell))
        var gy := int(floor((point.y-grid_origin.y)/grid_cell))
        if gx >= 0 and gx < 12 and gy >= 0 and gy < 8:
            grid_pressed.emit(gx,gy)
            accept_event()


func _draw_colony() -> void:
    if game.colonies.is_empty():
        _caption("КОЛОНИАЛЬНАЯ ПРОМЫШЛЕННОСТЬ", "Нет основанных колоний")
        return
    var colony: Dictionary = game.colonies[colony_index]
    _caption("КОЛОНИЯ / %s" % colony["name"],"Сеть дорог соединяет заводы с терминалом · режим: %s" % colony_tool)
    _draw_grid_base()
    for y in range(8):
        for x in range(12):
            var cell := Rect2(grid_origin+Vector2(x,y)*grid_cell+Vector2(3,3),Vector2(grid_cell-6,grid_cell-6))
            var tint := Color("1c2a2a") if (x+y)%3 == 0 else Color("21313a")
            draw_rect(cell,tint)
            draw_circle(cell.get_center(),minf(grid_cell*0.085,4.5),Color("3e5758",0.55))
    for entry in colony["buildings"]:
        var id: String = str(entry["id"])
        var x := int(entry["x"])
        var y := int(entry["y"])
        var rect := Rect2(grid_origin+Vector2(x,y)*grid_cell+Vector2(4,4),Vector2(grid_cell-8,grid_cell-8))
        if id == "road":
            draw_rect(Rect2(rect.position+Vector2(0,grid_cell*0.34),Vector2(grid_cell-8,grid_cell*0.2)),Color("84949d"))
            draw_line(rect.position+Vector2(5,grid_cell*0.44),rect.position+Vector2(grid_cell-13,grid_cell*0.44),Color("e6bf6d"),1)
            continue
        var connected := game.colony_connected(colony_index,x,y)
        var tint := Color("277879") if connected else Color("703d47")
        if id in ["quarry","ice_drill","silicon_pit","copper_pit"]:
            tint = Color("7c6b52") if connected else Color("703d47")
        if id in ["greenhouse","habitat"]:
            tint = Color("35694f") if connected else Color("703d47")
        draw_rect(rect,tint)
        draw_rect(rect,Color("97c8cb") if connected else Color("e58a87"),false,1.5)
        _text(rect.position+Vector2(8,grid_cell*0.54),Db.COLONY_BUILDINGS[id]["tag"],clampi(int(grid_cell*0.28),13,24))
        if int(entry.get("level",1)) > 1:
            _text(rect.position+Vector2(grid_cell*0.57,grid_cell*0.3),str(entry["level"]),12,Color("f2dc8b"))
    _draw_colony_hauls(colony)
    _text(grid_origin+Vector2(2,grid_cell*8+30),"Склад %d/%d  •  Рейс %d циклов  •  Жителей %d" % [game.colony_stored(colony_index),game.colony_storage(colony_index),colony["convoy"]["eta"],colony["population"]],17,muted)

func _draw_colony_hauls(colony: Dictionary) -> void:
    # Visual progress follows the actual shortest-road path, not a direct jump.
    for job in colony.get("hauls",[]):
        var path: Array = job.get("path",[])
        if path.size() < 2:
            continue
        for i in range(path.size()-1):
            var start_tile: Array = path[i]
            var end_tile: Array = path[i+1]
            var from := grid_origin+Vector2(float(start_tile[0])+0.5,float(start_tile[1])+0.5)*grid_cell
            var to := grid_origin+Vector2(float(end_tile[0])+0.5,float(end_tile[1])+0.5)*grid_cell
            draw_line(from,to,Color("a6e6d8",0.35),2.5)
        var duration := maxf(1.0,float(job.get("total_eta",job.get("eta",1))))
        var progress := clampf((duration-float(job["eta"])+tick_fraction)/duration,0.0,1.0)
        var steps := progress*float(path.size()-1)
        var segment := mini(int(floor(steps)),path.size()-2)
        var a: Array = path[segment]
        var b: Array = path[segment+1]
        var movement := Vector2(float(a[0])+0.5,float(a[1])+0.5).lerp(
            Vector2(float(b[0])+0.5,float(b[1])+0.5),steps-float(segment))
        var position := grid_origin+movement*grid_cell
        draw_circle(position,minf(13.0,grid_cell*0.26),Color("103a42"))
        draw_circle(position,minf(9.0,grid_cell*0.19),Color("f3c36d"))
        draw_circle(position,minf(3.0,grid_cell*0.07),Color("fbf3d9"))

func _draw_fleet() -> void:
    _caption("ФЛОТ / ВЕРФЬ И ЭКСПЕДИЦИИ", "Классы: разведчики, грузовозы и эскортные корабли · патрули и ремонт")
    var columns := 3
    var rows: int = maxi(1,int(ceili(float(game.ships.size())/float(columns))))
    var cw := (size.x-140)/float(columns)
    var ch := minf(155.0,(size.y-158)/float(rows))
    for i in range(game.ships.size()):
        var ship: Dictionary = game.ships[i]
        var r := Rect2(Vector2(55+(i%columns)*cw,122+int(i/columns)*ch),Vector2(cw-18,ch-12))
        draw_rect(r,Color("1a3041"))
        draw_rect(r,Color("416379"),false,1.4)
        var center := r.position+Vector2(48,52)
        var hull_col := Color("80cbd5") if int(ship["health"])>0 else Color("8a4550")
        var silhouette := PackedVector2Array([center+Vector2(0,-25),center+Vector2(18,12),center+Vector2(0,7),center+Vector2(-18,12)])
        draw_colored_polygon(silhouette,hull_col)
        draw_line(center+Vector2(-22,12),center+Vector2(22,12),Color("b1d4e4"),2.0)
        _text(r.position+Vector2(90,39),ship["name"],18)
        _text(r.position+Vector2(90,68),"Корпус %d%%" % ship["health"],15,muted)
        var status := "В ПУТИ: %d" % ship["eta"] if int(ship["eta"])>0 else ("ПОТЕРЯН" if int(ship["health"])<=0 else "НА БАЗЕ")
        _text(r.position+Vector2(90,94),status,15,Color("f1c47c"))

func _draw_battle() -> void:
    _caption("КОСМИЧЕСКИЙ БОЙ / ТАКТИЧЕСКОЕ УПРАВЛЕНИЕ", "Команды кораблю — в правой панели. Стратегическое время остановлено")
    if game.pending_battle.is_empty():
        _text(Vector2(70,190),"Нет текущего боевого столкновения",26,muted)
        return
    var battle: Dictionary = game.pending_battle
    var ship: Dictionary = game.ships[int(battle["ship_index"])]
    var center_y: float = size.y*0.53
    var ally: Vector2 = Vector2(size.x*0.28,center_y)
    var enemy: Vector2 = Vector2(size.x*0.73,center_y)
    draw_line(ally,enemy,Color("33546c"),2.0,true)
    var player_hull: PackedVector2Array = PackedVector2Array([
        ally+Vector2(80,0),ally+Vector2(-36,-48),ally+Vector2(-12,0),ally+Vector2(-36,48)])
    draw_colored_polygon(player_hull,Color("63b6bc"))
    draw_line(ally+Vector2(-34,-48),ally+Vector2(-34,48),Color("afedf0"),3.0)
    draw_circle(enemy,58.0,Color("5e293e"))
    draw_arc(enemy,58,0,TAU,44,Color("ec7181"),4)
    draw_colored_polygon(PackedVector2Array([enemy+Vector2(-54,0),enemy+Vector2(30,-35),enemy+Vector2(50,0),enemy+Vector2(30,35)]),Color("d16b77"))
    var player_hp: float = clampf(float(ship["health"])/100.0,0.0,1.0)
    var enemy_hp: float = clampf(float(battle["enemy_hp"])/maxf(1.0,float(battle["enemy_max_hp"])),0.0,1.0)
    for segment in [[ally,player_hp,Color("54d8bb")],[enemy,enemy_hp,Color("ef8585")]]:
        var at: Vector2 = segment[0]
        draw_rect(Rect2(at+Vector2(-100,95),Vector2(200,14)),Color("243244"))
        draw_rect(Rect2(at+Vector2(-100,95),Vector2(200*float(segment[1]),14)),segment[2])
    _text(ally+Vector2(-100,143),"%s / %d%%" % [ship["name"],int(ship["health"])],21)
    _text(enemy+Vector2(-100,143),"ПИРАТСКИЙ ФЛОТ / %d HP" % int(battle["enemy_hp"]),21)
    _text(Vector2(55,size.y-45),"Тактические приказы • противник отвечает после каждого действия",18,muted)

func _draw_diplomacy() -> void:
    _caption("ПОЛИТИЧЕСКАЯ КАРТА / ФРАКЦИИ", "Торговля и промышленность фракций · риск пиратских перехватов %d%%" % game.pirate_threat)
    for i in range(Db.FACTION_IDS.size()):
        var faction: String = Db.FACTION_IDS[i]
        var relation: int = int(game.faction_standing.get(faction,0))
        var y: float = 150.0+i*135
        draw_rect(Rect2(Vector2(70,y),Vector2(size.x-140,112)),Color("1b3040"))
        _text(Vector2(94,y+36),faction,29)
        _text(Vector2(94,y+72),"ОТНОШЕНИЯ: %+d" % relation,20,Color("80d8a9") if relation>=0 else Color("e29a8c"))
        if faction != "Рой":
            _text(Vector2(94,y+98),"КАЗНА: %d ₡  ·  ТОВАРЫ: %d" % [int(game.faction_economy[faction]["treasury"]),game.faction_economy[faction]["stock"].size()],14,muted)
        draw_rect(Rect2(Vector2(360,y+49),Vector2(size.x-495,18)),Color("304353"))
        var ratio := clampf((float(relation)+100.0)/200.0,0.0,1.0)
        draw_rect(Rect2(Vector2(360,y+49),Vector2((size.x-495)*ratio,18)),Color("77d4ca") if relation>=0 else Color("d39279"))

func _draw_campaign() -> void:
    _caption("КАМПАНИЯ / ДОРОГА К НУЛЕВОЙ ОРБИТЕ", "Четыре главы · связанная экономика · исследования · финальная экспедиция")
    var span := (size.x-145)/4.0
    for i in range(Db.OBJECTIVES.size()):
        var obj: Dictionary = Db.OBJECTIVES[i]
        var pos := Vector2(54+i*span,145)
        var active := i == game.campaign_stage
        var done := i < game.campaign_stage
        var col := Color("68d4c0") if done else (Color("ddb779") if active else Color("586f83"))
        draw_circle(pos+Vector2(span*0.48,62),28,col.darkened(0.55))
        draw_arc(pos+Vector2(span*0.48,62),29,0,TAU,48,col,3)
        _text(pos+Vector2(span*0.44,71),str(i+1),28,col)
        if i < Db.OBJECTIVES.size()-1:
            draw_line(pos+Vector2(span*0.48+32,62),pos+Vector2(span+span*0.48-32,62),Color("3c6d78"),3)
        _text(pos+Vector2(8,160),obj["name"],18)
    _text(Vector2(74,size.y-90),"ГЛАВА %d / 4" % (mini(4,game.campaign_stage+1)),28,Color("e4c88d"))
    _text(Vector2(74,size.y-55),game.campaign_progress(),17,muted)
