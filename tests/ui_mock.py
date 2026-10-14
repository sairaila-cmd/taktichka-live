"""Страница игры и помощник боя в Chromium на подставных данных (без записи в живую базу).

Ответы Supabase подменяются: таблицы — из фикстур ниже (пример боя из правил),
вызовы api_* — записываются и отвечают «успешно».

  python tests/ui_mock.py [папка_для_снимков]
"""
import functools, http.server, json, pathlib, sys, threading, urllib.parse
from playwright.sync_api import sync_playwright

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
PROPS = json.loads((ROOT / "supabase" / "properties.json").read_text(encoding="utf-8"))
COST = {"Натиск": None, "Добивание": 1, "Лечение": 1, "Всем друг": 0, "Осведомленность": 0, "Шпионаж": 0, "Мобильность": 0}

players = [{"id": 1, "name": "Ведущий", "characters": [], "is_admin": True, "resources": 0, "bonus_squads": 0},
           {"id": 2, "name": "Зои", "characters": ["Зои"], "is_admin": False, "resources": 3, "bonus_squads": 0},
           {"id": 3, "name": "Ратбургер", "characters": ["Ратбургер"], "is_admin": False, "resources": 0, "bonus_squads": 1},
           {"id": 4, "name": "Любомир", "characters": ["Любомир"], "is_admin": False, "resources": 0, "bonus_squads": 2},
           {"id": 5, "name": "Самум", "characters": ["Самум"], "is_admin": False, "resources": 7, "bonus_squads": 0}]
def fig(i, name, nom, s, l, prop): return {"id": i, "name": name, "nominal": nom, "s": s, "l": l, "v": 1, "properties": [prop],
    "owner_label": "", "sources": "", "status": "active"}
figures = [fig(11, "Ладья-натиск", "ладья", 5, 3, "Натиск"), fig(12, "Пешка-добивание", "пешка", 1, 2, "Добивание"),
           fig(13, "Конь-осведомлённый", "конь", 2, 2, "Осведомленность"), fig(21, "Пешка-шпион", "пешка", 3, 1, "Шпионаж"),
           fig(22, "Ладья-лекарь", "ладья", 7, 2, "Лечение"), fig(23, "Офицер «Всем друг»", "офицер", 5, 3, "Всем друг"),
           fig(24, "Резервный конь", "конь", 2, 2, "Мобильность"), fig(25, "Выбывший пёс", "пешка", 4, 4, "Мобильность")]
