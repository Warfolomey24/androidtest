extends Control
## Landscape Android-first control room. No external art or paid assets.
const State = preload("res://scripts/sim/game_state.gd")
const Db = preload("res://scripts/sim/database.gd")
const WorldView = preload("res://scripts/ui/world_view.gd")

const NAV = [
    ["station", "СТАНЦИЯ"], ["mine", "ШАХТА"], ["colony", "КОЛОНИИ"],
    ["galaxy", "ГАЛАКТИКА"], ["fleet", "ФЛОТ"], ["battle", "БОЙ"], ["research", "НАУКА"],
    ["market", "РЫНОК"], ["contracts", "КОНТРАКТЫ"], ["diplomacy", "ФРАКЦИИ"], ["campaign", "КАМПАНИЯ"]
]
const BACK := Color("0c1523")
const PANEL := Color("162637")
const LINE := Color("2a4b5e")
const AQUA := Color("66dccc")
const GOLD := Color("dfb87c")
const TEXT := Color("e5f0f4")
const MUTED := Color("90a7b7")

var game = State.new()
var view := "station"
var sector_index := 0
var selected_building := "habitat"
var selected_colony_building := "road"
var selected_colony := 0
var station_tool := "build"
var colony_tool := "build"
var selected_ship := 0
var selected_star := 1
var day_speed := 0
var elapsed := 0.0
var header_status: Label
var resource_status: Label
var time_status: Label
var notice: Label
var sidebar: VBoxContainer
var sidebar_scroll: ScrollContainer
var canvas
var nav_buttons: Dictionary = {}
var confirmation: ConfirmationDialog
var sidebar_touch_scrolling: bool = false
var confirmed_action: Callable = Callable()

func _ready() -> void:
    _make_shell()
    confirmation = ConfirmationDialog.new()
    confirmation.title = "Подтверждение операции"
    confirmation.dialog_text = "Продолжить?"
    confirmation.confirmed.connect(_execute_confirmed)
    add_child(confirmation)
    _refresh()

func _process(delta: float) -> void:
    if day_speed <= 0:
        return
    elapsed += delta * float(day_speed)
    canvas.tick_fraction = clampf(elapsed/2.5,0.0,1.0)
    canvas.queue_redraw()
    if elapsed >= 2.5:
        elapsed -= 2.5
        game.step()
        _auto_save_if_due()
        if game.defeated or game.victory or not game.pending_story.is_empty():
            day_speed = 0
        _refresh()

func _style(background: Color, outline: Color = LINE, radius: int = 10) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = background
    style.border_color = outline
    style.border_width_left = 1
    style.border_width_top = 1
    style.border_width_right = 1
    style.border_width_bottom = 1
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_right = radius
    style.corner_radius_bottom_left = radius
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 8
    style.content_margin_bottom = 8
    return style

func _make_label(s: String, point_size: int = 20, color: Color = TEXT) -> Label:
    var label := Label.new()
    label.text = s
    label.add_theme_font_size_override("font_size",point_size)
    label.add_theme_color_override("font_color",color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return label

func _action_button(s: String, callback: Callable, primary: bool = false) -> Button:
    var button := Button.new()
    button.text = s
    button.custom_minimum_size = Vector2(0,48)
    button.add_theme_font_size_override("font_size",18)
    button.add_theme_color_override("font_color",TEXT)
    button.add_theme_stylebox_override("normal",_style(Color("14525b") if primary else Color("22374b")))
    button.add_theme_stylebox_override("hover",_style(Color("276b75")))
    button.add_theme_stylebox_override("pressed",_style(Color("10535c"),AQUA))
    button.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,AQUA))
    button.pressed.connect(callback)
    return button

