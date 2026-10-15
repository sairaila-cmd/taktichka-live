"""Подставной Supabase для проверок в Chromium: таблицы из фикстур, вызовы api_* записываются.

Используют tests/ui_mock.py и tests/ui_flows.py. В живую базу ничего не уходит.

  T      — таблицы (меняются на месте прямо в проверке; reset() возвращает исходные)
  calls  — [(имя api_*, тело запроса)] по порядку
  FAIL   — {"api_…": "текст"}: вызов ответит ошибкой базы с этим текстом
  FAIL_STATUS — {"api_…": {"status": код, "code": код, "message": текст}}: HTTP/API ошибка
  RESULT — {"api_…": значение}: что вернёт вызов (по умолчанию null)
Коды входа: admin-test — Ведущий, rat-test — Ратбургер, lub-test — Любомир,
samum-test — Самум, bad-code — «Неверный код»; любой другой — Зои.
"""
import copy, functools, http.server, json, pathlib, threading, urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROPS = json.loads((ROOT / "supabase" / "properties.json").read_text(encoding="utf-8"))
COST = {"Натиск": None, "Добивание": 1, "Лечение": 1, "Всем друг": 0, "Осведомленность": 0, "Шпионаж": 0, "Мобильность": 0}

players = [{"id": 1, "name": "Ведущий", "characters": [], "is_admin": True, "resources": 0, "bonus_squads": 0},
           {"id": 2, "name": "Зои", "characters": ["Зои"], "is_admin": False, "resources": 3, "bonus_squads": 0},
           {"id": 3, "name": "Ратбургер", "characters": ["Ратбургер"], "is_admin": False, "resources": 0, "bonus_squads": 1},
           {"id": 4, "name": "Любомир", "characters": ["Любомир"], "is_admin": False, "resources": 0, "bonus_squads": 2},
           {"id": 5, "name": "Самум", "characters": ["Самум"], "is_admin": False, "resources": 7, "bonus_squads": 0}]
def fig(i, name, nom, s, l, prop): return {"id": i, "name": name, "nominal": nom, "s": s, "l": l, "v": 1, "properties": [prop],
    "owner_label": "", "sources": "", "status": "active"}
figures = [dict(fig(11, "Ладья-натиск", "ладья", 5, 3, "Натиск"), sources="Фури"),
           dict(fig(12, "Пешка-добивание", "пешка", 1, 2, "Добивание"), sources="Фури; Storm Heist"),
           fig(13, "Конь-осведомлённый", "конь", 2, 2, "Осведомленность"),
           dict(fig(21, "Пешка-шпион", "пешка", 3, 1, "Шпионаж"), sources="Storm Heist; 182/8"),
           fig(22, "Ладья-лекарь", "ладья", 7, 2, "Лечение"), fig(23, "Офицер «Всем друг»", "офицер", 5, 3, "Всем друг"),
           fig(24, "Резервный конь", "конь", 2, 2, "Мобильность"), fig(25, "Выбывший пёс", "пешка", 4, 4, "Мобильность")]
BASE = {
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
T = copy.deepcopy(BASE)
calls = []
read_calls = []
FAIL = {}
FAIL_STATUS = {}
RESULT = {}
WHO = {"admin-test": 1, "rat-test": 3, "lub-test": 4, "samum-test": 5}


def reset():
    """Вернуть таблицы к исходным, очистить журнал вызовов и подставленные ответы."""
    T.clear(); T.update(copy.deepcopy(BASE))
    calls.clear(); read_calls.clear(); FAIL.clear(); FAIL_STATUS.clear(); RESULT.clear()


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


def whoami(code):
    pid = WHO.get(code, 2)
    p = next(x for x in T["players"] if x["id"] == pid)
    return {k: p[k] for k in ("id", "name", "characters", "is_admin")}


def error(route, message):
    route.fulfill(status=400, content_type="application/json",
                  body=json.dumps({"code": "P0001", "message": message, "details": None, "hint": None}, ensure_ascii=False))


def handle(route):
    req = route.request
    u = urllib.parse.urlparse(req.url)
    path = u.path.split("/rest/v1/")[-1]
    if path.startswith("rpc/"):
        fn = path[4:]
        body = json.loads(req.post_data or "{}")
        calls.append((fn, body))
        if fn == "api_whoami" and body.get("p_code") == "bad-code":
            return error(route, "Неверный код")
        if fn in FAIL_STATUS:
            failure = FAIL_STATUS[fn]
            return route.fulfill(status=failure["status"], content_type="application/json",
                                 body=json.dumps({"code": failure["code"], "message": failure["message"],
                                                  "details": None, "hint": None}, ensure_ascii=False))
        if fn in FAIL:
            return error(route, FAIL[fn])
        if fn in RESULT: result = RESULT[fn]
        elif fn == "api_whoami": result = whoami(body.get("p_code"))
        elif fn == "api_admin_echoes": result = [dict(e) for e in T["echoes_public"] if e.get("game_id") == body.get("p_game", 1)]
        elif fn == "journal_page":
            result = sorted(T["events"], key=lambda e: (e["at"], e["id"]), reverse=True)
            if body.get("p_before_at") is not None:
                cursor = (body["p_before_at"], body["p_before_id"])
                result = [e for e in result if (e["at"], e["id"]) < cursor]
            result = result[:min(body["p_limit"], 1000)]
        elif fn == "api_roll": result = 7
        else: result = None
        return route.fulfill(status=200, content_type="application/json", body=json.dumps(result, ensure_ascii=False))
    if req.method == "GET":
        read_calls.append(path)
    qs = urllib.parse.parse_qs(u.query)
    rows = filt(T.get(path, []), qs)
    # Supabase caps responses at 1000 rows; range/limit pagination follows fixture order.
    start = int(qs.get("offset", ["0"])[0])
    limit = min(int(qs.get("limit", ["1000"])[0]), 1000)
    rows = rows[start:start + limit]
    route.fulfill(status=200, content_type="application/json", body=json.dumps(rows, ensure_ascii=False))


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass


def serve():
    """Раздать папку сайта на свободном порту; вернуть (сервер, адрес index.html)."""
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(ROOT)))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_port}/index.html"


def attach(page, errors):
    """Подменить Supabase для страницы и собирать ошибки консоли (кроме Realtime)."""
    page.on("pageerror", lambda e: errors.append(str(e)))
    def on_console(message):
        if message.type != "error" or "WebSocket" in message.text or "realtime" in message.text.lower():
            return
        if "status of 400" in message.text:
            return
        if "status of 503" in message.text and any(failure["status"] == 503 for failure in FAIL_STATUS.values()):
            return
        errors.append(message.text)
    page.on("console", on_console)
    page.route("**/rest/v1/**", handle)
    page.route("**/realtime/**", lambda r: r.abort())


class Checks:
    def __init__(self): self.ok = 0; self.fail = 0; self.failed = []
    def __call__(self, name, cond, info=""):
        if cond: self.ok += 1; print("  ✓", name)
        else: self.fail += 1; self.failed.append(name); print("  ✗", name, info)
