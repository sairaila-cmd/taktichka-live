"""Проверка schema.sql на локальном Postgres (pgserver): загрузка + сценарии из плана."""
import sys, tempfile, pathlib, traceback
import pgserver, psycopg2
sys.stdout.reconfigure(encoding='utf-8')

SCHEMA = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
tmp = tempfile.mkdtemp(prefix="pgt")
srv = pgserver.get_server(tmp, cleanup_mode="stop")
uri = srv.get_uri()

admin = psycopg2.connect(uri); admin.autocommit = True
cur = admin.cursor()
# заглушки Supabase
cur.execute("create role anon nologin; create role authenticated nologin;")
cur.execute("create publication supabase_realtime;")
# как в Supabase: anon по умолчанию получает все права на таблицы и функции, защищает только RLS
cur.execute("""grant usage on schema public to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant all on sequences to anon, authenticated;
  alter default privileges in schema public grant execute on functions to anon, authenticated;""")
cur.execute(SCHEMA)
print("схема загружена")

# данные: игроки и коды
cur.execute("""
insert into players (name, characters, is_admin, resources, bonus_squads) values
 ('Админ', '{Ведущий}', true, 0, 0),
 ('Аня', '{Зои}', false, 5, 0),
 ('Боря', '{Ратбургер}', false, 3, 1),
 ('Вера', '{Пятая}', false, 2, 0),
 ('Гоша', '{Ржавый}', false, 0, 2);
insert into player_codes select id, hash_code(lower(name) || '-code') from players;
insert into properties (name, phase, description, cost) values
 ('Натиск','Сила','',null), ('Добивание','Ущерб','',1), ('Осведомленность','Сила','',0),
 ('Шпионаж','Риск','',0), ('Лечение','Ущерб','',1), ('Всем друг','Условие','',0),
 ('Воротила','Перемещение','',0), ('Мобильность','Перемещение','',0);
""")

# запросы — от роли anon, как из браузера
c = psycopg2.connect(uri); c.autocommit = True
q = c.cursor()
q.execute("set role anon")

ok = fail = 0
def call(fn, *args):
    if fn == "api_squad_save" and len(args) == 5: args = args + (None,)
    q.execute(f"select {fn}({', '.join(['%s'] * len(args))})", args)
    return q.fetchone()[0]

def expect_ok(name, fn, *args):
    global ok, fail
    try:
        r = call(fn, *args); ok += 1; print(f"  ✓ {name}"); return r
    except Exception as e:
        fail += 1; print(f"  ✗ {name}: ожидался успех, а {str(e).splitlines()[0]}")

def expect_err(name, fn, *args, contains=""):
    global ok, fail
    try:
        call(fn, *args); fail += 1; print(f"  ✗ {name}: ожидался отказ, а прошло")
    except Exception as e:
        msg = str(e).splitlines()[0]
        if contains and contains not in msg:
            fail += 1; print(f"  ✗ {name}: отказ, но не тот: {msg}")
        else:
            ok += 1; print(f"  ✓ {name} → {msg}")

def sql(s, *a):
    q.execute(s, a); return q.fetchall()

A, ANYA, BORYA, VERA, GOSHA = "админ-code", "аня-code", "боря-code", "вера-code", "гоша-code"

print("\nДоступ")
expect_err("прямой INSERT от anon", "(select 1 from (select 1) x where false)") if False else None
try:
    q.execute("insert into figures (name, nominal, s, l, v) values ('x','пешка',1,1,1)"); fail += 1; print("  ✗ прямой INSERT прошёл")
except Exception as e:
    ok += 1; print("  ✓ прямой INSERT запрещён →", str(e).splitlines()[0])
try:
    q.execute("select * from player_codes"); rows = q.fetchall()
    if rows: fail += 1; print("  ✗ хэши кодов видны");
    else: ok += 1; print("  ✓ хэши кодов не видны (0 строк)")
except Exception as e:
    ok += 1; print("  ✓ хэши кодов закрыты →", str(e).splitlines()[0])
try:
    q.execute("select hash_code('x')"); fail += 1; print("  ✗ служебная функция доступна")
except Exception as e:
    ok += 1; print("  ✓ служебные функции закрыты")
expect_err("неверный код", "api_whoami", "nope", contains="Неверный код")
expect_ok("вход по коду", "api_whoami", ANYA)

print("\nФигуры")
fig = {}
def add(code, name, nom, s, l, v, props):
    fig[name] = expect_ok(f"добавить {name}", "api_figure_add", code, name, nom, s, l, v, props, "тест", None)
add(ANYA, "Ладья-натиск", "ладья", 5, 3, 2, ["Натиск"])
add(ANYA, "Пешка-добивание", "пешка", 1, 2, 1, ["Добивание"])
add(ANYA, "Конь-осведомленность", "конь", 2, 4, 2, ["Осведомленность"])
add(BORYA, "Пешка-шпионаж", "пешка", 3, 1, 1, ["Шпионаж"])
add(BORYA, "Ладья-лечение", "ладья", 7, 5, 2, ["Лечение"])
add(BORYA, "Офицер-всем-друг", "офицер", 5, 6, 2, ["Всем друг"])
add(ANYA, "Ферзь-1", "ферзь", 6, 6, 6, ["Мобильность"])
add(ANYA, "Ферзь-2", "ферзь", 6, 6, 6, ["Мобильность"])
add(ANYA, "Пешка-воротила", "пешка", 1, 1, 1, ["Воротила"])
add(VERA, "Ладья-В1", "ладья", 4, 4, 4, ["Мобильность"])
add(VERA, "Ладья-В2", "ладья", 4, 4, 4, ["Мобильность"])
add(GOSHA, "Ладья-Г1", "ладья", 4, 4, 4, ["Мобильность"])
expect_err("править чужую", "api_figure_edit", BORYA, fig["Ферзь-1"], "Ферзь-1", "ферзь", 9, 9, 9, ["Мобильность"], None, contains="не ваша")
expect_ok("править свою", "api_figure_edit", ANYA, fig["Ферзь-1"], "Ферзь-1", "ферзь", 6, 6, 7, ["Мобильность"], None)
expect_err("передать чужую", "api_figure_transfer", BORYA, fig["Ферзь-2"], None, 3, None)
expect_ok("отметить применение", "api_figure_use", ANYA, fig["Ферзь-1"], None, "Шрам", None)