T = {
    "players": players,
    "properties": [{"name": p["name"], "phase": p["phase"], "description": p["description"], "cost": COST.get(p["name"], 0), "cost_note": None} for p in PROPS],
    "nominals": [{"name": n, "rank": r, "max_per_strategist": m} for n, r, m in
                 [("король", 6, 1), ("ферзь", 5, 1), ("ладья", 4, 2), ("офицер", 3, 2), ("конь", 2, 2), ("пешка", 1, 8)]],
    "figures": figures,
    "figure_owners": [{"figure_id": f, "player_id": 2} for f in (11, 12, 13)] + [{"figure_id": f, "player_id": 3} for f in (21, 22, 23, 24, 25)],
    "games": [{"id": 1, "title": "Пять ликов одной Луны", "starts_at": "2026-10-20T16:00:00Z", "status": "running"}],
    "game_gifts": [{"game_id": 1, "gift": g} for g in ("alaya", "belaya", "chernaya", "gorkaya")],
    "strategists": [{"id": 1, "game_id": 1, "wallet": None, "invited": None, "initiative": 10},
                    {"id": 2, "game_id": 1, "wallet": 6, "invited": None, "initiative": 4}],
    "strategist_members": [{"strategist_id": 1, "game_id": 1, "player_id": 2}, {"strategist_id": 2, "game_id": 1, "player_id": 3},
                           {"strategist_id": 2, "game_id": 1, "player_id": 4}],
    "squads": [{"id": 1, "game_id": 1, "strategist_id": 1, "name": "Волки", "name_key": "волки", "destroyed": False, "dead_figure": None, "rage": 1},
               {"id": 2, "game_id": 1, "strategist_id": 2, "name": "Совы", "name_key": "совы", "destroyed": False, "dead_figure": None, "rage": 0, "echo_id": 1},
               {"id": 3, "game_id": 1, "strategist_id": 2, "name": "Запас", "name_key": "запас", "destroyed": False, "dead_figure": None, "rage": 0},
               {"id": 4, "game_id": 1, "strategist_id": 2, "name": "Павшие", "name_key": "павшие", "destroyed": True, "dead_figure": None, "rage": 0}],
    "squad_figures": [{"squad_id": 1, "figure_id": f, "game_id": 1, "strategist_id": 1, "state": "ok", "borrowed": False} for f in (11, 12, 13)] +
                     [{"squad_id": 2, "figure_id": f, "game_id": 1, "strategist_id": 2, "state": "ok", "borrowed": False} for f in (21, 22, 23)] +
                     [{"squad_id": 3, "figure_id": 24, "game_id": 1, "strategist_id": 2, "state": "damaged", "borrowed": False}],
    "squad_totals": [{"squad_id": 1, "game_id": 1, "strategist_id": 1, "name": "Волки", "destroyed": False, "s": 8, "l": 7, "v": 3},
                     {"squad_id": 2, "game_id": 1, "strategist_id": 2, "name": "Совы", "destroyed": False, "s": 15, "l": 6, "v": 3},
                     {"squad_id": 3, "game_id": 1, "strategist_id": 2, "name": "Запас", "destroyed": False, "s": 2, "l": 2, "v": 1}],
    "squad_moon": [{"squad_id": 1, "game_id": 1, "white_streak": False, "duplicate_nominals": 0},
                   {"squad_id": 2, "game_id": 1, "white_streak": False, "duplicate_nominals": 0}],
    "turns": [{"id": 1, "game_id": 1, "number": 2, "phase": "actions", "tacts": 2, "tact": 1, "current_strategist": 1}],
    "squad_moves": [{"turn_id": 1, "squad_id": 3, "strategist_id": 2, "tact": 1, "action": "Перемещение", "movement": "Перемещение", "act": None},
                    {"turn_id": 1, "squad_id": 2, "strategist_id": 2, "tact": 1, "action": "Нападение", "movement": None, "act": "Нападение"}],
    "battles": [{"id": 1, "game_id": 1, "attacker": 1, "defender": 2, "status": "open", "winner": None, "result": None, "opened_by": 2, "created_at": "2026-10-20T17:00:00Z"}],
    "battle_actions": [
        {"id": 1, "battle_id": 1, "kind": "property", "squad_id": 2, "figure_id": 23, "property": "Всем друг", "params": {"phase": "Условие"}, "roll": None, "cost": 0},
        {"id": 2, "battle_id": 1, "kind": "property", "squad_id": 1, "figure_id": 13, "property": "Осведомленность", "params": {"phase": "Сила"}, "roll": None, "cost": 0},
        {"id": 3, "battle_id": 1, "kind": "roll", "squad_id": 2, "figure_id": None, "property": None, "params": {"purpose": "risk"}, "roll": 3, "cost": 0, "manual": False},
        {"id": 4, "battle_id": 1, "kind": "roll", "squad_id": 1, "figure_id": None, "property": None, "params": {"purpose": "risk"}, "roll": 10, "cost": 0, "manual": False}],
    "echoes_public": [{"id": 1, "game_id": 1, "name": "Святилище", "description": "Подкуп и Плен не работают.", "status": "active",
                       "end_condition": "до конца игры", "blocked_properties": ["Подкуп", "Плен"], "move_cost": 0}],
    "events": [{"id": 1, "at": "2026-10-20T16:05:00Z", "actor": 2, "kind": "intrigue", "game_id": 1, "figure_id": None, "squad_id": None,
                "player_id": None, "amount": 2, "data": {"label": "Зои", "strategist": 1}, "comment": "Слухи о предателе", "reverted": False},
               {"id": 2, "at": "2026-10-20T16:10:00Z", "actor": 3, "kind": "squad_move", "game_id": 1, "figure_id": None, "squad_id": 3,
                "player_id": None, "amount": 2, "data": {"action": "Перемещение", "tact": 1}, "comment": None, "reverted": False},
               {"id": 3, "at": "2026-10-20T15:00:00Z", "actor": 1, "kind": "squad_save", "game_id": 1, "figure_id": None, "squad_id": 3,
                "player_id": None, "amount": None, "data": {"name": "Запас", "figures": [25]}, "comment": None, "reverted": False},
               {"id": 4, "at": "2026-10-20T17:05:00Z", "actor": 1, "kind": "figure_state", "game_id": 1, "figure_id": 11, "squad_id": 1,
                "player_id": None, "amount": None, "data": {"from": "ok", "to": "damaged"}, "comment": "Бой #1", "reverted": False}],
    "figure_conflicts": [], "trophies": [{"id": 1, "name": "Знамя", "description": "+2 к Силе", "bonus_s": 2, "bonus_l": 0, "bonus_v": 0, "squad_id": 2, "holder": None, "status": "active"}],
}
calls = []