func _make_shell() -> void:
    var background := ColorRect.new()
    background.color = BACK
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    var root := VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation",6)
    add_child(root)

    var head := HBoxContainer.new()
    head.custom_minimum_size = Vector2(0,75)
    head.add_theme_constant_override("separation",26)
    root.add_child(head)
    var brand := VBoxContainer.new()
    brand.custom_minimum_size.x = 385
    head.add_child(brand)
    brand.add_child(_make_label("ПЕРИМЕТР / НУЛЕВАЯ ОРБИТА",26,AQUA))
    brand.add_child(_make_label("КОСМИЧЕСКАЯ ЭКОНОМИКА · ALPHA 0.8",14,MUTED))
    header_status = _make_label("",20)
    header_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(header_status)
    time_status = _make_label("",20,GOLD)
    head.add_child(time_status)
    head.add_child(_action_button("⏸" ,_toggle_time,true))

    resource_status = _make_label("",20,TEXT)
    resource_status.custom_minimum_size = Vector2(0,42)
    root.add_child(resource_status)

    var nav_scroll := ScrollContainer.new()
    nav_scroll.custom_minimum_size = Vector2(0,64)
    nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    nav_scroll.follow_focus = true
    root.add_child(nav_scroll)
    var navigation := HBoxContainer.new()
    navigation.add_theme_constant_override("separation",8)
    nav_scroll.add_child(navigation)
    for item in NAV:
        var key: String = item[0]
        var button := _action_button(item[1],_change_view.bind(key),false)
        button.custom_minimum_size.x = 153
        nav_buttons[key] = button
        navigation.add_child(button)

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation",10)
    root.add_child(body)

    var map_border := PanelContainer.new()
    map_border.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_border.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_border.add_theme_stylebox_override("panel",_style(Color("0a1726")))
    body.add_child(map_border)
    canvas = WorldView.new()
    canvas.game = game
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    canvas.grid_pressed.connect(_grid_clicked)
    canvas.star_pressed.connect(_star_clicked)
    map_border.add_child(canvas)

    var side_border := PanelContainer.new()
    side_border.custom_minimum_size = Vector2(405,0)
    side_border.add_theme_stylebox_override("panel",_style(PANEL))
    body.add_child(side_border)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.scroll_deadzone = 24
    scroll.follow_focus = true
    scroll.scroll_started.connect(_on_sidebar_touch_started)
    scroll.scroll_ended.connect(_on_sidebar_touch_ended)
    sidebar_scroll = scroll
    side_border.add_child(scroll)
    sidebar = VBoxContainer.new()
    sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sidebar.add_theme_constant_override("separation",9)
    scroll.add_child(sidebar)

    notice = _make_label("Готово. Выберите игровой раздел.",16,MUTED)
    notice.custom_minimum_size = Vector2(0,43)
    root.add_child(notice)

func _refresh() -> void:
    if not game.pending_story.is_empty():
        day_speed = 0
        view = "campaign"
    if not game.pending_battle.is_empty():
        day_speed = 0
        view = "battle"
    if selected_colony >= game.colonies.size():
        selected_colony = 0
    if selected_ship >= game.ships.size():
        selected_ship = 0
    header_status.text = "КОРПУС %d%%   •   ДОВЕРИЕ %d%%   •   ЭКИПАЖ %d" % [int(game.hull),int(game.trust),game.crew]
    resource_status.text = "  ⛏ %d РУДА     ◈ %d СПЛАВ     ▣ %d ПОЛИМЕР     ◉ %d ПИЩА     ≋ %d ВОДА     ◆ %d ТОПЛИВО     ◇ %d НАУКА     ₡ %d" % [
        int(game.resources.get("ore",0)),int(game.resources.get("alloy",0)),
        int(game.resources.get("polymer",0)),int(game.resources.get("food",0)),
        int(game.resources.get("water",0)),int(game.resources.get("fuel",0)),
        int(game.resources.get("science",0)),int(game.resources.get("credits",0))]
    time_status.text = "ЦИКЛ %03d   ·   %s" % [game.cycle,"ПАУЗА" if day_speed == 0 else "ХОД ×%d" % day_speed]
    for key in nav_buttons.keys():
        var btn: Button = nav_buttons[key]
        btn.add_theme_stylebox_override("normal",_style(Color("164b54") if key == view else Color("22374b"),AQUA if key == view else LINE))
    canvas.game = game
    canvas.mode = view
    canvas.sector_index = sector_index
    canvas.colony_index = selected_colony
    canvas.station_tool = station_tool
    canvas.colony_tool = colony_tool
    canvas.tick_fraction = clampf(elapsed/2.5,0.0,1.0)
    canvas.chosen_star = selected_star
    canvas.queue_redraw()
    # Do not destroy/recreate pressed controls during a touchscreen scroll gesture.
    # Refresh the sidebar only after touch scrolling completes.
    if not sidebar_touch_scrolling or not game.pending_battle.is_empty() or not game.pending_story.is_empty():
        var old_scroll := sidebar_scroll.scroll_vertical
        _render_sidebar()
        sidebar_scroll.set_deferred("scroll_vertical",old_scroll)
    if not game.pending_battle.is_empty():
        notice.text = "КОСМИЧЕСКИЙ БОЙ: выберите действие. Стратегическое время остановлено."
    elif not game.pending_story.is_empty():
        notice.text = "ТРЕБУЕТСЯ РЕШЕНИЕ: откройте сюжетный вопрос в разделе кампании. Время остановлено."
    elif game.victory:
        notice.text = "ПОБЕДА. Ядро перехода работает: новые колонии получили шанс на жизнь!"
    elif game.defeated:
        notice.text = "ПОРАЖЕНИЕ. Корабль-станция потерян. Начните новую экспедицию."

func _on_sidebar_touch_started() -> void:
    sidebar_touch_scrolling = true

func _on_sidebar_touch_ended() -> void:
    sidebar_touch_scrolling = false
    _refresh()

func _clear_sidebar() -> void:
    for child in sidebar.get_children():
        sidebar.remove_child(child)
        child.queue_free()

func _section(s: String) -> void:
    sidebar.add_child(_make_label(s,24,AQUA))

func _note(s: String, color: Color = MUTED) -> void:
    sidebar.add_child(_make_label(s,17,color))