print("\nРесурсы")
expect_err("передать больше баланса", "api_resources_transfer", VERA, 2, 10, None, contains="Не хватает")
expect_err("передать 0", "api_resources_transfer", VERA, 2, 0, None, contains="больше нуля")
expect_ok("передать 1", "api_resources_transfer", VERA, 2, 1, None)
expect_err("начислить не-админом", "api_admin_resources", ANYA, 2, 100, None, contains="ведущего")
expect_ok("начислить админом", "api_admin_resources", A, 4, 2, None)

print("\nИгра и отряды")
g = expect_ok("создать игру", "api_admin_game", A, None, "Тестовая", None, "draft")
s1 = expect_ok("отряд Ани", "api_squad_save", ANYA, g, None, "Волки", [fig["Ладья-натиск"], fig["Пешка-добивание"], fig["Конь-осведомленность"]])
add(ANYA, "Пешка-запас", "пешка", 1, 1, 1, ["Мобильность"]); add(ANYA, "Конь-запас", "конь", 1, 1, 1, ["Мобильность"])
expect_err("4 фигуры", "api_squad_save", ANYA, g, None, "Лишние", [fig["Ферзь-1"], fig["Пешка-запас"], fig["Пешка-воротила"], fig["Конь-запас"]], contains="от 1 до 3")
expect_err("2 ферзя", "api_squad_save", ANYA, g, None, "Ферзи", [fig["Ферзь-1"], fig["Ферзь-2"]], contains="ферзь")
expect_err("пустой отряд", "api_squad_save", ANYA, g, None, "Пусто", [], contains="от 1 до 3")
expect_err("чужая фигура", "api_squad_save", ANYA, g, None, "Чужие", [fig["Пешка-шпионаж"]], contains="не принадлежит")
expect_err("та же фигура в двух отрядах", "api_squad_save", ANYA, g, None, "Дубль", [fig["Ладья-натиск"]], contains="другом вашем отряде")
expect_err("название « волки » занято", "api_squad_save", ANYA, g, None, "  ВОЛКИ ", [fig["Ферзь-1"]], contains="уже занято")
expect_err("пустое название", "api_squad_save", ANYA, g, None, "  ", [fig["Ферзь-1"]], contains="название")
s1b = expect_ok("второй отряд Ани", "api_squad_save", ANYA, g, None, "Ферзевые", [fig["Ферзь-1"], fig["Пешка-воротила"]])
expect_err("третий отряд без бонуса", "api_squad_save", ANYA, g, None, "Третий", [fig["Ферзь-2"]], contains="Отрядов больше")
s2 = expect_ok("отряд Бори", "api_squad_save", BORYA, g, None, "Совы", [fig["Пешка-шпионаж"], fig["Ладья-лечение"], fig["Офицер-всем-друг"]])
expect_ok("2-й отряд Бори", "api_squad_save", BORYA, g, None, "Совы-2", [fig["Ладья-лечение"]]) if False else None

print("\nНапарники")
expect_ok("Вера зовёт Гошу", "api_partner_invite", VERA, g, 5)
expect_err("Аня принимает чужое приглашение", "api_partner_accept", ANYA, g, 4, contains="Приглашения нет")
sv = expect_ok("Гоша принимает", "api_partner_accept", GOSHA, g, 4)
print("    кошелёк пары:", sql("select wallet from strategists where id=%s", sv), "балансы:", sql("select name, resources from players where id in (4,5) order by id"))
expect_ok("пара: 2 ладьи (Веры и Гоши)", "api_squad_save", VERA, g, None, "Башни", [fig["Ладья-В1"], fig["Ладья-Г1"]])
expect_err("пара: 3-я ладья", "api_squad_save", GOSHA, g, None, "Ещё башня", [fig["Ладья-В2"]], contains="ладья")
expect_err("третий напарник", "api_admin_pair", A, g, 4, 2, contains="")
print("    лимит отрядов пары = 2 + max(0,2) = 4")

print("\nСтарт игры")
expect_ok("старт", "api_admin_game", A, g, "Тестовая", None, "running")
expect_err("пересборка после старта", "api_squad_save", ANYA, g, s1, "Волки", [fig["Ладья-натиск"]], contains="началась")

print("\nСвойства вне боя")
r = expect_ok("Воротила", "api_property_use", ANYA, s1b, fig["Пешка-воротила"], "Воротила", None, None, None, None)
print("    результат:", r)
expect_err("свойство чужой фигуры", "api_property_use", ANYA, s2, fig["Пешка-шпионаж"], "Шпионаж", None, None, None, None, contains="не ваш")
expect_err("свойство, которого у фигуры нет", "api_property_use", ANYA, s1, fig["Ладья-натиск"], "Лечение", None, None, None, None, contains="нет свойства")