def filt(rows, qs):
    out = rows
    for k, vals in qs.items():
        if k in ("select", "order", "limit", "offset"): continue
        v = vals[0]
        def ok(r, k=k, v=v):
            if k not in r: return True
            x = r[k]
            if v.startswith("eq."): return str(x).lower() == v[3:].lower()
            if v.startswith("neq."): return str(x) != v[4:]
            if v.startswith("in."): return str(x) in v[4:-1].split(",")
            if v.startswith("gt."): return x is not None and float(x) > float(v[3:])
            if v.startswith("not.is."): return x is not None
            if v.startswith("is.null"): return x is None
            return True
        out = [r for r in out if ok(r)]
    return out

def handle(route):
    req = route.request
    u = urllib.parse.urlparse(req.url)
    path = u.path.split("/rest/v1/")[-1]
    if path.startswith("rpc/"):
        fn = path[4:]
        body = json.loads(req.post_data or "{}")
        calls.append((fn, body))
        admin = body.get("p_code") == "admin-test"
        rat = body.get("p_code") == "rat-test"
        result = {"api_whoami": {"id": 1, "name": "Ведущий", "characters": [], "is_admin": True} if admin else
                  {"id": 3, "name": "Ратбургер", "characters": ["Ратбургер"], "is_admin": False} if rat else
                  {"id": 2, "name": "Зои", "characters": ["Зои"], "is_admin": False},
                  "api_admin_echoes": [dict(e) for e in T["echoes_public"]]}.get(fn)
        if fn == "api_roll": result = 7
        return route.fulfill(status=200, content_type="application/json", body=json.dumps(result))
    rows = filt(T.get(path, []), urllib.parse.parse_qs(u.query))
    route.fulfill(status=200, content_type="application/json", body=json.dumps(rows, ensure_ascii=False))

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(ROOT)))
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}/index.html"
errors, ok, fail = [], 0, 0
def check(name, cond, info=""):
    global ok, fail
    if cond: ok += 1; print("  ✓", name)
    else: fail += 1; print("  ✗", name, info)

