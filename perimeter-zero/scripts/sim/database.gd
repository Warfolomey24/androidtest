extends RefCounted
## All original economy content in one data-driven catalog.

const RESOURCE_LABELS := {
    "ore": "Руда", "alloy": "Сплавы", "polymer": "Полимеры",
    "food": "Пища", "water": "Вода", "fuel": "Топливо",
    "science": "Наука", "credits": "Кредиты", "components": "Компоненты", "silicon": "Кремний",
    "ice": "Лёд", "copper": "Медь"
}
const RESOURCE_COLORS := {
    "ore": Color("8c97a6"), "alloy": Color("b3bfc6"), "polymer": Color("b984dc"),
    "food": Color("89d99a"), "water": Color("65cce4"), "fuel": Color("e1aa5c"),
    "science": Color("67e3dc"), "credits": Color("eac777"), "components": Color("f1b989"),
    "silicon": Color("8bcbe9"), "ice": Color("7eb7e1"), "copper": Color("e4a06d")
}
const BUILDINGS := {
    "reactor": {"name":"Термореактор", "tag":"ЯД", "cost":{"alloy":16, "polymer":4}, "power":35, "workers":6, "consume":{"fuel":1}, "produce":{}},
    "habitat": {"name":"Жилой модуль", "tag":"Ж", "cost":{"alloy":9, "polymer":7}, "power":-3, "workers":0, "consume":{}, "produce":{}, "capacity":55},
    "farm": {"name":"Гидропоника", "tag":"Е", "cost":{"alloy":10, "polymer":6}, "power":-6, "workers":8, "consume":{"water":2}, "produce":{"food":6}},
    "recycler": {"name":"Регенерация", "tag":"В", "cost":{"alloy":8, "polymer":5}, "power":-4, "workers":5, "consume":{}, "produce":{"water":5}},
    "smelter": {"name":"Плавильный цех", "tag":"М", "cost":{"alloy":14, "polymer":3}, "power":-8, "workers":10, "consume":{"ore":5}, "produce":{"alloy":3}},
    "laboratory": {"name":"Исследовательский центр", "tag":"Н", "cost":{"alloy":12, "polymer":8}, "power":-7, "workers":9, "consume":{"silicon":1}, "produce":{"science":3}},
    "repair": {"name":"Ремонтный док", "tag":"Р", "cost":{"alloy":18, "polymer":6}, "power":-5, "workers":7, "consume":{"alloy":1}, "produce":{}, "repair":2},
    "warehouse": {"name":"Складской блок", "tag":"С", "cost":{"alloy":7, "polymer":2}, "power":-1, "workers":2, "consume":{}, "produce":{}, "capacity":0},
    "workshop": {"name":"Полимерная мастерская", "tag":"П", "cost":{"alloy":12, "polymer":3}, "power":-6, "workers":6, "consume":{"ore":2, "fuel":1}, "produce":{"polymer":3}},
    "clinic": {"name":"Медицинский модуль", "tag":"+", "cost":{"alloy":8, "polymer":5}, "power":-3, "workers":6, "consume":{}, "produce":{}, "morale":1},
    "hangar": {"name":"Ангар флота", "tag":"К", "cost":{"alloy":20, "polymer":10}, "power":-5, "workers":5, "consume":{}, "produce":{}},
    "solar": {"name":"Солнечные фермы", "tag":"СЭ", "cost":{"alloy":14, "polymer":5, "silicon":3}, "power":16, "workers":2, "consume":{}, "produce":{}}
}
const TECHS := [
    {"id":"ore_vision", "name":"Геосканирование", "cost":18, "requires":[], "desc":"Разведка расширяет видимость шахты"},
    {"id":"better_drills", "name":"Механические буровые", "cost":28, "requires":["ore_vision"], "desc":"Быстрая добыча рудных пластов"},
    {"id":"logistic_ai", "name":"Автологистика", "cost":34, "requires":[], "desc":"Больше грузов в конвоях и шаттлах"},
    {"id":"hydroponics", "name":"Биорегенерация", "cost":28, "requires":[], "desc":"Фермы производят больше еды"},
    {"id":"shielding", "name":"Корпусные экраны", "cost":40, "requires":["logistic_ai"], "desc":"Меньше износ корпуса станции"},
    {"id":"orbital_mining", "name":"Дистанционная добыча", "cost":42, "requires":["better_drills"], "desc":"+1 добычи всем шахтам колоний"},
    {"id":"alloy_forging", "name":"Улучшенная металлургия", "cost":48, "requires":["better_drills"], "desc":"+1 сплав с каждого завода"},
    {"id":"industrial_ai", "name":"Производственный ИИ", "cost":65, "requires":["logistic_ai","alloy_forging"], "desc":"Ускоренные производства колоний"},
    {"id":"cargo_drones", "name":"Грузовые дроны", "cost":45, "requires":["logistic_ai"], "desc":"Ускоряет рейсы грузовых конвоев"},
    {"id":"fleet_tactics", "name":"Тактика эскадрилий", "cost":54, "requires":["shielding"], "desc":"Корабли сильнее в столкновениях"},
    {"id":"deep_scanners", "name":"Дальние сканеры", "cost":58, "requires":["ore_vision"], "desc":"Снижают риск исследовательских рейсов"},
    {"id":"fusion_cores", "name":"Термоядерные реакторы", "cost":75, "requires":["industrial_ai"], "desc":"Больше энергии и топлива"},
    {"id":"colony_governance", "name":"Колониальные советы", "cost":78, "requires":["industrial_ai"], "desc":"Репутация улучшается от контрактов"},
    {"id":"fleet_repair", "name":"Ремонтные боты", "cost":60, "requires":["fleet_tactics"], "desc":"Ремонт кораблей дешевле"},
    {"id":"fold_drive", "name":"Гравитационный парус", "cost":95, "requires":["shielding", "better_drills"], "desc":"Открывает путь к дальним звёздам"},
    {"id":"stellar_cartography", "name":"Картография рубежа", "cost":110, "requires":["deep_scanners", "fold_drive"], "desc":"Открывает внешние системы"},
    {"id":"generation_habitats", "name":"Корабли поколений", "cost":145, "requires":["fusion_cores","colony_governance"], "desc":"Основа независимого населения"},
    {"id":"singularity", "name":"Ядро перехода", "cost":220, "requires":["stellar_cartography", "generation_habitats"], "desc":"Финальная экспедиция"}
]
const SYSTEMS := [
    {"name":"Орбита Сигма", "x":0.22, "y":0.49, "kind":"home", "faction":"Союз", "ore":"ore", "risk":0},
    {"name":"Бездонный пояс", "x":0.42, "y":0.21, "kind":"asteroid", "faction":"Нейтрал", "ore":"ore", "risk":1},
    {"name":"Лира-8", "x":0.60, "y":0.54, "kind":"trade", "faction":"Консорциум", "ore":"silicon", "risk":1},
    {"name":"Мёртвая звезда", "x":0.78, "y":0.24, "kind":"hazard", "faction":"Рой", "ore":"copper", "risk":3},
    {"name":"Ковчег-9", "x":0.83, "y":0.78, "kind":"goal", "faction":"Неизвестно", "ore":"ice", "risk":2},
    {"name":"Кассандра", "x":0.10, "y":0.16, "kind":"colony", "faction":"Союз", "ore":"ice", "risk":0},
    {"name":"Рубеж-11", "x":0.38, "y":0.77, "kind":"outpost", "faction":"Консорциум", "ore":"copper", "risk":2},
    {"name":"Тёмное облако", "x":0.66, "y":0.08, "kind":"hazard", "faction":"Рой", "ore":"silicon", "risk":4}
]
const LINKS := [[0,1],[0,2],[1,2],[1,3],[2,3],[2,4],[3,4],[0,5],[5,1],[2,6],[6,4],[3,7],[7,4]]
const MARKETS := {"ore":12, "alloy":42, "polymer":54, "food":22, "water":17, "fuel":36, "silicon":41, "copper":27, "ice":19, "components":68}
const CONTRACTS := [
    {"name":"Пайки для беженцев", "resource":"food", "amount":25, "reward":180, "trust":3},
    {"name":"Ремонт колониальной пристани", "resource":"alloy", "amount":20, "reward":320, "trust":2},
    {"name":"Силиконовый проект", "resource":"silicon", "amount":12, "reward":370, "trust":2}
]