print("\nБой из примера правил")
b = expect_ok("Аня атакует", "api_battle_open", ANYA, s1, s2)
expect_ok("Условия: Всем друг (Боря)", "api_property_use", BORYA, s2, fig["Офицер-всем-друг"], "Всем друг", None, b, None, None)
expect_err("Сила: Натиск недоступен", "api_property_use", ANYA, s1, fig["Ладья-натиск"], "Натиск", 2, b, None, None, contains="Всем друг")
expect_ok("Сила: Осведомленность", "api_property_use", ANYA, s1, fig["Конь-осведомленность"], "Осведомленность", None, b, '{"bonus":5}', None)
expect_err("фигура не может действовать дважды", "api_property_use", ANYA, s1, fig["Конь-осведомленность"], "Осведомленность", None, b, None, None, contains="уже действовала")
r1 = expect_ok("бросок Бори (база)", "api_roll", BORYA, g, b, s2, "risk", None)
expect_err("ручной бросок игроком", "api_roll", ANYA, g, b, s1, "risk", 10, contains="только ведущий")
expect_err("ручной бросок 11", "api_roll", A, g, b, s1, "risk", 11, contains="от 1 до 10")
expect_ok("ручной бросок 10 (ведущий за Аню)", "api_roll", A, g, b, s1, "risk", 10)
expect_err("Шпионаж: игрок не вводит переброс вручную", "api_property_use", BORYA, s2, fig["Пешка-шпионаж"], "Шпионаж", None, b, '{"manual_roll": 9}', None, contains="только ведущий")
spy = expect_ok("Шпионаж: переброс 9 (ведущий вводит живой кубик)", "api_property_use", A, s2, fig["Пешка-шпионаж"], "Шпионаж", None, b, '{"manual_roll": 9}', None)
if spy and spy.get("roll") == 9: ok += 1; print("  ✓ переброс записан:", spy)
else: fail += 1; print("  ✗ переброс:", spy)
expect_ok("Ущерб: повреждена пешка-шпионаж", "api_battle_step", BORYA, b, "damage", s2, fig["Пешка-шпионаж"], None)
expect_ok("Ущерб: Лечение ладьи (своё платное — можно)", "api_property_use", BORYA, s2, fig["Ладья-лечение"], "Лечение", None, b, None, None)
expect_ok("…пешка снова цела", "api_figure_state", BORYA, s2, fig["Пешка-шпионаж"], "ok", "Лечение")
expect_err("Добивание платное — под Всем друг", "api_property_use", ANYA, s1, fig["Пешка-добивание"], "Добивание", None, b, None, None, contains="Всем друг")
expect_ok("закрыть бой: победа Ани", "api_battle_close", ANYA, b, s1, '{"s":[13,15],"rolls":[9,%d]}' % (r1 or 0))
print("    ресурсы Бори после Лечения:", sql("select resources from players where id=3"))

print("\nТрофеи")
t = [expect_ok(f"трофей {i}", "api_admin_trophy_give", A, s2, f"Трофей {i}", "", 2, 0, 0) for i in range(1, 4)]
expect_err("4-й трофей", "api_admin_trophy_give", A, s2, "Трофей 4", "", 0, 0, 0, contains="3 трофея")
print("    сила «Сов» с трофеями:", sql("select s from squad_totals where squad_id=%s", s2))
expect_ok("победитель забирает трофей", "api_trophy_take", ANYA, b, t[0])
expect_err("второй трофей за тот же бой", "api_trophy_take", ANYA, b, t[1], contains="уже взят")
expect_err("проигравший не забирает", "api_trophy_take", BORYA, b, t[1])
expect_ok("выкинуть трофей", "api_trophy_drop", BORYA, t[1])

print("\nОбмен")
expect_ok("обмен: пешка-воротила → Волки", "api_exchange", ANYA, s1, s1b,
          [fig["Ладья-натиск"], fig["Пешка-добивание"], fig["Пешка-воротила"]], [fig["Конь-осведомленность"], fig["Ферзь-1"]], [t[0]], [])
expect_err("обмен: 4 фигуры в отряде", "api_exchange", ANYA, s1, s1b,
          [fig["Ладья-натиск"], fig["Пешка-добивание"], fig["Пешка-воротила"], fig["Ферзь-1"]], [fig["Конь-осведомленность"]], [t[0]], [], contains="от 1 до 3")
expect_err("обмен с чужим отрядом", "api_exchange", ANYA, s1, s2, [], [], [], [])

print("\nГибель в конце игры")
for f_ in [fig["Пешка-шпионаж"], fig["Ладья-лечение"], fig["Офицер-всем-друг"]]:
    call("api_figure_state", BORYA, s2, f_, "damaged", None)
print("    «Совы» уничтожены:", sql("select destroyed from squads where id=%s", s2))
expect_err("закрыть игру без решения", "api_admin_game", A, g, "Тестовая", None, "closed", contains="погибшие")
expect_err("Аня выбирает гибель в чужом отряде", "api_squad_death", ANYA, s2, fig["Ладья-лечение"], contains="не ваш")
dead = expect_ok("жребий", "api_squad_death", BORYA, s2, None)
print("    погибла:", sql("select name, status, died_how from figures where id=%s", dead))
expect_err("повторный выбор", "api_squad_death", BORYA, s2, fig["Ладья-лечение"], contains="уже выбрана")
expect_err("закрыть игру: кошелёк пары не разделён", "api_admin_game", A, g, "Тестовая", None, "closed", contains="кошельков")
w = sql("select wallet from strategists where id=%s", sv)[0][0]
expect_err("раздел: сумма не сходится", "api_admin_split_wallet", A, sv, '{"4": %d, "5": 99}' % w, contains="не равна")
expect_ok("раздел кошелька", "api_admin_split_wallet", A, sv, '{"4": %d, "5": 0}' % w)
expect_err("закрыть игру: трофеи не решены", "api_admin_game", A, g, "Тестовая", None, "closed", contains="трофеев")
expect_ok("трофей остаётся у Ани", "api_admin_trophy_end", A, t[0], 2)
expect_ok("трофей исчезает", "api_admin_trophy_end", A, t[2], None)
expect_ok("закрыть игру", "api_admin_game", A, g, "Тестовая", None, "closed")

print("\nСледующая игра")
g2 = expect_ok("новая игра", "api_admin_game", A, None, "Вторая", None, "draft")
expect_err("погибшую фигуру в отряд", "api_squad_save", BORYA, g2, None, "Совы", [dead], contains="погибла")
expect_ok("название «Волки» снова можно", "api_squad_save", ANYA, g2, None, "Волки", [fig["Ферзь-1"]])
expect_ok("сохранённый трофей в отряд", "api_trophy_equip", ANYA, t[0], sql("select id from squads where game_id=%s", g2)[0][0])

print("\n═══ v2: дары лун, инициатива, ходы ═══")
for nm, nom in [("Б-пешка", "пешка"), ("Б-конь", "конь"), ("Б-офицер", "офицер"), ("Б-пешка2", "пешка"),
                ("Б-ладья", "ладья"), ("Б-конь2", "конь")]:
    add(BORYA, nm, nom, 2, 2, 2, ["Мобильность"])