func _render_sidebar() -> void:
    _clear_sidebar()
    match view:
        "station": _sidebar_station()
        "mine": _sidebar_mine()
        "colony": _sidebar_colony()
        "galaxy": _sidebar_galaxy()
        "fleet": _sidebar_fleet()
        "battle": _sidebar_battle()
        "research": _sidebar_research()
        "market": _sidebar_market()
        "contracts": _sidebar_contracts()
        "diplomacy": _sidebar_diplomacy()
        "campaign": _sidebar_campaign()
    sidebar.add_child(HSeparator.new())
    _section("УПРАВЛЕНИЕ")
    var controls := HBoxContainer.new()
    sidebar.add_child(controls)
    controls.add_child(_action_button("ТЕМП: 0 → 1 → 2 → 4",_toggle_time,true))
    controls.add_child(_action_button("+ 1 ЦИКЛ",_next_cycle))
    sidebar.add_child(_action_button("СОХРАНИТЬ",_save_game))
    sidebar.add_child(_action_button("ЗАГРУЗИТЬ",_load_game))
    _section("СОХРАНЕНИЯ · АВТО + 3 СЛОТА")
    _note("Автосохранение каждые 5 циклов. Резервные копии создаются автоматически.")
    for slot in range(1,4):
        var slot_row := HBoxContainer.new()
        sidebar.add_child(slot_row)
        slot_row.add_child(_action_button("ЗАПИСАТЬ %d" % slot,_save_game.bind(slot)))
        slot_row.add_child(_action_button("ЗАГРУЗИТЬ %d" % slot,_load_game.bind(slot)))
    sidebar.add_child(_action_button("НОВАЯ ИГРА",_request_new_game))
    sidebar.add_child(HSeparator.new())
    _section("ЖУРНАЛ СОБЫТИЙ")
    for entry in game.event_log.slice(0,4):
        _note(str(entry))

func _sidebar_station() -> void:
    _section("УПРАВЛЕНИЕ СЕКТОРАМИ")
    var selector := GridContainer.new()
    selector.columns = 3
    sidebar.add_child(selector)
    for i in range(6):
        var available := bool(game.sectors[i]["open"])
        var label := "%02d  %s" % [i+1,"●" if available else "⊘"]
        selector.add_child(_action_button(label,_set_sector.bind(i),i == sector_index))
    if not game.sectors[sector_index]["open"]:
        _note("Сектор законсервирован. Открытие: 45 сплавов, 20 полимеров.")
        sidebar.add_child(_action_button("ОТКРЫТЬ СЕКТОР",_open_sector,true))
        return
    _note("Энергия: %+d • Работники: %d / %d" % [game.power_balance(),game.workers_required(),game.crew])
    _note("Жильё: %d / %d | Сектор: %d / %d" % [game.crew,game.population_capacity(),int(game.sectors[sector_index]["population"]),game.sector_capacity(sector_index)])
    if sector_index > 0:
        sidebar.add_child(_action_button("ПЕРЕВЕСТИ 10 ЧЕЛОВЕК ИЗ СЕКТОРА 1",_transfer_crew.bind(0,sector_index)))
        sidebar.add_child(_action_button("ВЕРНУТЬ 10 ЧЕЛОВЕК В СЕКТОР 1",_transfer_crew.bind(sector_index,0)))
    sidebar.add_child(_action_button("РЕМОНТ КОРПУСА (8 сплавов)",_emergency_repair))
    sidebar.add_child(HSeparator.new())
    _section("РЕЖИМ КАРТЫ")
    var modes := HBoxContainer.new()
    sidebar.add_child(modes)
    modes.add_child(_action_button("СТРОИТЬ",_set_station_tool.bind("build"),station_tool == "build"))
    modes.add_child(_action_button("УЛУЧШИТЬ",_set_station_tool.bind("upgrade"),station_tool == "upgrade"))
    modes.add_child(_action_button("СНЕСТИ",_set_station_tool.bind("dismantle"),station_tool == "dismantle"))
    _section("СТРОИТЕЛЬСТВО")
    _note("Выберите тип и коснитесь свободной клетки слева.")
    for id in Db.BUILDINGS.keys():
        var spec: Dictionary = Db.BUILDINGS[id]
        var cost: Dictionary = spec["cost"]
        var str_cost := ""
        for resource_id in cost.keys():
            str_cost += "%s %d  " % [Db.label_for(resource_id),int(cost[resource_id])]
        var title: String = ("● " if id == selected_building else "   ") + str(spec["name"])
        sidebar.add_child(_action_button(title,_pick_building.bind(id),id == selected_building))
        _note(str_cost)