## Planetary industry is local. Only convoys move goods to station inventory.
const COLONY_BUILDINGS := {
    "road":{"name":"Транспортная дорога","tag":"=","cost":{"alloy":1},"workers":0,"consume":{},"produce":{}},
    "landing":{"name":"Посадочный терминал","tag":"ПТ","cost":{"alloy":25,"polymer":8},"workers":4,"consume":{},"produce":{}},
    "quarry":{"name":"Рудная шахта","tag":"РД","cost":{"alloy":14,"polymer":4},"workers":7,"consume":{},"produce":{"ore":4}},
    "ice_drill":{"name":"Ледяной бур","tag":"ЛД","cost":{"alloy":12,"polymer":5},"workers":6,"consume":{},"produce":{"ice":4}},
    "silicon_pit":{"name":"Карьер кремния","tag":"КР","cost":{"alloy":17,"polymer":4},"workers":7,"consume":{},"produce":{"silicon":2}},
    "copper_pit":{"name":"Медный рудник","tag":"МР","cost":{"alloy":15,"polymer":5},"workers":8,"consume":{},"produce":{"copper":3}},
    "purifier":{"name":"Очиститель воды","tag":"ОВ","cost":{"alloy":10,"polymer":5},"workers":5,"consume":{"ice":2},"produce":{"water":5}},
    "greenhouse":{"name":"Тепличный комплекс","tag":"ТЛ","cost":{"alloy":13,"polymer":6},"workers":7,"consume":{"water":2},"produce":{"food":6}},
    "foundry":{"name":"Плавильный завод","tag":"ПЗ","cost":{"alloy":18,"polymer":7},"workers":10,"consume":{"ore":5},"produce":{"alloy":3}},
    "assembler":{"name":"Сборочный цех","tag":"СЦ","cost":{"alloy":24,"polymer":9},"workers":10,"consume":{"alloy":2,"silicon":1},"produce":{"components":2}},
    "fuel_lab":{"name":"Топливный завод","tag":"ТЗ","cost":{"alloy":15,"polymer":7},"workers":8,"consume":{"ice":3},"produce":{"fuel":3}},
    "depot":{"name":"Склад колонии","tag":"СК","cost":{"alloy":8,"polymer":3},"workers":2,"consume":{},"produce":{},"storage":160},
    "habitat":{"name":"Купол поселенцев","tag":"ЖК","cost":{"alloy":14,"polymer":9},"workers":0,"consume":{},"produce":{},"capacity":60}
}
const SHIP_TYPES := {
    "scout":{"name":"Разведчик","cost":{"alloy":22,"polymer":12,"components":3},"cargo":14,"attack":6,"defense":5,"speed":2},
    "freighter":{"name":"Грузовоз","cost":{"alloy":38,"polymer":14,"components":6},"cargo":45,"attack":3,"defense":10,"speed":3},
    "escort":{"name":"Эскорт","cost":{"alloy":48,"polymer":22,"components":10},"cargo":9,"attack":20,"defense":18,"speed":2}
}
const FACTION_IDS := ["Союз", "Консорциум", "Рой"]
# Independent faction stock, industrial output and interstellar trade lanes.
# Each faction trades only listed resources. The Swarm is hostile and will not trade.
const FACTION_TRADE := {
    "Союз": {"system":5, "description":"Колониальное содружество · продовольствие и вода",
        "goods":["food","water","alloy","silicon"],
        "production":{"food":9,"water":5}, "consumption":{"alloy":2,"silicon":1},
        "stock":{"food":85,"water":60,"alloy":24,"silicon":8}, "treasury":1800},
    "Консорциум": {"system":6, "description":"Промышленные корпорации · топливо и комплектующие",
        "goods":["alloy","components","fuel","copper"],
        "production":{"fuel":6,"copper":4,"components":2}, "consumption":{"alloy":3},
        "stock":{"alloy":26,"components":20,"fuel":56,"copper":48}, "treasury":2600},
    "Рой": {"system":7, "description":"Автономная машинная экспансия · дипломатия невозможна",
        "goods":[], "production":{}, "consumption":{}, "stock":{}, "treasury":0}
}
const OBJECTIVES := [
    {"name":"Первая промышленная база", "desc":"Постройте три промышленных здания на колониях"},
    {"name":"Галактические маршруты", "desc":"Откройте не менее четырёх систем и выполните три контракта"},
    {"name":"Технологический рывок", "desc":"Исследуйте 10 технологий и основайте вторую колонию"},
    {"name":"Космический рубеж", "desc":"Исследуйте «Ядро перехода» и отправьте экспедицию к Ковчегу-9"}
]