g3 = expect_ok("игра 3", "api_admin_game", A, None, "Луны", None, "draft")
for gift in ["alaya", "belaya", "gorkaya", "chernaya"]:
    expect_ok(f"дар {gift}", "api_admin_gift", A, g3, gift, True)
pkl = expect_ok("Аня: пешка-конь-ладья", "api_squad_save", ANYA, g3, None, "ПКЛ", [fig["Пешка-запас"], fig["Конь-запас"], fig["Ладья-натиск"]])
af = expect_ok("Аня: ферзь", "api_squad_save", ANYA, g3, None, "Ф", [fig["Ферзь-1"]])
tri = expect_ok("Боря: пешка-конь-офицер", "api_squad_save", BORYA, g3, None, "Тройка", [fig["Б-пешка"], fig["Б-конь"], fig["Б-офицер"]])
para = expect_ok("Боря: пара", "api_squad_save", BORYA, g3, None, "Пара", [fig["Б-пешка2"], fig["Б-ладья"]])
odin = expect_ok("Боря: третий отряд (бонус 1)", "api_squad_save", BORYA, g3, None, "Одиночка", [fig["Б-конь2"]])
expect_ok("Вера зовёт Гошу", "api_partner_invite", VERA, g3, 5)
pv = expect_ok("Гоша принимает", "api_partner_accept", GOSHA, g3, 4)
vg = expect_ok("пара: отряд", "api_squad_save", GOSHA, g3, None, "Башня", [fig["Ладья-В2"]])
adm = expect_ok("ведущий тоже стратег", "api_squad_save", A, g3, None, "Ведущие", [fig["Ферзь-2"]])

print("\nБелая луна")
moon = dict(sql("select squad_id, white_streak from squad_moon where game_id=%s", g3))
print("    пешка-конь-офицер:", moon.get(tri), "| пешка-конь-ладья:", moon.get(pkl))
if moon.get(tri) is True and moon.get(pkl) is False: ok += 1; print("  ✓ бонус Белой луны считается верно")
else: fail += 1; print("  ✗ бонус Белой луны")
print("    повторы номиналов «Пара»:", sql("select duplicate_nominals from squad_moon where squad_id=%s", para))

expect_ok("старт игры 3", "api_admin_game", A, g3, "Луны", None, "running")
sid = {n: sql("select strategist_id from squads where id=%s", x)[0][0] for n, x in
       [("аня", pkl), ("боря", tri), ("пара", vg), ("вед", adm)]}

print("\nИнициатива и порядок хода (Чёрная луна)")
def order():
    cur.execute("select strategist_id from turn_order(%s) order by pos", (g3,))   # служебная функция — не для anon
    return [r[0] for r in cur.fetchall()]
expect_ok("Аня 10", "api_admin_initiative", A, sid["аня"], 10)
expect_ok("пара 8 (одна на двоих)", "api_admin_initiative", A, sid["пара"], 8)
expect_ok("ведущий 5", "api_admin_initiative", A, sid["вед"], 5)
expect_ok("Боря 100 при 3 отрядах — сохраняется без ошибки", "api_admin_initiative", A, sid["боря"], 100)
want = [sid["аня"], sid["пара"], sid["вед"], sid["боря"]]
if order() == want: ok += 1; print("  ✓ Чёрная луна: Боря (3 отряда, 100) встал после первой тройки — 4-й")
else: fail += 1; print("  ✗ порядок:", order(), "ожидался", want)
expect_ok("выключить Чёрную луну", "api_admin_gift", A, g3, "chernaya", False)
if order()[0] == sid["боря"]: ok += 1; print("  ✓ без Чёрной луны Боря первый")
else: fail += 1; print("  ✗ без Чёрной луны:", order())
expect_ok("включить Чёрную луну снова (без ошибки)", "api_admin_gift", A, g3, "chernaya", True)
expect_ok("Боря 1", "api_admin_initiative", A, sid["боря"], 1)

print("\nХод 1: интриги")
expect_ok("начать ход (3 такта)", "api_admin_turn_start", A, g3, 3)
expect_ok("Аня: интрига", "api_intrigue", ANYA, g3, "Подсылаю шпиона")
expect_err("ход отряда во время интриг", "api_squad_move", ANYA, pkl, "Перемещение", None, contains="не фаза действий")
expect_ok("интриги закончены", "api_admin_turn_actions", A, g3)
expect_err("интрига после начала действий", "api_intrigue", BORYA, g3, "поздно", contains="в начале хода")

def pointer():
    return sql("select current_strategist, tact, phase from turns where game_id=%s order by number desc limit 1", g3)[0]
def expect_ptr(name, who, tact):
    global ok, fail
    cur, tc, ph = pointer()
    want = sid[who] if who else None
    if cur == want and tc == tact: ok += 1; print(f"  ✓ {name}: ходит {who or '—'}, такт {tc}, {ph}")
    else: fail += 1; print(f"  ✗ {name}: ожидался {who} такт {tact}, а {cur} такт {tc} {ph}")