func _sidebar_mine() -> void:
    _section("ГЕОЛОГИЧЕСКАЯ СЛУЖБА")
    _note("Добыча пласта продолжается автоматически. Шахтёры тратят время на переход к участку.")
    _note("Автозадания: %d · Шахтёров: %d/8" % [game.mine_queue.size(),game.miners.size()])
    sidebar.add_child(_action_button("НАНЯТЬ ШАХТЁРА (70 ₡)",_hire_miner))
    for worker in game.miners:
        _note("%s · %s" % [worker["name"],"В пути: %d" % worker["eta"] if int(worker["eta"]) > 0 else "Свободен"])
    _note("Локальный склад: %d ед. • Шаттл: %s" % [game.total_mine_storage(),"В пути" if int(game.shuttle["eta"]) > 0 else "На погрузке"])
    sidebar.add_child(_action_button("РАЗВЕДАТЬ УЧАСТКИ (-55 ₡)",_survey_mine,true))
    sidebar.add_child(_action_button("ОСТАНОВИТЬ АВТОДОБЫЧУ",_stop_mining))
    sidebar.add_child(HSeparator.new())
    _section("ПРИОРИТЕТ ГРУЗОВОГО РЕЙСА")
    var cargo_row := GridContainer.new()
    cargo_row.columns = 2
    sidebar.add_child(cargo_row)
    for id in ["ore","silicon","copper","ice"]:
        cargo_row.add_child(_action_button(("● " if id == game.cargo_priority else "   ")+Db.label_for(id),_set_cargo_priority.bind(id),id == game.cargo_priority))
    _section("ЗАПАСЫ МИНЕРАЛОВ")
    for id in ["ore","silicon","copper","ice"]:
        _note("%s: на станции %d / в шахте %d" % [Db.label_for(id),int(game.resources.get(id,0)),int(game.mine_stockpile.get(id,0))],Db.RESOURCE_COLORS[id])
    _note("Пласты и количество руды процедурно создаются при старте новой игры.")

func _sidebar_galaxy() -> void:
    var star: Dictionary = Db.SYSTEMS[selected_star]
    _section("НАВИГАЦИЯ")
    _note("Выбранная система: %s" % star["name"],GOLD)
    _note("Фракция: %s • Риск: %d" % [star["faction"],int(star["risk"])])
    _note("Основной ресурс: %s" % Db.label_for(star["ore"]))
    _note("Статус: %s" % ("Исследована" if selected_star in game.discovered else "Неизвестна"))
    sidebar.add_child(HSeparator.new())
    _section("ЭКСПЕДИЦИОННЫЙ ФЛОТ")
    for i in range(game.ships.size()):
        var ship: Dictionary = game.ships[i]
        var busy := int(ship["eta"]) > 0
        _note("%s  •  %s" % [ship["name"], "В пути: %d циклов" % ship["eta"] if busy else "На базе"],TEXT)
        var button := _action_button("ОТПРАВИТЬ (4 топлива)",_send_ship.bind(i),true)
        button.disabled = busy or not game.can_send_to(selected_star)
        sidebar.add_child(button)
    sidebar.add_child(HSeparator.new())
    if selected_star in game.discovered and selected_star != 0:
        sidebar.add_child(_action_button("ОСНОВАТЬ КОЛОНИЮ",_found_colony))
    _note("Ковчег-9 требует «Гравитационный парус». Внешние системы требуют картографию.")
    _note("Экспедиции привозят сырьё и научные данные. Опасные системы повреждают корпус и корабли.")

func _sidebar_research() -> void:
    _section("НАУЧНЫЙ СОВЕТ")
    _note("Свободная наука: %d" % int(game.resources["science"]),GOLD)
    for tech in Db.TECHS:
        var id: String = tech["id"]
        var ready := true
        for prerequisite in tech["requires"]:
            if not prerequisite in game.researched:
                ready = false
        var known: bool = id in game.researched
        var label: String = ("✓ " if known else "◈ ") + str(tech["name"]) + "  [%d]" % int(tech["cost"])
        var b := _action_button(label,_research.bind(id),not known and ready)
        b.disabled = known or not ready
        sidebar.add_child(b)
        _note(tech["desc"])

func _sidebar_market() -> void:
    _section("ГАЛАКТИЧЕСКАЯ БИРЖА")
    _note("Цены динамические. Объём сделки: 5. Поставки сразу поступают на станцию.")
    for id in Db.MARKETS.keys():
        var price := game.market_price(id)
        _note("%s  |  %d ₡   |   запас %d" % [Db.label_for(id),price,int(game.resources.get(id,0))],Db.RESOURCE_COLORS[id])
        var trade_row := HBoxContainer.new()
        sidebar.add_child(trade_row)
        trade_row.add_child(_action_button("КУПИТЬ 5",_trade.bind(id,true)))
        trade_row.add_child(_action_button("ПРОДАТЬ 5",_trade.bind(id,false)))

func _sidebar_contracts() -> void:
    _section("ДОГОВОРЫ КОЛОНИЙ")
    _note("Поставляйте материалы, повышайте репутацию и восстанавливайте доверие экипажа.")
    for i in range(Db.CONTRACTS.size()):
        var deal: Dictionary = Db.CONTRACTS[i]
        _note("%s" % deal["name"],TEXT)
        _note("%d × %s → %d кредитов" % [deal["amount"],Db.label_for(deal["resource"]),deal["reward"]])
        var remaining := maxi(0,int(game.contract_ready[i])-game.cycle)
        var button := _action_button("ВЫПОЛНИТЬ" if remaining == 0 else "СНОВА ЧЕРЕЗ %d ЦИКЛОВ" % remaining,_complete_contract.bind(i),true)
        button.disabled = remaining > 0
        sidebar.add_child(button)

