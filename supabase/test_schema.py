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

print("\nИнициатива (Чёрная луна)")
expect_err("Боря с 3 отрядами на 1-м месте", "api_admin_initiative", A, sid["боря"], 100, contains="Чёрная луна")
expect_ok("Аня 10", "api_admin_initiative", A, sid["аня"], 10)
expect_ok("пара 8 (одна на двоих)", "api_admin_initiative", A, sid["пара"], 8)
expect_ok("ведущий 5", "api_admin_initiative", A, sid["вед"], 5)
expect_ok("Боря 1 (4-е место)", "api_admin_initiative", A, sid["боря"], 1)
expect_ok("выключить Чёрную луну", "api_admin_gift", A, g3, "chernaya", False)
expect_ok("без Чёрной луны Боря может быть первым", "api_admin_initiative", A, sid["боря"], 100)
expect_err("включить Чёрную луну, когда Боря первый", "api_admin_gift", A, g3, "chernaya", True, contains="Чёрная луна")
expect_ok("Боря снова 1", "api_admin_initiative", A, sid["боря"], 1)
expect_ok("включить Чёрную луну", "api_admin_gift", A, g3, "chernaya", True)

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

print("\nХод 1: такты")
expect_ptr("первым ходит Аня (10)", "аня", 1)
expect_err("Боря не в свой черёд", "api_squad_move", BORYA, tri, "Перемещение", None, contains="Сейчас ходит")
expect_ok("Аня: ПКЛ перемещается", "api_squad_move", ANYA, pkl, "Перемещение", None)
expect_ptr("такт ушёл к паре (8)", "пара", 1)
expect_err("Аня вторым отрядом не в свой черёд", "api_squad_move", ANYA, af, "Перемещение", None, contains="Сейчас ходит")
expect_ok("ведущий отмечает за Борю (вне очереди)", "api_squad_move", A, tri, "Нападение", None)
expect_err("второй отряд Бори в том же такте", "api_squad_move", A, para, "Перемещение", None, contains="в этом такте")
expect_ptr("указатель не сдвинулся", "пара", 1)
expect_ok("Гоша: Башня", "api_squad_move", GOSHA, vg, "Активация фишки", None)
expect_ptr("дальше ведущий (5)", "вед", 1)
expect_ok("ведущий пропускает такт", "api_pass_turn", A, g3)
expect_ptr("Боря уже ходил в такте 1 → такт 2, Аня", "аня", 2)
expect_err("ПКЛ второй раз за ход", "api_squad_move", ANYA, pkl, "Перемещение", None, contains="уже ходил")
expect_ok("Аня: Ф", "api_squad_move", ANYA, af, "Перемещение", None)
expect_ptr("пара всё походила → ведущий", "вед", 2)
expect_ok("ведущий: Ведущие", "api_squad_move", A, adm, "Перемещение", None)
expect_ptr("→ Боря", "боря", 2)
expect_ok("Боря: Пара", "api_squad_move", BORYA, para, "Перемещение", None)
expect_ptr("такт 3: остался только Боря", "боря", 3)
expect_ok("Боря: Одиночка", "api_squad_move", BORYA, odin, "Перемещение", None)
print("    ход 1:", pointer())
if pointer()[2] == "done": ok += 1; print("  ✓ все отряды походили — ход закончен")
else: fail += 1; print("  ✗ ход не закончился")

print("\nЯрость (Алая луна)")
expect_ok("ход 2", "api_admin_turn_start", A, g3, 2)
expect_ok("действия", "api_admin_turn_actions", A, g3)
b1 = expect_ok("бой: ПКЛ атакует Тройку", "api_battle_open", ANYA, pkl, tri)
expect_err("Ярость без накопленной", "api_rage_spend", ANYA, pkl, "power", b1, None, contains="нет Ярости")
expect_ok("победа Ани", "api_battle_close", ANYA, b1, pkl, None)
print("    ярость ПКЛ/Тройка:", sql("select name, rage from squads where id in (%s,%s) order by id", pkl, tri))
b2 = expect_ok("бой: Тройка атакует ПКЛ", "api_battle_open", BORYA, tri, pkl)
expect_ok("Боря тратит Ярость: +5 Силы", "api_rage_spend", BORYA, tri, "power", b2, None)
expect_err("игрок не выставляет Ярость сам", "api_admin_rage", BORYA, tri, 5, None, contains="ведущего")
expect_ok("ведущий даёт Ярость вручную", "api_admin_rage", A, tri, 2, None)
expect_err("второй раз +5 за бой", "api_rage_spend", BORYA, tri, "power", b2, None, contains="один раз за бой")
expect_ok("+1 к перемещению за Ярость", "api_rage_spend", BORYA, tri, "move", None, None)
expect_ok("победа Бори", "api_battle_close", BORYA, b2, tri, None)
r = dict(sql("select id, rage from squads where id in (%s,%s)", pkl, tri))
if r[tri] == 0 and r[pkl] == 1: ok += 1; print("  ✓ победитель сжёг Ярость, проигравший получил +1")
else: fail += 1; print("  ✗ Ярость после боя:", r)

print("\nЭхо (Горькая луна)")
e1 = expect_ok("Святилище (скрыто)", "api_admin_echo", A, None, g3, "Святилище", "Подкуп и Плен не работают", "hidden", "", ["Подкуп", "Плен"], 0)
e2 = expect_ok("Болото (скрыто)", "api_admin_echo", A, None, g3, "Болото", "Движение +1 Ресурс", "hidden", "до 3-го хода", [], 1)
cnt = sql("select count(*) from echoes")[0][0], sql("select count(*) from echoes_public")[0][0]
leak = sql("select count(*) from events where kind='echo' and data::text like '%%Святилище%%'")[0][0]
if cnt == (0, 0) and leak == 0: ok += 1; print("  ✓ скрытые Эхо не видны ни в таблице, ни в журнале")
else: fail += 1; print("  ✗ утечка Эхо:", cnt, leak)
expect_ok("ведущий видит скрытые", "api_admin_echoes", A, g3)
expect_ok("Мобильность пока работает", "api_property_use", ANYA, af, fig["Ферзь-1"], "Мобильность", None, None, None, None)
expect_ok("Эхо-тест: блок Мобильности, активно", "api_admin_echo", A, None, g3, "Буря", "", "active", "", ["Мобильность"], 0)
expect_err("Мобильность под Эхо", "api_property_use", ANYA, af, fig["Ферзь-1"], "Мобильность", None, None, None, None, contains="Эхо «Буря»")
expect_ok("Болото открыто и активно", "api_admin_echo", A, e2, g3, "Болото", "Движение +1 Ресурс", "active", "до 3-го хода", [], 1)
print("    видно игрокам:", sql("select name, status from echoes_public order by id"))
expect_ok("оплата Болота 1 Ресурсом", "api_pay", ANYA, pkl, 1, "Болото")
expect_err("оплата больше баланса", "api_pay", ANYA, pkl, 100, "Болото", contains="Не хватает")

print("\nЖурнал:", sql("select count(*) from events")[0][0], "записей; конфликты:", sql("select count(*) from figure_conflicts")[0][0])
print(f"\nИтого: {ok} ✓, {fail} ✗")
sys.exit(1 if fail else 0)