print("\nХод 1: движение + действие, такты")
expect_ptr("первым ходит Аня (10)", "аня", 1)
expect_err("Боря не в свой черёд", "api_squad_move", BORYA, tri, "Перемещение", None, contains="Сейчас ходит")
expect_ok("Аня: ПКЛ перемещается (ход не закончен)", "api_squad_move", ANYA, pkl, "Перемещение", None)
expect_ptr("после Перемещения такт не ушёл", "аня", 1)
expect_err("второе Перемещение ПКЛ", "api_squad_move", ANYA, pkl, "Перемещение", None, contains="уже двигался")
expect_err("в этом такте — только один отряд", "api_squad_move", ANYA, af, "Перемещение", None, contains="в этом такте вы уже действовали")
expect_ok("ПКЛ: Активация фишки — ход закончен", "api_squad_move", ANYA, pkl, "Активация фишки", None)
print("    ход ПКЛ:", sql("select action from squad_moves where squad_id=%s", pkl))
expect_err("после действия — ничего (даже ведущему)", "api_squad_move", A, pkl, "Стоит на месте", None, contains="уже закончен")
expect_ptr("такт ушёл к паре (8)", "пара", 1)
expect_err("Нападение через «Ход» не записывается", "api_squad_move", GOSHA, vg, "Нападение", None, contains="своими кнопками")
expect_ok("ведущий отмечает за Борю вне очереди", "api_squad_move", A, tri, "Активация фишки", None)
expect_err("второй отряд Бори в том же такте", "api_squad_move", A, para, "Перемещение", None, contains="в этом такте")
expect_ptr("указатель не сдвинулся", "пара", 1)
expect_ok("Гоша: Стоит на месте (вместо движения)", "api_squad_move", GOSHA, vg, "Стоит на месте", None)
expect_ptr("ход Башни не закончен", "пара", 1)
expect_ok("Гоша: Стоит на месте (вместо действия)", "api_squad_move", GOSHA, vg, "Стоит на месте", None)
print("    ход Башни:", sql("select action from squad_moves where squad_id=%s", vg))
expect_ptr("дальше ведущий (5)", "вед", 1)
expect_ok("ведущий пропускает такт", "api_pass_turn", A, g3)
expect_ptr("Боря уже действовал в такте 1 → такт 2, Аня", "аня", 2)
expect_ok("Аня: Ф — Активация фишки без движения", "api_squad_move", ANYA, af, "Активация фишки", None)
expect_ptr("пара всё походила → ведущий", "вед", 2)
expect_ok("ведущий: Ведущие", "api_squad_move", A, adm, "Активация фишки", None)
expect_ptr("→ Боря", "боря", 2)
expect_ok("Боря: Пара", "api_squad_move", BORYA, para, "Активация фишки", None)
expect_ptr("такт 3: остался только Боря", "боря", 3)
expect_ok("Боря: Одиночка", "api_squad_move", BORYA, odin, "Активация фишки", None)
print("    ход 1:", pointer())
if pointer()[2] == "done": ok += 1; print("  ✓ все отряды походили — ход закончен")
else: fail += 1; print("  ✗ ход не закончился")

print("\nХод 2: Нападение заканчивает ход; трофей в бою; Ярость")
expect_ok("ход 2", "api_admin_turn_start", A, g3, 2)
expect_ok("действия", "api_admin_turn_actions", A, g3)
expect_err("Боря нападает не в свой черёд", "api_battle_open", BORYA, tri, pkl, contains="Сейчас ходит")
expect_ok("ПКЛ перемещается", "api_squad_move", ANYA, pkl, "Перемещение", None)
b1 = expect_ok("бой: ПКЛ нападает на Тройку", "api_battle_open", ANYA, pkl, tri)
print("    ход ПКЛ:", sql("select action, act from squad_moves m join turns t on t.id=m.turn_id where t.number=2 and m.squad_id=%s", pkl))
expect_ptr("после Нападения такт ушёл к паре", "пара", 1)
tr = expect_ok("трофей Тройке", "api_admin_trophy_give", A, tri, "Знамя", "", 1, 0, 0)
expect_err("выкинуть трофей во время боя", "api_trophy_drop", BORYA, tr, contains="Во время боя")
expect_err("второй бой с тем же отрядом", "api_battle_open", A, para, pkl, contains="уже в бою")
expect_err("Ярость без накопленной", "api_rage_spend", ANYA, pkl, "power", b1, None, contains="нет Ярости")
expect_ok("победа Ани", "api_battle_close", ANYA, b1, pkl, None)
expect_err("ПКЛ нападает второй раз за ход", "api_battle_open", A, pkl, tri, contains="уже закончен")
print("    ярость ПКЛ/Тройка:", sql("select name, rage from squads where id in (%s,%s) order by id", pkl, tri))
b2 = expect_ok("бой: Тройка нападает на ПКЛ (ведущий за Борю)", "api_battle_open", A, tri, pkl)
expect_ok("Боря тратит Ярость: +5 Силы", "api_rage_spend", BORYA, tri, "power", b2, None)
expect_err("игрок не выставляет Ярость сам", "api_admin_rage", BORYA, tri, 5, None, contains="ведущего")
expect_ok("ведущий даёт Ярость вручную", "api_admin_rage", A, tri, 2, None)
expect_err("второй раз +5 за бой", "api_rage_spend", BORYA, tri, "power", b2, None, contains="один раз за бой")
expect_ok("+1 к перемещению за Ярость", "api_rage_spend", BORYA, tri, "move", None, None)
expect_ok("победа Бори", "api_battle_close", BORYA, b2, tri, None)
r = dict(sql("select id, rage from squads where id in (%s,%s)", pkl, tri))
if r[tri] == 0 and r[pkl] == 1: ok += 1; print("  ✓ победитель сжёг Ярость, проигравший получил +1")
else: fail += 1; print("  ✗ Ярость после боя:", r)
expect_ok("после боя трофей выкинуть можно", "api_trophy_drop", BORYA, tr)

print("\nХод 3 (без Чёрной луны): Обмен заканчивает ход только начавшего")
expect_ok("выключить Чёрную луну", "api_admin_gift", A, g3, "chernaya", False)
expect_ok("ход 3", "api_admin_turn_start", A, g3, None)
expect_ok("действия", "api_admin_turn_actions", A, g3)
pf = sql("select array_agg(figure_id order by figure_id) from squad_figures where squad_id=%s", pkl)[0][0]
ff = sql("select array_agg(figure_id order by figure_id) from squad_figures where squad_id=%s", af)[0][0]
expect_ok("Аня: Обмен ПКЛ ↔ Ф", "api_exchange", ANYA, pkl, af, pf, ff, [], [])
expect_err("ПКЛ после Обмена", "api_squad_move", ANYA, pkl, "Перемещение", None, contains="уже закончен")
expect_ok("Ф после Обмена ходит дальше", "api_squad_move", ANYA, af, "Перемещение", None)
expect_ok("Ф: Активация фишки", "api_squad_move", ANYA, af, "Активация фишки", None)
expect_ok("Аня передаёт ход", "api_pass_turn", ANYA, g3)