func _say(msg: String) -> void:
    notice.text = msg if msg != "" else "Команда выполнена."
    _refresh()

func _change_view(key: String) -> void:
    view = key
    sidebar_scroll.scroll_vertical = 0
    _refresh()

func _toggle_time() -> void:
    match day_speed:
        0: day_speed = 1
        1: day_speed = 2
        2: day_speed = 4
        _: day_speed = 0
    elapsed = 0.0
    _refresh()

func _next_cycle() -> void:
    var previous: int = int(game.cycle)
    game.step()
    _auto_save_if_due()
    _say("Продвинут один игровой цикл" if game.cycle > previous else "Время остановлено. Завершите бой или примите сюжетное решение")

func _set_sector(i: int) -> void:
    sector_index = i
    _refresh()

func _pick_building(id: String) -> void:
    selected_building = id
    _say("Размещение: %s. Коснитесь свободной клетки." % Db.BUILDINGS[id]["name"])

func _grid_clicked(x: int,y: int) -> void:
    if view == "station":
        match station_tool:
            "upgrade": _say(game.upgrade_station_building(sector_index,x,y))
            "dismantle": _ask_confirmation("Демонтировать объект? Часть ресурсов вернётся на склад.",_dismantle_confirmed.bind(sector_index,x,y))
            _: _say(game.build(selected_building,sector_index,x,y))
    elif view == "mine":
        _say(game.mine_tile(x,y))
    elif view == "colony":
        if colony_tool == "upgrade":
            _say(game.colony_upgrade(selected_colony,x,y))
        else:
            _say(game.colony_build(selected_colony,selected_colony_building,x,y))

func _star_clicked(i: int) -> void:
    selected_star = i
    _refresh()

func _open_sector() -> void:
    _say(game.open_sector(sector_index))

func _survey_mine() -> void:
    _say(game.survey_mine())

func _set_cargo_priority(id: String) -> void:
    game.set_cargo_priority(id)
    _say("Приоритет доставки: %s" % Db.label_for(id))

func _stop_mining() -> void:
    game.mine_queue.clear()
    _say("Автодобыча остановлена")

func _emergency_repair() -> void:
    _say(game.emergency_repair())

func _send_ship(i: int) -> void:
    _say(game.send_ship(i,selected_star))

func _research(id: String) -> void:
    _say(game.research(id))

func _trade(id: String, buy: bool) -> void:
    _say(game.trade(id,5,buy))

func _complete_contract(i: int) -> void:
    _say(game.complete_contract(i))

func _save_game(slot: int = 0) -> void:
    var result := game.save_game(slot)
    _say("Данные записаны в слот %d" % slot if result == "" else result)

func _load_game(slot: int = 0) -> void:
    var result: String = game.load_game(slot)
    if result == "":
        selected_colony = 0
        selected_ship = 0
        sector_index = 0
        selected_star = 1
    _say("Слот %d загружен" % slot if result == "" else result)

func _auto_save_if_due() -> void:
    if game.cycle > 1 and game.cycle % 5 == 0:
        var result := game.save_game(0)
        if result != "":
            notice.text = "Автосохранение не удалось: %s" % result

func _ask_confirmation(message: String, action: Callable) -> void:
    confirmed_action = action
    confirmation.dialog_text = message
    confirmation.popup_centered(Vector2i(570,240))

func _execute_confirmed() -> void:
    if confirmed_action.is_valid():
        var action := confirmed_action
        confirmed_action = Callable()
        action.call()

func _request_new_game() -> void:
    _ask_confirmation("Начать новую игру? Несохранённый прогресс будет потерян.",_new_game)

func _dismantle_confirmed(sector: int, x: int, y: int) -> void:
    _say(game.dismantle_station_building(sector,x,y))

func _new_game() -> void:
    game.start_new(randi_range(1,2147483647))
    elapsed = 0
    day_speed = 0
    sector_index = 0
    selected_star = 1
    selected_building = "habitat"
    selected_colony_building = "road"
    selected_colony = 0
    selected_ship = 0
    station_tool = "build"
    colony_tool = "build"
    _say("Начата новая экспедиция")