with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 1280, "height": 1000})
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: m.type == "error" and "WebSocket" not in m.text and "realtime" not in m.text.lower() and errors.append(m.text))
    page.route("**/rest/v1/**", handle)
    page.route("**/realtime/**", lambda r: r.abort())

    # вход Зои (подставной)
    page.add_init_script("localStorage.setItem('taktichka.code', 'zoi-test')")

    print("Страница игры")
    page.goto(BASE + "#/game/1")
    page.wait_for_selector("text=Отряды", timeout=20000)
    txt = page.locator("#view").inner_text()
    check("название игры", "Пять ликов одной Луны" in txt)
    check("ход 2, такт 1 из 2 (Чёрная луна)", "Ход 2" in txt and "такт 1 из 2" in txt)
    check("сейчас ходит Зои", "Сейчас ходит: Зои" in txt)
    check("интрига хода видна", "Слухи о предателе" in txt)
    check("Ярость Волков", "Ярость 1" in txt)
    check("Эхо «Святилище» видно", "Святилище" in txt and "Не работают: Подкуп, Плен" in txt)
    check("ход «Запаса»: только движение, ход не закончен, при Чёрной луне — с номером такта", "ход: Перемещение … (такт 1)" in txt)
    check("Совы стоят в Эхо «Святилище»", "в Эхо «Святилище»" in txt and "Здесь стоят: «Совы»" in txt)
    mine = page.locator("section.card:has(h2:has-text(\"Моё участие\"))")
    check("в «Моём участии» видны свои отряды с кнопками", mine.locator(".squad:has-text(\"Волки\")").count() == 1 and mine.locator("button:has-text(\"Ход\")").count() == 1)
    check("бой в списке", "«Волки» → «Совы»" in txt)
    def frame(name):
        cls = page.locator(f".squads .squad:has(.name:text-is('{name}'))").first.get_attribute("class")
        return next((c[3:] for c in cls.split() if c.startswith("st-")), None)
    frames = {n: frame(n) for n in ("Волки", "Совы", "Запас", "Павшие")}
    check("рамки: Волки зелёная, Совы жёлтая, Запас синяя (ждёт череда), Павшие красная",
          frames == {"Волки": "active", "Совы": "done", "Запас": "waiting", "Павшие": "destroyed"}, frames)
    page.locator(".squads .squad:has(.name:text-is('Волки')) a:has-text('Ладья-натиск')").first.click()
    page.wait_for_selector("dialog[open] h2:has-text('Ладья-натиск')", timeout=10000)
    dlg = page.locator("dialog").inner_text()
    check("окно фигуры открылось на странице игры, адрес не сменился", page.evaluate("location.hash") == "#/game/1")
    check("в истории фигуры — название отряда", "в отряде «Волки»" in dlg, dlg[-200:])
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    check("после закрытия — снова страница игры", page.evaluate("location.hash") == "#/game/1" and page.locator("text=Статистика игры").count() == 1)
    stats = page.locator("section.card:has(h2:has-text('Статистика игры'))")
    st = stats.inner_text()
    check("статистика: 8 фигур (7 сейчас + 1 выбывшая)", "8\nфигур в отрядах (сейчас и раньше)" in st, st[:120])
    check("статистика: «выбыла из отряда» = 1", "1\nвыбыла из отряда" in st)
    check("статистика: состояние «повреждена» = 1", "1\nповреждена" in st)
    check("статистика: графики нарисованы", stats.locator("svg").count() >= 5, stats.locator("svg").count())
    if SHOTS: stats.screenshot(path=str(SHOTS / "stats.png"))
    check("статистика стоит перед журналом", page.evaluate("""() => { const hs = [...document.querySelectorAll('#view h2')].map(h => h.textContent);
      return hs.indexOf('Статистика игры') === hs.indexOf('Журнал игры') - 1; }"""))
    volki = page.locator("section.card:has(h2:has-text('Моё участие')) .squad:has-text('Волки')")
    check("Зои в свой черёд: «Ход» у Волков активен", volki.locator("button:has-text('Ход')").is_enabled())
    check("у Зои есть кнопки отряда (в «Моём участии» и в общем списке)", page.locator("button:has-text('Напасть')").count() == 2)
    if SHOTS: page.screenshot(path=str(SHOTS / "game.png"), full_page=True)
    page.click("button:has-text('Ход') >> nth=0")
    page.wait_for_selector("dialog[open]")
    opts = page.locator("dialog select >> nth=0").locator("option").all_inner_texts()
    check("в окне хода сначала движение", any("Перемещение" in o for o in opts) and not any("Нападение" == o for o in opts), opts)
    check("в окне хода есть «Эхо по пути»", page.locator("dialog").inner_text().count("Эхо по пути") == 1)
    page.click("dialog button:has-text('Записать')")
    page.wait_for_timeout(500)
    check("после действия нет уведомления об ошибке", page.locator(".toast.error").count() == 0,
          page.locator(".toast.error").all_inner_texts())
    check("ход отряда уходит в api_squad_move", any(c[0] == "api_squad_move" and c[1].get("p_squad") == 1 for c in calls), calls[-1:])

    print("\nПомощник боя (пример из правил, после бросков)")
    page.goto(BASE + "#/battle/1")
    page.wait_for_selector("text=Очередь фигур", timeout=20000)
    txt = page.locator("#view").inner_text()
    check("Сила 13 и 17 (15 + трофей «Знамя» +2)", page.locator(".side.attacker .power").inner_text() == "13" and page.locator(".side.defender .power").inner_text() == "17")
    check("кубики 10 и 3", page.locator(".side.attacker .die").inner_text() == "10" and page.locator(".side.defender .die").inner_text() == "3")
    check("ходит пешка со Шпионажем", "Ход фигуры" in txt and "Пешка-шпион" in txt)
    check("Зои (нападающая) не решает за Сов", "Решает Ратбургер" in txt)
    check("Натиск недоступен из-за «Всем друг»", "«Всем друг» противника" in txt)
    check("трофей Сов +2 учтён", "трофеи" in page.locator(".side.defender").inner_text())
    if SHOTS: page.screenshot(path=str(SHOTS / "battle.png"), full_page=True)

    # шаг вперёд: Шпионаж применён, переброс 9 → ждём, что Совы выберут повреждение
    T["battle_actions"].append({"id": 5, "battle_id": 1, "kind": "property", "squad_id": 2, "figure_id": 21, "property": "Шпионаж",
                                "params": {"phase": "Риск"}, "roll": 9, "cost": 0})
    page.evaluate("window.dispatchEvent(new Event('taktichka:refresh'))")
    page.wait_for_selector("text=Проигравший выбирает", timeout=10000)
    txt = page.locator("#view").inner_text()
    check("после Шпионажа: победа Волков 22 против 20", "Победил «Волки»" in txt)
    check("кубик Волков теперь 9 (было 10)", page.locator(".side.attacker .die").inner_text() == "9")
    if SHOTS: page.screenshot(path=str(SHOTS / "battle-damage.png"), full_page=True)

    print("\nРатбургер не в свой черёд")
    page.evaluate("localStorage.setItem('taktichka.code', 'rat-test')")
    page.add_init_script("localStorage.setItem('taktichka.code', 'rat-test')")
    page.goto(BASE + "#/game/1"); page.reload()
    page.wait_for_selector("text=Моё участие", timeout=20000)
    sovy = page.locator("section.card:has(h2:has-text('Моё участие')) .squad:has-text('Совы')")
    disabled = [n for n in ("Ход", "Напасть", "Свойство", "Обмен", "Оплатить", "Эхо") if not sovy.locator(f"button:has-text('{n}')").first.is_enabled()]
    check("у Ратбургера серые Ход, Напасть, Свойство, Обмен, Оплатить, Эхо", len(disabled) == 6, disabled)
    check("…и активна «Состояние фигур»", sovy.locator("button:has-text('Состояние фигур')").is_enabled())
    check("подсказка «Сейчас ходит Зои»", sovy.locator("button:has-text('Ход')").get_attribute("title") == "Сейчас ходит Зои")
    check("у Ратбургера те же рамки", frame("Волки") == "active" and frame("Совы") == "done")
    if SHOTS: sovy.screenshot(path=str(SHOTS / "rat-squad.png"))

    print("\nВедущий на странице игры")
    page.evaluate("localStorage.setItem('taktichka.code', 'admin-test')")
    page.add_init_script("localStorage.setItem('taktichka.code', 'admin-test')")
    page.goto(BASE + "#/game/1"); page.reload()
    page.wait_for_selector("text=Ведущему", timeout=20000)
    check("у ведущего те же рамки", frame("Волки") == "active" and frame("Павшие") == "destroyed")
    check("кнопка «Добавить стратега…»", page.locator("button:has-text('Добавить стратега')").count() == 1)
    check("«+ Отряд» у каждого стратега", page.locator("button:has-text('+ Отряд')").count() == 2)
    check("ведущий может изменить отряд в идущей игре", page.locator("button:has-text('Изменить')").count() >= 3)
    check("у ведущего «Ход» Запаса активен (не его черёд — ведущему можно)", page.locator(".squads .squad:has(.name:text-is('Запас')) button:has-text('Ход')").first.is_enabled())
    page.click("button:has-text('+ Отряд') >> nth=1")
    page.wait_for_selector("dialog[open]")
    dt = page.locator("dialog").inner_text()
    check("окно сборки за Ратбургера, есть «показать все фигуры»", "Ратбургер" in dt and "показать все фигуры" in dt, dt[:120])
    page.click("dialog button:has-text('Сохранить отряд')")
    page.wait_for_timeout(500)
    sv = [c for c in calls if c[0] == "api_squad_save"]
    check("отряд сохраняется за стратега Ратбургера", sv and sv[-1][1].get("p_strategist") == 2, sv[-1:] if sv else None)
    page.keyboard.press("Escape")
    page.click("button:has-text('Эхо') >> nth=0")
    page.wait_for_selector("dialog[open] >> text=Эхо занимает часть карты", timeout=10000)
    check("окно «Эхо» у отряда открывается (ведущий видит список)", page.locator("dialog select").count() >= 1)
    page.keyboard.press("Escape")
    if SHOTS: page.screenshot(path=str(SHOTS / "game-admin.png"), full_page=True)

    # закрытый бой: кнопка «Вернуться к игре»
    T["battles"][0].update(status="closed", winner=1, result={"reason": "Сила + кубик", "totals": {"attacker": 22, "defender": 20}})
    page.goto(BASE + "#/battle/1")
    page.wait_for_selector("text=Итог боя", timeout=10000)
    check("после боя есть кнопка «Вернуться к игре»", page.locator("button:has-text('Вернуться к игре')").count() == 1)
    page.click("button:has-text('Вернуться к игре')")
    page.wait_for_selector("text=Статистика игры", timeout=20000)
    check("кнопка ведёт на страницу игры", page.evaluate("location.hash") == "#/game/1")
    T["battles"][0].update(status="open", winner=None, result=None)
    print("\nПерсонажи — по текущей игре")
    page.goto(BASE + "#/people")
    page.wait_for_selector("text=Стратеги и Ресурсы", timeout=20000)
    rows_ = page.locator("section.card:has(h2:has-text('Стратеги и Ресурсы')) tbody tr").all_inner_texts()
    check("две строки стратегов, пара одной строкой", len(rows_) == 2 and any(r.startswith("Ратбургер и Любомир") for r in rows_), rows_)
    pair = next((r for r in rows_ if r.startswith("Ратбургер и Любомир")), "")
    cells = [c.strip() for c in pair.split("\t")]
    check("у пары — общий кошелёк 6, 3 отряда, 4 фигуры, доп. отряды по большему (2)", cells[1:5] == ["6 общий кошелёк", "3", "4", "2"], cells)
    check("не участвующие — в свёрнутом блоке (Самум)", "Не участвуют в этой игре (1)" in page.locator("#view").inner_text())
    print("\nТелефон")
    page.set_viewport_size({"width": 390, "height": 844})
    page.goto(BASE + "#/game/1")
    page.wait_for_selector("text=Отряды", timeout=20000)
    check("страница игры без горизонтальной прокрутки", page.evaluate("document.documentElement.scrollWidth") <= 390,
          page.evaluate("document.documentElement.scrollWidth"))
    page.goto(BASE + "#/battle/1")
    page.wait_for_selector("text=Очередь фигур", timeout=20000)
    check("бой без горизонтальной прокрутки", page.evaluate("document.documentElement.scrollWidth") <= 390,
          page.evaluate("document.documentElement.scrollWidth"))
    if SHOTS: page.screenshot(path=str(SHOTS / "battle-phone.png"), full_page=False)
    b.close()
srv.shutdown()
print("\nошибки в консоли:" if errors else "\nошибок в консоли нет", *errors, sep="\n  ")
print(f"Итого: {ok} ✓, {fail} ✗")
sys.exit(1 if fail or errors else 0)