const STORY_EVENTS := [
    {"id":"distress","cycle":12,"title":"Корабль беженцев",
     "text":"На внешней орбите найден транспорт с людьми. В жилых секторах почти нет свободных мест.",
     "options":[
         {"text":"Принять 8 человек", "cost":{"food":12,"water":12},"crew":8,"trust":6},
         {"text":"Отправить припасы", "cost":{"food":10,"credits":45},"reward":{"science":12},"trust":2,"faction":"Союз","relation":5},
         {"text":"Отказать в помощи", "trust":-7,"faction":"Союз","relation":-6}
     ]},
    {"id":"reactor","cycle":24,"title":"Авария реакторного узла",
     "text":"Инженеры обнаружили трещины в охлаждении. Для полной замены узла нужны редкие компоненты.",
     "options":[
         {"text":"Провести капитальный ремонт", "cost":{"alloy":15,"components":4},"hull":18,"trust":3},
         {"text":"Временное укрепление", "cost":{"alloy":5},"hull":5,"trust":-2},
         {"text":"Оставить без ремонта", "hull":-17,"trust":-6}
     ]},
    {"id":"signal","cycle":42,"title":"Непонятный сигнал рубежа",
     "text":"У границы исследованного космоса обнаружен источник древних данных.",
     "options":[
         {"text":"Отправить научную экспедицию", "cost":{"fuel":8,"credits":90},"reward":{"science":65},"trust":2},
         {"text":"Продать координаты Консорциуму", "reward":{"credits":180},"faction":"Консорциум","relation":12,"trust":-3},
         {"text":"Скрыть находку", "reward":{"science":15},"trust":-1}
     ]}
]

static func label_for(id: String) -> String:
    return str(RESOURCE_LABELS.get(id, id))

static func tech_by_id(id: String) -> Dictionary:
    for tech in TECHS:
        if tech["id"] == id:
            return tech
    return {}