func _sidebar_colony() -> void:
    _section("ПЛАНЕТАРНЫЕ КОЛОНИИ")
    var picker := GridContainer.new()
    picker.columns = 2
    sidebar.add_child(picker)
    for i in range(game.colonies.size()):
        var colony: Dictionary = game.colonies[i]
        picker.add_child(_action_button("%d · %s" % [i+1,Db.SYSTEMS[int(colony["system"])]["name"]],_set_colony.bind(i),selected_colony == i))
    var c: Dictionary = game.colonies[selected_colony]
    _note("%s · Население: %d · Мораль: %d%%" % [c["name"],int(c["population"]),int(c["morale"])],GOLD)
    _note("Склад: %d / %d" % [game.colony_stored(selected_colony),game.colony_storage(selected_colony)])
    _note("Внутренний транспорт: %d/%d рейсов · зарезервировано %d ед." % [
        c.get("hauls",[]).size(),game.colony_haul_capacity(selected_colony),game.colony_haul_reserved(selected_colony)])
    _note("Грузовой рейс: %d циклов · Приоритет: %s" % [int(c["convoy"]["eta"]),Db.label_for(c["priority"])])
    var assigned_count := 0
    for ship in game.ships:
        if int(ship.get("assigned_colony",-1)) == selected_colony and int(ship.get("health",0)) > 0:
            assigned_count += 1
    _note("Грузовозы на маршруте: %d · вместимость зависит от назначений" % assigned_count)
    var priorities := GridContainer.new()
    priorities.columns = 3
    sidebar.add_child(priorities)
    for id in ["ore","ice","silicon","alloy","food","water","fuel","components"]:
        priorities.add_child(_action_button(Db.label_for(id),_set_colony_priority.bind(id),str(c["priority"]) == id))
    sidebar.add_child(HSeparator.new())
    _section("ПЛАНЕТАРНАЯ ИНДУСТРИЯ")
    _note("Производство работает только при дороге к терминалу. Ресурсы остаются на местном складе до конвоя.")
    var tools := HBoxContainer.new()
    sidebar.add_child(tools)
    tools.add_child(_action_button("ПОСТРОЙКА",_set_colony_tool.bind("build"),colony_tool == "build"))
    tools.add_child(_action_button("АПГРЕЙД 1–10",_set_colony_tool.bind("upgrade"),colony_tool == "upgrade"))
    for id in Db.COLONY_BUILDINGS.keys():
        if id == "landing":
            continue
        var spec: Dictionary = Db.COLONY_BUILDINGS[id]
        sidebar.add_child(_action_button(("● " if selected_colony_building == id else "  ")+spec["name"],_choose_colony_building.bind(id),selected_colony_building == id))
        var cost := ""
        for res in spec["cost"].keys():
            cost += "%s %d  " % [Db.label_for(res),int(spec["cost"][res])]
        _note(cost)
    _section("ЛОКАЛЬНЫЕ ЗАПАСЫ")
    for res in c["stock"].keys():
        _note("%s: %d" % [Db.label_for(res),int(c["stock"][res])],Db.RESOURCE_COLORS.get(res,TEXT))

func _sidebar_fleet() -> void:
    _section("ФЛОТ И ВЕРФИ")
    _note("Постройте ангар на станции для выпуска кораблей. Патруль снижает риск и доставляет трофеи.")
    for i in range(game.ships.size()):
        var ship: Dictionary = game.ships[i]
        var route := int(ship.get("assigned_colony",-1))
        var status := "Потерян" if int(ship["health"]) <= 0 else ("В пути %d" % int(ship["eta"]) if int(ship["eta"]) > 0 else ("Грузовой рейс %d" % int(ship.get("cargo_eta",0)) if int(ship.get("cargo_eta",0)) > 0 else ("Маршрут колонии %d" % (route+1) if route >= 0 else "На базе")))
        sidebar.add_child(_action_button("%s · %d%% · %s" % [ship["name"],int(ship["health"]),status],_select_ship.bind(i),selected_ship == i))
    var chosen: Dictionary = game.ships[selected_ship]
    _note("Выбран: %s" % chosen["name"],GOLD)
    _note("Класс: %s | Корпус: %d%%" % [Db.SHIP_TYPES[str(chosen.get("type","scout"))]["name"],int(chosen["health"])])
    _note("Цель: %s" % Db.SYSTEMS[selected_star]["name"])
    sidebar.add_child(_action_button("ПАТРУЛЬ В ВЫБРАННУЮ СИСТЕМУ",_patrol_selected))
    sidebar.add_child(_action_button("РЕМОНТИРОВАТЬ КОРАБЛЬ",_repair_selected))
    if str(chosen.get("type","")) == "escort":
        _section("СОПРОВОЖДЕНИЕ ТОРГОВЫХ РЕЙСОВ")
        _note("Выберите рейс для охраны. Вылет стоит 3 топлива; корабль занят до доставки.")
        if game.trade_flights.is_empty():
            _note("В космосе пока нет наших торговых конвоев")
        for flight_index in range(game.trade_flights.size()):
            var flight: Dictionary = game.trade_flights[flight_index]
            var has_escort: bool = int(flight.get("escort_index",-1)) >= 0
            var button := _action_button("%s · ETA %d · %s" % [flight["faction"],int(flight["eta"]),"ЭСКОРТ НАЗНАЧЕН" if has_escort else "СОПРОВОДИТЬ"], _escort_selected.bind(flight_index))
            button.disabled = has_escort or int(flight["eta"]) <= 1 or int(chosen["health"]) <= 0 or int(chosen["eta"]) > 0 or int(chosen.get("cargo_eta",0)) > 0
            sidebar.add_child(button)
    if str(chosen.get("type","")) == "freighter":
        _section("НАЗНАЧЕНИЕ ГРУЗОВОЗА")
        _note("Выберите колонию на вкладке «Колонии», затем назначьте на неё грузовоз.")
        sidebar.add_child(_action_button("НАЗНАЧИТЬ ВЫБРАННОЙ КОЛОНИИ",_assign_selected_freighter))
        sidebar.add_child(_action_button("СНЯТЬ С МАРШРУТА",_unassign_selected_freighter))
    sidebar.add_child(HSeparator.new())
    _section("СУДОСТРОЕНИЕ")
    for id in Db.SHIP_TYPES.keys():
        var spec: Dictionary = Db.SHIP_TYPES[id]
        sidebar.add_child(_action_button("ПОСТРОИТЬ: %s" % spec["name"],_build_ship.bind(id)))
        _note("Вместимость %d · Урон %d · Защита %d" % [int(spec["cargo"]),int(spec["attack"]),int(spec["defense"])])
        var costs := ""
        for res in spec["cost"].keys():
            costs += "%s %d  " % [Db.label_for(res),int(spec["cost"][res])]
        _note(costs)

