"""Страница игры и помощник боя в Chromium на подставных данных (без записи в живую базу).

Ответы Supabase подменяются (tests/mock_backend.py): таблицы — из фикстур (пример боя из правил),
вызовы api_* — записываются и отвечают «успешно».

  python tests/ui_mock.py [папка_для_снимков]
"""
import pathlib, sys
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from mock_backend import T, calls, serve, attach, Checks

sys.stdout.reconfigure(encoding="utf-8")
SHOTS = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
srv, BASE = serve()
errors = []
check = Checks()

with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 1280, "height": 1000})
    attach(page, errors)

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
    # Стратега убрали из игры: база удалила его отряд (99) — его фигура не «выбыла из отряда», а пропадает из статистики.
    saved_events = list(T["events"])
    T["events"] += [
        {"id": 90, "at": "2026-10-20T15:10:00Z", "actor": 1, "kind": "squad_save", "game_id": 1, "figure_id": None, "squad_id": 99,
         "player_id": None, "amount": None, "data": {"name": "Ушедшие", "figures": [25]}, "comment": None, "reverted": False},
        {"id": 91, "at": "2026-10-20T15:20:00Z", "actor": 1, "kind": "leave_game", "game_id": 1, "figure_id": None, "squad_id": None,
         "player_id": 3, "amount": 0, "data": {"squads": 1, "partner": None}, "comment": "убрал ведущий", "reverted": False}]
    page.reload()
    page.wait_for_selector("text=Статистика игры", timeout=20000)
    st = page.locator("section.card:has(h2:has-text('Статистика игры'))").inner_text()
    check("стратег убран: его фигуры не в статистике (7 фигур, выбывших 0)",
          "7\nфигур в отрядах (сейчас и раньше)" in st and "0\nвыбыла из отряда" in st, st[:200])
    T["events"][:] = saved_events
    page.reload()
    page.wait_for_selector("text=Статистика игры", timeout=20000)
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

    print("\nПогибшая фигура в отряде")
    # как в тестовой игре: в отряде выбрана погибшая, в отряде она «повреждена», в общем списке жива
    T["squad_figures"].append({"squad_id": 4, "figure_id": 25, "game_id": 1, "strategist_id": 2, "state": "damaged", "borrowed": False})
    T["squads"][3]["dead_figure"] = 25
    page.goto(BASE + "#/game/1")
    page.wait_for_selector("text=Статистика игры", timeout=20000)
    li = page.locator(".squads .squad:has(.name:text-is('Павшие')) li:has-text('Выбывший пёс')").first
    lt = li.inner_text()
    check("у погибшей значок «погибла», а не «повреждена»", "погибла" in lt and "повреждена" not in lt, lt)
    check("…и строка зачёркнута (st-dead)", "st-dead" in (li.get_attribute("class") or ""), li.get_attribute("class"))
    st = page.locator("section.card:has(h2:has-text('Статистика игры'))").inner_text()
    check("статистика игры считает её погибшей", "1\nпогибла" in st, st[:300])
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
print(f"Итого: {check.ok} ✓, {check.fail} ✗")
sys.exit(1 if check.fail or errors else 0)