print("\nЭхо — зона: действует только на отряд внутри")
e1 = expect_ok("Святилище (скрыто)", "api_admin_echo", A, None, g3, "Святилище", "Подкуп и Плен не работают", "hidden", "", ["Подкуп", "Плен"], 0)
e2 = expect_ok("Болото (скрыто)", "api_admin_echo", A, None, g3, "Болото", "Движение +1 Ресурс", "hidden", "до 3-го хода", [], 1)
cnt = sql("select count(*) from echoes")[0][0], sql("select count(*) from echoes_public")[0][0]
leak = sql("select count(*) from events where kind='echo' and data::text like '%%Святилище%%'")[0][0]
if cnt == (0, 0) and leak == 0: ok += 1; print("  ✓ скрытые Эхо не видны ни в таблице, ни в журнале")
else: fail += 1; print("  ✗ утечка Эхо:", cnt, leak)
expect_ok("ведущий видит скрытые", "api_admin_echoes", A, g3)
e3 = expect_ok("Буря: блок Мобильности, действует", "api_admin_echo", A, None, g3, "Буря", "", "active", "", ["Мобильность"], 0)
expect_ok("Ф вне Бури: Мобильность работает", "api_property_use", ANYA, af, fig["Ферзь-1"], "Мобильность", None, None, None, None)
expect_err("игрок не отмечает скрытое Эхо", "api_squad_echo", ANYA, af, e1, "stopped", contains="не обнаружено")
expect_ok("Ф остановился в Буре", "api_squad_echo", ANYA, af, e3, "stopped")
expect_err("Ф в Буре: Мобильность не работает", "api_property_use", ANYA, af, fig["Ферзь-1"], "Мобильность", None, None, None, None, contains="Эхо «Буря»")
expect_ok("ПКЛ снаружи: Мобильность работает", "api_property_use", ANYA, pkl, fig["Пешка-запас"], "Мобильность", None, None, None, None)
expect_ok("Ф ушёл из Бури", "api_squad_echo", ANYA, af, None, "left")
expect_err("Ферзь уже применял Мобильность в этом ходу", "api_property_use", ANYA, af, fig["Ферзь-1"], "Мобильность", None, None, None, None, contains="уже применяла свойство в этом ходу")
expect_err("и ведущему тоже — раз в ход", "api_property_use", A, af, fig["Ферзь-1"], "Мобильность", None, None, None, None, contains="уже применяла")
expect_ok("ход 4", "api_admin_turn_start", A, g3, None)
expect_ok("после ухода из Бури и в новом ходу — снова работает", "api_property_use", ANYA, af, fig["Ферзь-1"], "Мобильность", None, None, None, None)
expect_ok("Болото открыто и действует", "api_admin_echo", A, e2, g3, "Болото", "Движение +1 Ресурс", "active", "до 3-го хода", [], 1)
before = sql("select resources from players where id=2")[0][0]
expect_ok("ПКЛ прошёл через Болото", "api_squad_echo", ANYA, pkl, e2, "passed")
after = sql("select resources from players where id=2")[0][0]
if before - after == 1 and sql("select echo_id from squads where id=%s", pkl)[0][0] is None: ok += 1; print("  ✓ проход через Болото: −1 Ресурс, отметки нет")
else: fail += 1; print("  ✗ Болото:", before, after)
print("    видно игрокам:", sql("select name, status from echoes_public order by id"))
expect_ok("оплата 1 Ресурсом", "api_pay", ANYA, pkl, 1, "Болото")
expect_err("оплата больше баланса", "api_pay", ANYA, pkl, 100, "Болото", contains="Не хватает")

print("\nЧёрная луна: отряд, ходивший в прошлом такте, больше не действует")
expect_ok("включить Чёрную луну", "api_admin_gift", A, g3, "chernaya", True)
expect_ok("ход 5 (2 такта)", "api_admin_turn_start", A, g3, 2)
expect_ok("действия", "api_admin_turn_actions", A, g3)
expect_ptr("ход 5: первой ходит Аня", "аня", 1)
expect_ok("Аня: ПКЛ только перемещается", "api_squad_move", ANYA, pkl, "Перемещение", None)
expect_ok("Аня пропускает такт", "api_pass_turn", ANYA, g3)
mv = sql("select act from squad_moves m join turns t on t.id=m.turn_id where t.game_id=%s and t.number=5 and m.squad_id=%s", g3, pkl)
if mv and mv[0][0] == "Такт закончился": ok += 1; print("  ✓ ход ПКЛ закрыт, когда такт ушёл от Ани")
else: fail += 1; print("  ✗ ход ПКЛ:", mv)
for _ in range(3):   # остальные пропускают такт 1
    if pointer()[0] != sid["аня"]: call("api_pass_turn", A, g3)
expect_ptr("такт 2 — снова Аня", "аня", 2)
expect_err("ПКЛ в такте 2 — нельзя", "api_squad_move", ANYA, pkl, "Активация фишки", None, contains="уже закончен")
expect_ok("Аня ходит другим отрядом (Ф)", "api_squad_move", ANYA, af, "Активация фишки", None)
expect_ok("выключить Чёрную луну", "api_admin_gift", A, g3, "chernaya", False)
print("\nРесурсы напарников (пара Вера + Гоша в идущей игре)")
w0 = sql("select wallet from strategists where id=%s", sid["пара"])[0][0]
expect_ok("ведущий начисляет Вере 5", "api_admin_resources", A, 4, 5, None)
w1, vr = sql("select wallet from strategists where id=%s", sid["пара"])[0][0], sql("select resources from players where id=4")[0][0]
if w1 == w0 + 5 and vr == 0: ok += 1; print(f"  ✓ начисление ушло в общий кошелёк ({w0} → {w1}), личный баланс 0")
else: fail += 1; print("  ✗ кошелёк:", w0, w1, "личный:", vr)
expect_err("Вера → Гоше: напарники", "api_resources_transfer", VERA, 5, 1, None, contains="напарники")
expect_ok("Аня → Вере 1 (в кошелёк пары)", "api_resources_transfer", ANYA, 4, 1, None)
expect_ok("Вера → Ане 2 (из кошелька)", "api_resources_transfer", VERA, 2, 2, None)
w2 = sql("select wallet from strategists where id=%s", sid["пара"])[0][0]
if w2 == w1 + 1 - 2: ok += 1; print("  ✓ передачи идут через кошелёк:", w2)
else: fail += 1; print("  ✗ кошелёк после передач:", w2)
expect_err("списать больше кошелька", "api_admin_resources", A, 5, -1000, None, contains="в общем кошельке")
cur.execute("update players set resources = 7 where id = 4")   # «застрявшие» Ресурсы, как до исправления
cur.execute("select fix_pair_wallets()"); fixed = cur.fetchone()[0]
w3, vr = sql("select wallet from strategists where id=%s", sid["пара"])[0][0], sql("select resources from players where id=4")[0][0]
if fixed >= 1 and w3 == w2 + 7 and vr == 0: ok += 1; print("  ✓ починка перенесла застрявшие 7 в кошелёк")
else: fail += 1; print("  ✗ починка:", fixed, w3, vr)