func _sidebar_battle() -> void:
    _section("БОЕВОЕ СТОЛКНОВЕНИЕ")
    if game.pending_battle.is_empty():
        _note("Активного боя нет. Отправьте корабль в патруль из раздела «Флот».")
        sidebar.add_child(_action_button("К ФЛОТУ",_change_view.bind("fleet")))
        return
    var battle: Dictionary = game.pending_battle
    var ship: Dictionary = game.ships[int(battle["ship_index"])]
    _note("Система: %s" % Db.SYSTEMS[int(battle["destination"])]["name"],GOLD)
    _note("Наш корабль: %s, корпус %d%%" % [ship["name"],int(ship["health"])])
    _note("Цель: корпус %d/%d · ход %d" % [int(battle["enemy_hp"]),int(battle["enemy_max_hp"]),int(battle["turn"])])
    if bool(battle["scanned"]):
        _note("Сканер: атака %d, защита %d" % [int(battle["enemy_attack"]),int(battle["enemy_defense"])])
    _section("БОЕВЫЕ ПРИКАЗЫ")
    sidebar.add_child(_action_button("ЗАЛП · высокий урон",_battle_action.bind("salvo"),true))
    sidebar.add_child(_action_button("ПРИЦЕЛЬНЫЙ ОГОНЬ · ослабить орудия",_battle_action.bind("precision")))
    sidebar.add_child(_action_button("ОБОРОНА · уменьшить входящий урон",_battle_action.bind("brace")))
    sidebar.add_child(_action_button("СКАНИРОВАНИЕ · узнать характеристики",_battle_action.bind("scan")))
    sidebar.add_child(_action_button("ОТСТУПИТЬ · сохранить корабль",_battle_action.bind("retreat")))
    _note("Победа приносит трофеи и снижает угрозу пиратов. Поражение может уничтожить корабль.")

func _battle_action(action: String) -> void:
    var result: String = game.battle_action(action)
    if game.pending_battle.is_empty():
        view = "fleet"
    _say(result)

func _sidebar_diplomacy() -> void:
    _section("МЕЖЗВЁЗДНЫЕ ФРАКЦИИ")
    _note("Фракции самостоятельно пополняют склады, потребляют товары и ведут межзвёздную торговлю.")
    _note("Угроза пиратства: %d / 100 · патрули уменьшают угрозу" % game.pirate_threat,GOLD)
    _section("НЕЗАВИСИМЫЕ КОНВОИ")
    if game.faction_fleets.is_empty():
        _note("Другие фракции пока не отправляли грузов")
    for npc_flight in game.faction_fleets:
        _note("%s → %s · %d %s · ETA %d" % [str(npc_flight["source"]),str(npc_flight["destination"]),int(npc_flight["amount"]),Db.label_for(str(npc_flight["resource"])),int(npc_flight["eta"])])
    _section("НАШИ ГРУЗЫ В КОСМОСЕ")
    if game.trade_flights.is_empty():
        _note("Активных торговых рейсов нет")
    for flight in game.trade_flights:
        var escort_index: int = int(flight.get("escort_index",-1))
        var escort_status := "под охраной" if escort_index >= 0 else "без эскорта"
        _note("%s · %s ×%d · ETA %d · %s" % [str(flight["faction"]),Db.label_for(str(flight["resource"])),int(flight["amount"]),int(flight["eta"]),escort_status])
    _note("Для торговли нужен свободный грузовоз. В разделе «Флот» снимите его с колониального маршрута.")
    for faction in Db.FACTION_IDS:
        _section(faction)
        var relation := int(game.faction_standing.get(faction,0))
        _note("Отношения: %+d / 100" % relation,GOLD if relation >= 0 else Color("e38a83"))
        if faction != "Рой":
            sidebar.add_child(_action_button("ДИПЛОМАТИЧЕСКАЯ МИССИЯ (65 ₡ +5 еды)",_negotiate.bind(faction)))
            var market: Dictionary = game.faction_economy[faction]
            _note("Казна: %d ₡ · торговая система: %s" % [int(market["treasury"]),Db.SYSTEMS[int(Db.FACTION_TRADE[faction]["system"])]["name"]])
            for res in Db.FACTION_TRADE[faction]["goods"]:
                var buy_price: int = game.faction_price(faction,res,true)
                var sell_price: int = game.faction_price(faction,res,false)
                _note("%s  · на складе %d · купить %d ₡ / продать %d ₡" % [Db.label_for(res),int(market["stock"].get(res,0)),buy_price,sell_price])
                var buttons := HBoxContainer.new()
                sidebar.add_child(buttons)
                buttons.add_child(_action_button("КУПИТЬ 5",_faction_trade.bind(faction,res,true)))
                buttons.add_child(_action_button("ПРОДАТЬ 5",_faction_trade.bind(faction,res,false)))
        else:
            _note("Не вступает в переговоры · требуется охрана маршрутов")
    _section("НАША РЕПУТАЦИЯ")
    _note("Выполнено контрактов: %d" % game.contracts_completed)