print("\nВедущий собирает отряды за стратегов")
g4 = expect_ok("игра 4", "api_admin_game", A, None, "Ведущий собирает", None, "draft")
s_anya = expect_ok("ведущий добавляет Аню в игру", "api_admin_join", A, g4, 2)
expect_err("Боря собирает за Аню", "api_squad_save", BORYA, g4, None, "Чужой", [fig["Б-пешка"]], s_anya, contains="только ведущий")
expect_err("ведущий: 2 ферзя — лимит и для ведущего", "api_squad_save", A, g4, None, "Ферзи", [fig["Ферзь-1"], fig["Ферзь-2"]], s_anya, contains="ферзь")
q4 = expect_ok("ведущий собирает отряд за Аню", "api_squad_save", A, g4, None, "За Аню", [fig["Ферзь-1"]], s_anya)
own = sql("select strategist_id from squads where id=%s", q4)[0][0]
if own == s_anya: ok += 1; print("  ✓ отряд принадлежит Ане, а не ведущему")
else: fail += 1; print("  ✗ стратег отряда:", own)
expect_ok("старт игры 4", "api_admin_game", A, g4, "Ведущий собирает", None, "running")
expect_ok("Ферзь повреждён", "api_figure_state", A, q4, fig["Ферзь-1"], "damaged", None)
expect_err("Аня пересобирает в идущей игре", "api_squad_save", ANYA, g4, q4, "За Аню", [fig["Ферзь-1"], fig["Пешка-запас"]], None, contains="началась")
expect_ok("ведущий добавляет пешку в идущей игре", "api_squad_save", A, g4, q4, "За Аню", [fig["Ферзь-1"], fig["Пешка-запас"]], None)
st = dict(sql("select figure_id, state from squad_figures where squad_id=%s", q4))
if st.get(fig["Ферзь-1"]) == "damaged" and st.get(fig["Пешка-запас"]) == "ok": ok += 1; print("  ✓ при правке состояние фигур сохранилось")
else: fail += 1; print("  ✗ состояния:", st)

def expect(name, cond, info=""):
    global ok, fail
    if cond: ok += 1; print(f"  ✓ {name}")
    else: fail += 1; print(f"  ✗ {name}", info)

print("\nУчастие и роспуск отряда")
g5 = expect_ok("игра 5", "api_admin_game", A, None, "Пятая", None, "draft")
j1 = expect_ok("Аня: Участвовать", "api_join_game", ANYA, g5)
j2 = expect_ok("повторное «Участвовать»", "api_join_game", ANYA, g5)
expect("повторное «Участвовать» не создаёт второго стратега", j1 == j2 and
       sql("select count(*) from strategist_members where game_id=%s and player_id=2", g5)[0][0] == 1)
expect_err("Участвовать в идущей игре", "api_join_game", BORYA, g4, contains="уже началась")
tmp = expect_ok("Аня: отряд «Временный»", "api_squad_save", ANYA, g5, None, "Временный", [fig["Пешка-добивание"]])
expect_err("Боря распускает чужой отряд", "api_squad_delete", BORYA, tmp, contains="не ваш")
expect_ok("Аня распускает свой", "api_squad_delete", ANYA, tmp)
expect("отряд удалён, фигура свободна", sql("select count(*) from squads where id=%s", tmp)[0][0] == 0
       and sql("select count(*) from squad_figures where squad_id=%s", tmp)[0][0] == 0)
expect_err("игрок распускает отряд в идущей игре", "api_squad_delete", ANYA, q4, contains="началась")

print("\nДоп. отряды")
expect_err("доп. отряды не-ведущим", "api_admin_bonus", ANYA, 2, 5, None, contains="ведущего")
expect_err("отрицательный бонус", "api_admin_bonus", A, 2, -1, None, contains="bonus_squads")
for nm, f_ in [("Один", "Пешка-добивание"), ("Два", "Конь-осведомленность")]:
    expect_ok(f"Аня: отряд «{nm}»", "api_squad_save", ANYA, g5, None, nm, [fig[f_]])
expect_err("третий отряд без бонуса", "api_squad_save", ANYA, g5, None, "Три", [fig["Пешка-воротила"]], contains="Отрядов больше")
expect_ok("ведущий: Ане 1 доп. отряд", "api_admin_bonus", A, 2, 1, "Влияние 3")
expect("bonus_squads = 1 и запись в журнале", sql("select bonus_squads from players where id=2")[0][0] == 1
       and sql("select count(*) from events where kind='bonus_squads' and player_id=2 and amount=1")[0][0] == 1)
expect_ok("с бонусом третий отряд можно", "api_squad_save", ANYA, g5, None, "Три", [fig["Пешка-воротила"]])

print("\nФигура в другой отряд (Подкуп) и отмена шага боя")
s_bor = expect_ok("ведущий добавляет Борю в игру 4", "api_admin_join", A, g4, 3)
add(BORYA, "Б-лекарь", "пешка", 1, 1, 1, ["Лечение"])
qb = expect_ok("ведущий собирает отряд за Борю", "api_squad_save", A, g4, None, "Борины", [fig["Б-пешка"], fig["Б-лекарь"]], s_bor)
expect_err("игрок переносит фигуру", "api_admin_move_figure", ANYA, q4, qb, fig["Пешка-запас"], None, contains="ведущего")
expect_ok("ведущий: пешка Ани к Боре", "api_admin_move_figure", A, q4, qb, fig["Пешка-запас"], "Подкуп")
row = sql("select squad_id, strategist_id, borrowed from squad_figures where figure_id=%s and game_id=%s", fig["Пешка-запас"], g4)
expect("фигура в отряде Бори, у его стратега, помечена «взята»", row == [(qb, s_bor, True)], row)
expect("в журнале — перенос", sql("select count(*) from events where kind='figure_move' and figure_id=%s", fig["Пешка-запас"])[0][0] == 1)
expect_ok("ведущий возвращает пешку Ане", "api_admin_move_figure", A, qb, q4, fig["Пешка-запас"], "вернуть")
row = sql("select squad_id, borrowed from squad_figures where figure_id=%s and game_id=%s", fig["Пешка-запас"], g4)
expect("вернувшаяся к владельцу фигура больше не «взята»", row == [(q4, False)], row)
expect_ok("и снова к Боре", "api_admin_move_figure", A, q4, qb, fig["Пешка-запас"], "Подкуп")
n_ev = sql("select count(*) from events where kind='figure_move'")[0][0]
expect_err("перенос фигуры, которой нет в отряде", "api_admin_move_figure", A, q4, qb, fig["Ладья-В1"], None, contains="Фигуры нет в отряде")
expect("…и в журнале пустой записи нет", sql("select count(*) from events where kind='figure_move'")[0][0] == n_ev)
expect_err("перенос в отряд другой игры", "api_admin_move_figure", A, qb, pkl, fig["Б-пешка"], None, contains="разных игр")
expect_err("перенос в тот же отряд", "api_admin_move_figure", A, qb, qb, fig["Б-пешка"], None, contains="уже в этом отряде")
b5 = expect_ok("ведущий открывает бой (без трекера ходов)", "api_battle_open", A, q4, qb)
expect_ok("Боре +2 Ресурса на Лечение", "api_admin_resources", A, 3, 2, None)
r0 = sql("select resources from players where id=3")[0][0]
expect_ok("Боря: Лечение (1 Р.)", "api_property_use", BORYA, qb, fig["Б-лекарь"], "Лечение", None, b5, None, None)
step = sql("select id, cost from battle_actions where battle_id=%s and property='Лечение'", b5)
expect("шаг Лечения записан с ценой 1, Ресурсы списаны", step and step[0][1] == 1 and sql("select resources from players where id=3")[0][0] == r0 - 1, step)
expect_err("игрок отменяет шаг боя", "api_admin_battle_undo", BORYA, step[0][0], contains="ведущего")
expect_ok("ведущий отменяет шаг", "api_admin_battle_undo", A, step[0][0])
expect("шаг удалён, Ресурсы вернулись", sql("select count(*) from battle_actions where id=%s", step[0][0])[0][0] == 0
       and sql("select resources from players where id=3")[0][0] == r0)
expect_err("повторная отмена того же шага", "api_admin_battle_undo", A, step[0][0], contains="Нет такого шага")
expect("…Ресурсы второй раз не вернулись", sql("select resources from players where id=3")[0][0] == r0)
expect_ok("Лечение снова можно (фигура не считается походившей)", "api_property_use", BORYA, qb, fig["Б-лекарь"], "Лечение", None, b5, None, None)

print("\nОтмена записи журнала")
ev = sql("select max(id) from events where kind='bonus_squads'")[0][0]
expect_err("игрок отменяет запись", "api_admin_revert", ANYA, ev, None, contains="ведущего")
expect_ok("ведущий отменяет запись", "api_admin_revert", A, ev, "ошибся игрой")
expect("запись помечена, отмена сама записана в журнал",
       sql("select reverted from events where id=%s", ev)[0][0] is True
       and sql("select count(*) from events where kind='revert' and (data->>'event')::bigint=%s", ev)[0][0] == 1)
expect("отмена только помечает: бонус не изменился", sql("select bonus_squads from players where id=2")[0][0] == 1)

print("\nПередать ход вручную")
expect_err("передать ход, когда ходов не было", "api_admin_turn_set", A, g4, s_bor, None, None, contains="Ходов ещё не было")
expect_err("игрок двигает указатель", "api_admin_turn_set", ANYA, g3, sid["аня"], None, None, contains="ведущего")
expect_ok("ведущий: ходит Боря, такт 1, действия", "api_admin_turn_set", A, g3, sid["боря"], 1, "actions")
expect_ptr("указатель на Боре", "боря", 1)
expect_ok("ведущий: только сменить стратега (такт и фаза прежние)", "api_admin_turn_set", A, g3, sid["пара"], None, None)
expect_ptr("указатель на паре, такт 1", "пара", 1)
expect("фаза осталась «действия»", pointer()[2] == "actions", pointer())
expect_err("указатель на стратега из другой игры", "api_admin_turn_set", A, g3, s_bor, None, None, contains="не участвует в игре")
expect_ptr("указатель не сдвинулся", "пара", 1)

print("\nМиграция 005 на старой базе")
cur.execute("update squad_figures set borrowed = true where figure_id=%s and game_id=%s", (fig["Ферзь-1"], g4))  # «застрявшая» пометка
mig = (pathlib.Path(__file__).parent / "migrations" / "005_admin_checks.sql").read_text(encoding="utf-8")
try:
    cur.execute(mig); res = cur.fetchone()
    expect("миграция выполняется повторно без ошибок, строка «ok»", res == ("ok",), res)
except Exception as e:
    expect("миграция выполняется повторно без ошибок", False, str(e).splitlines()[0])
expect("починка сняла «взята» у фигуры владельца", sql("select borrowed from squad_figures where figure_id=%s and game_id=%s", fig["Ферзь-1"], g4) == [(False,)])
expect("…а у фигуры, взятой у противника, оставила",
       sql("select borrowed from squad_figures where figure_id=%s and game_id=%s", fig["Пешка-запас"], g4) == [(True,)])

print("\nЖурнал:", sql("select count(*) from events")[0][0], "записей; конфликты:", sql("select count(*) from figure_conflicts")[0][0])
print(f"\nИтого: {ok} ✓, {fail} ✗")
sys.exit(1 if fail else 0)