func _sidebar_campaign() -> void:
    if not game.pending_story.is_empty():
        var event := game.story_event()
        if not event.is_empty():
            _section("СРОЧНОЕ СЮЖЕТНОЕ РЕШЕНИЕ")
            _note(str(event["title"]),GOLD)
            _note(str(event["text"]),TEXT)
            for i in range(event["options"].size()):
                var option: Dictionary = event["options"][i]
                var label := str(option["text"])
                var costs: Dictionary = option.get("cost",{})
                if not costs.is_empty():
                    label += "  ·  затраты: "
                    for key in costs.keys():
                        label += "%s %d  " % [Db.label_for(key),int(costs[key])]
                var button := _action_button(label,_resolve_story.bind(i),true)
                button.disabled = not game.can_afford(costs)
                sidebar.add_child(button)
            sidebar.add_child(HSeparator.new())
    _section("ИСТОРИЯ / ЧЕТЫРЕ ГЛАВЫ")
    _note("Цель: стабилизировать колонии, освоить звёзды, построить инфраструктуру и запустить ядро перехода.")
    _note("Текущая глава: %d / 4" % (mini(game.campaign_stage+1,4)),GOLD)
    for i in range(Db.OBJECTIVES.size()):
        var objective: Dictionary = Db.OBJECTIVES[i]
        _section(("✓  " if i < game.campaign_stage else "◇  ")+objective["name"])
        _note(objective["desc"])
    sidebar.add_child(HSeparator.new())
    _section("УСЛОВИЯ ПОБЕДЫ")
    _note("Открыть Ковчег-9, изучить «Ядро перехода», пройти три первых этапа, сохранить корпус и доверие.")
    _note("Код генерации галактики: %d" % game.world_seed)
    _note("Исследовано систем: %d / %d" % [game.discovered.size(),Db.SYSTEMS.size()])
    _note("Исследовано технологий: %d / %d" % [game.researched.size(),Db.TECHS.size()])
    _note("Колоний: %d" % game.colonies.size())
    _section("ПРИНЯТЫЕ РЕШЕНИЯ")
    for record in game.story_history:
        _note("Цикл %d · %s · вариант %d" % [int(record["cycle"]),str(record["id"]),int(record["choice"])+1])

func _set_station_tool(tool: String) -> void:
    station_tool = tool
    _say("Режим станции: %s" % tool)

func _set_colony_tool(tool: String) -> void:
    colony_tool = tool
    _say("Режим колонии: %s" % tool)

func _choose_colony_building(id: String) -> void:
    selected_colony_building = id
    colony_tool = "build"
    _say("Размещение: %s" % Db.COLONY_BUILDINGS[id]["name"])

func _set_colony(i: int) -> void:
    selected_colony = i
    _refresh()

func _set_colony_priority(id: String) -> void:
    _say(game.colony_assign_priority(selected_colony,id))

func _transfer_crew(source: int, target: int) -> void:
    _say(game.transfer_crew(source,target,10))

func _found_colony() -> void:
    var result: String = game.found_colony(selected_star)
    if result == "":
        selected_colony = game.colonies.size()-1
        view = "colony"
    _say(result)

func _select_ship(i: int) -> void:
    selected_ship = i
    _refresh()

func _build_ship(id: String) -> void:
    var result: String = game.build_ship(id)
    if result == "":
        selected_ship = game.ships.size()-1
    _say(result)

func _repair_selected() -> void:
    _say(game.repair_ship(selected_ship))

func _patrol_selected() -> void:
    _say(game.send_patrol(selected_ship,selected_star))

func _negotiate(faction: String) -> void:
    _say(game.negotiate(faction))

func _hire_miner() -> void:
    _say(game.hire_miner())

func _assign_selected_freighter() -> void:
    _say(game.assign_freighter(selected_ship,selected_colony))

func _unassign_selected_freighter() -> void:
    _say(game.assign_freighter(selected_ship,-1))

func _resolve_story(index: int) -> void:
    _say(game.resolve_story(index))

func _faction_trade(faction: String, resource_id: String, buying: bool) -> void:
    _say(game.faction_trade(faction,resource_id,5,buying))

func _escort_selected(flight_index: int) -> void:
    _say(game.escort_trade_flight(selected_ship,flight_index))
