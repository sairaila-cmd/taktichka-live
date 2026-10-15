"""Действия игрока и ведущего в Chromium на подставных данных (без записи в живую базу).

Каждый сценарий нажимает кнопки сайта и проверяет, какой вызов api_* ушёл в базу и с какими
параметрами, и что показал сайт (окна, уведомления, ошибки базы). ID сценариев (И-…, В-…)
совпадают с каталогом «Тестовые сценарии тактички.xlsx».

  python tests/ui_flows.py [папка_для_снимков]
"""
import pathlib, sys
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mock_backend as m
from mock_backend import T, calls, FAIL, RESULT

sys.stdout.reconfigure(encoding="utf-8")
SHOTS = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
srv, BASE = m.serve()
errors = []
check = m.Checks()
FULL_BATTLE = [dict(a) for a in m.BASE["battle_actions"]]


def extend():
    """К общим фикстурам: игра в сборе отрядов, погибшая фигура, фигура в уничтоженном отряде."""
    T["games"].append({"id": 2, "title": "Сбор у старой мельницы", "starts_at": None, "status": "draft"})
    T["game_gifts"].append({"game_id": 2, "gift": "belaya"})
    T["figures"] += [m.fig(26, "Ферзь бури", "ферзь", 6, 3, "Мобильность"), m.fig(27, "Ферзь песков", "ферзь", 5, 4, "Мобильность"),
                     m.fig(28, "Пешка ветра", "пешка", 1, 1, "Мобильность"),
                     dict(m.fig(30, "Павший ворон", "пешка", 2, 2, "Мобильность"), status="dead")]
    T["figure_owners"] += [{"figure_id": f, "player_id": 5} for f in (26, 27, 28)] + [{"figure_id": 30, "player_id": 3}]
    T["strategists"] += [{"id": 3, "game_id": 2, "wallet": None, "invited": None, "initiative": None},
                         {"id": 4, "game_id": 2, "wallet": None, "invited": 2, "initiative": None}]
    T["strategist_members"] += [{"strategist_id": 3, "game_id": 2, "player_id": 5}, {"strategist_id": 4, "game_id": 2, "player_id": 4}]
    T["squads"].append({"id": 5, "game_id": 2, "strategist_id": 3, "name": "Ветер", "name_key": "ветер", "destroyed": False, "dead_figure": None, "rage": 0})
    T["squad_figures"] += [{"squad_id": 5, "figure_id": 26, "game_id": 2, "strategist_id": 3, "state": "ok", "borrowed": False},
                           {"squad_id": 4, "figure_id": 25, "game_id": 1, "strategist_id": 2, "state": "discard", "borrowed": False}]


def setup():
    m.reset(); extend()


def go(page, code, route, wait):
    """Открыть раздел под нужным кодом (None — без входа) и дождаться текста."""
    page.goto(BASE + route)
    page.evaluate("c => c ? localStorage.setItem('taktichka.code', c) : localStorage.removeItem('taktichka.code')", code)
    page.reload()
    page.wait_for_function("() => !document.querySelector('#view .loading')", timeout=20000)
    if wait: page.wait_for_selector(f"text={wait}", timeout=15000)


def wait_call(page, fn, timeout=5000):
    """Дождаться вызова fn после последнего mark(); вернуть тело или None."""
    waited = 0
    while waited < timeout:
        hits = [b for f, b in calls[mark.at:] if f == fn]
        if hits: return hits[-1]
        page.wait_for_timeout(100); waited += 100
    return None


class Mark:
    at = 0
    def __call__(self): self.at = len(calls)
mark = Mark()

dlg = "dialog[open]"
def dialog_text(page): return page.locator(dlg).inner_text() if page.locator(dlg).count() else ""
def in_dialog(page, text): page.locator(f"{dlg} button:has-text('{text}')").first.click()
def toast_error(page, timeout=5000):
    try: page.wait_for_selector(".toast.error", timeout=timeout)
    except Exception: return ""
    return " ".join(page.locator(".toast.error").all_inner_texts())
def squad(page, name, mine=False):
    scope = "section.card:has(h2:has-text('Моё участие'))" if mine else ".squads"
    return page.locator(f"{scope} .squad:has(.name:text-is('{name}'))").first
def has(b, **kw): return b is not None and all(b.get(k) == v for k, v in kw.items())
def shot(page, name):
    if SHOTS: page.screenshot(path=str(SHOTS / f"{name}.png"), full_page=True)


with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 1280, "height": 1000})
    m.attach(page, errors)

    # ═════════════════════ ИГРОК ═════════════════════
    print("Вход и выход")
    setup()
    go(page, None, "#/", "Все фигуры")
    check("И-03 без кода нет «+ Добавить фигуру»", page.locator("button:has-text('+ Добавить фигуру')").count() == 0)
    page.click("tbody tr:has-text('Ладья-натиск')")
    page.wait_for_selector(f"{dlg} h2:has-text('Ладья-натиск')")
    check("И-03 без кода в окне фигуры нет «Править/Передать»", page.locator(f"{dlg} button:has-text('Править')").count() == 0
          and page.locator(f"{dlg} button:has-text('Передать')").count() == 0)
    page.keyboard.press("Escape")
    page.fill("#who input", "bad-code"); page.click("#who button")
    err = toast_error(page)
    check("И-02 неверный код → сообщение «Неверный код»", "Неверный код" in err, err)
    check("И-02 после неверного кода вход не выполнен, код не запомнен",
          page.locator("#who .me").count() == 0 and page.evaluate("localStorage.getItem('taktichka.code')") is None)
    page.fill("#who input", "zoi-test"); page.click("#who button")
    page.wait_for_selector("#who .me", timeout=10000)
    check("И-01 вход кодом: в шапке «Вы: Зои»", page.locator("#who .me").inner_text() == "Зои")
    page.wait_for_selector("button:has-text('+ Добавить фигуру')", timeout=10000)
    check("И-01 после входа есть «+ Добавить фигуру», раздела «Ведущий» нет",
          page.locator("#nav-admin").is_hidden())
    check("И-01 код запомнен в браузере", page.evaluate("localStorage.getItem('taktichka.code')") == "zoi-test")
    page.click("#who button:has-text('Выйти')")
    page.wait_for_selector("#who input", timeout=10000)
    check("И-01 «Выйти»: поле кода снова на месте, код забыт",
          page.evaluate("localStorage.getItem('taktichka.code')") is None)

    print("\nФигуры: поиск, фильтры, сортировка")
    go(page, None, "#/", "Все фигуры")
    rows = lambda: page.locator("tbody tr").count()
    check("И-10 в таблице только фигуры в строю (11 из 12)", rows() == 11, rows())
    page.check("label:has-text('погибшие') input")
    check("И-10 «погибшие» добавляет погибших (12)", rows() == 12, rows())
    page.uncheck("label:has-text('погибшие') input")
    page.fill("input[type=search]", "шпион")
    check("И-10 поиск «шпион» → 1 фигура", rows() == 1 and "Пешка-шпион" in " ".join(page.locator("tbody").all_inner_texts()))
    page.fill("input[type=search]", "Мобильность")
    check("И-10 поиск по свойству «Мобильность» → 5 фигур", rows() == 5, rows())
    page.fill("input[type=search]", "")
    page.click(".chips .chip:has-text('конь')")
    check("И-10 фильтр «конь» → 2 фигуры", rows() == 2, rows())
    page.click(".chips .chip:has-text('Все')")
    page.select_option("select[aria-label='Владелец']", label="Зои")
    check("И-10 фильтр по владельцу «Зои» → 3 фигуры", rows() == 3, rows())
    page.select_option("select[aria-label='Владелец']", value="")
    page.click("thead button:text-is('С') >> nth=0")
    first = page.locator("tbody tr").first.inner_text()
    check("И-10 сортировка по Силе: сначала самая сильная (Ладья-лекарь, 7)", first.startswith("Ладья-лекарь"), first[:40])
    page.click("thead button:text-is('С') >> nth=0")
    check("И-10 повторный щелчок — обратный порядок", page.locator("tbody tr").first.inner_text().startswith("Пешка"),
          page.locator("tbody tr").first.inner_text()[:40])
    opts = page.locator("select[aria-label='Источник'] option").all_inner_texts()
    check("И-16 список источников: каждый источник один раз, из «;»-списков", opts == ["Все источники", "182/8", "Фури", "Storm Heist"], opts)
    page.select_option("select[aria-label='Источник']", label="Storm Heist")
    check("И-16 фильтр по источнику «Storm Heist» → 2 фигуры", rows() == 2, rows())
    page.select_option("select[aria-label='Владелец']", label="Зои")
    check("И-16 источник + владелец «Зои» вместе → 1 фигура (Пешка-добивание)",
          rows() == 1 and "Пешка-добивание" in " ".join(page.locator("tbody").all_inner_texts()), rows())
    page.select_option("select[aria-label='Источник']", value="")
    page.select_option("select[aria-label='Владелец']", value="")
    game_rows = lambda: page.locator("#figs-game tbody tr").all_inner_texts()
    rest_rows = lambda: page.locator("#figs-rest tbody tr").all_inner_texts()
    g = game_rows()
    check("И-17 сверху — фигуры в отрядах идущей игры (8)", len(g) == 8 and not any("Ферзь" in x for x in g), len(g))
    check("И-17 остальные — в свёрнутом блоке «Остальные фигуры (3)»",
          len(rest_rows()) == 3 and page.locator("details summary").inner_text() == "Остальные фигуры (3)"
          and page.locator("details").get_attribute("open") is None, page.locator("details summary").inner_text())
    page.select_option("select[aria-label='Игра']", value="2")
    page.wait_for_function("() => location.hash === '#/figures/2' && document.querySelectorAll('#figs-game tbody tr').length === 1", timeout=10000)
    check("И-17 выбор другой игры: сверху её фигуры (Ферзь бури), остальные 10 ниже",
          game_rows()[0].startswith("Ферзь бури") and len(rest_rows()) == 10, (game_rows(), len(rest_rows())))
    page.fill("input[type=search]", "Ладья")
    check("И-17 поиск действует на оба списка", len(game_rows()) == 0 and len(rest_rows()) == 2
          and page.locator("p.empty:has-text('Под фильтр не попала')").is_visible(), (len(game_rows()), len(rest_rows())))

    print("\nФигуры: правки по коду")
    go(page, "zoi-test", "#/", "+ Добавить фигуру")
    mark(); page.click("button:has-text('+ Добавить фигуру')")
    page.wait_for_selector(f"{dlg} h2:has-text('Новая фигура')")
    page.fill(f"{dlg} input[name=name]", "Конь-разведчик")
    page.select_option(f"{dlg} select[name=nominal]", "конь")
    page.fill(f"{dlg} input[name=s]", "3")
    page.select_option(f"{dlg} select[name=properties]", ["Мобильность"])
    page.fill(f"{dlg} input[name=source]", "Пять ликов")
    in_dialog(page, "Добавить")
    c = wait_call(page, "api_figure_add")
    check("И-11 «+ Добавить фигуру» → api_figure_add с полями формы",
          has(c, p_name="Конь-разведчик", p_nominal="конь", p_s=3, p_l=1, p_properties=["Мобильность"], p_source="Пять ликов"), c)
    page.wait_for_timeout(300)
    check("И-11 после добавления окно закрыто", page.locator(dlg).count() == 0)

    page.click("tbody tr:has-text('Ладья-натиск')")
    page.wait_for_selector(f"{dlg} button:has-text('Править')")
    check("И-12 у своей фигуры кнопки «Править», «Передать», «Отметить применение»",
          all(page.locator(f"{dlg} button:has-text('{t}')").count() == 1 for t in ("Править", "Передать", "Отметить применение")))
    mark(); in_dialog(page, "Править")
    page.wait_for_selector(f"{dlg} h2:has-text('Править «Ладья-натиск»')")
    check("И-12 форма правки заполнена текущими значениями", page.input_value(f"{dlg} input[name=s]") == "5")
    page.fill(f"{dlg} input[name=s]", "6"); page.fill(f"{dlg} input[name=comment]", "Трофей Луны")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_figure_edit")
    check("И-12 «Править» → api_figure_edit (фигура 11, Сила 6, причина)", has(c, p_figure=11, p_s=6, p_comment="Трофей Луны", p_nominal="ладья"), c)

    page.click("tbody tr:has-text('Ладья-натиск')")
    page.wait_for_selector(f"{dlg} button:has-text('Передать')")
    mark(); in_dialog(page, "Передать")
    page.wait_for_selector(f"{dlg} select[name=to]")
    opts = page.locator(f"{dlg} select[name=to] option").all_inner_texts()
    check("И-13 «Передать»: «Чья доля» — только своя, в «Кому» нет ведущего",
          page.locator(f"{dlg} select[name=from] option").all_inner_texts() == ["Зои"] and "Ведущий" not in opts, opts)
    page.select_option(f"{dlg} select[name=to]", label="Самум")
    in_dialog(page, "Передать")
    c = wait_call(page, "api_figure_transfer")
    check("И-13 → api_figure_transfer от Зои к Самуму", has(c, p_figure=11, p_from=2, p_to=5), c)

    page.click("tbody tr:has-text('Ладья-натиск')")
    page.wait_for_selector(f"{dlg} button:has-text('Отметить применение')")
    mark(); in_dialog(page, "Отметить применение")
    page.wait_for_selector(f"{dlg} select[name=game]")
    page.select_option(f"{dlg} select[name=game]", "1")
    page.fill(f"{dlg} input[name=comment]", "Натиск на Сов")
    in_dialog(page, "Отметить")
    c = wait_call(page, "api_figure_use")
    check("И-14 «Отметить применение» → api_figure_use с игрой 1", has(c, p_figure=11, p_game=1, p_comment="Натиск на Сов"), c)

    page.click("tbody tr:has-text('Пешка-шпион')")
    page.wait_for_selector(f"{dlg} h2:has-text('Пешка-шпион')")
    check("И-15 у чужой фигуры нет кнопок правки", page.locator(f"{dlg} button:has-text('Править')").count() == 0)
    page.keyboard.press("Escape")

    print("\nРесурсы")
    go(page, "zoi-test", "#/people", "Стратеги и Ресурсы")
    mark(); page.click("button:has-text('Передать Ресурсы')")
    page.wait_for_selector(f"{dlg} select[name=to]")
    dt = dialog_text(page)
    opts = page.locator(f"{dlg} select[name=to] option").all_inner_texts()
    check("И-20 в окне видно, сколько Ресурсов (3), себе передать нельзя", "у вас 3" in dt and "Зои" not in opts, (dt[:80], opts))
    page.select_option(f"{dlg} select[name=to]", label="Самум")
    page.fill(f"{dlg} input[name=amount]", "2"); page.fill(f"{dlg} input[name=comment]", "за помощь")
    in_dialog(page, "Передать")
    c = wait_call(page, "api_resources_transfer")
    check("И-20 «Передать Ресурсы» → api_resources_transfer (Самуму 2)", has(c, p_to=5, p_amount=2, p_comment="за помощь"), c)
    FAIL["api_resources_transfer"] = "Недостаточно Ресурсов: есть 3"
    page.wait_for_timeout(300)
    page.click("button:has-text('Передать Ресурсы')")
    page.wait_for_selector(f"{dlg} select[name=to]")
    page.fill(f"{dlg} input[name=amount]", "50")
    in_dialog(page, "Передать")
    err = toast_error(page)
    check("И-21 отказ базы виден в уведомлении с её текстом", "Недостаточно Ресурсов: есть 3" in err, err)
    check("И-21 при ошибке окно остаётся открытым (можно исправить)", page.locator(dlg).count() == 1)
    page.keyboard.press("Escape")
    FAIL.clear()

    print("\nПодготовка к игре (игра в сборе отрядов)")
    setup()
    go(page, "zoi-test", "#/game/2", "Подготовка")
    mine_card = "section.card:has(h2:has-text('Моё участие'))"
    txt = page.locator(mine_card).inner_text()
    check("И-30 не участвующей видны «Участвовать», «+ Новый отряд», «Принять приглашение: Любомир»",
          all(t in txt for t in ("Участвовать", "+ Новый отряд", "Принять приглашение: Любомир")), txt)
    mark(); page.click(f"{mine_card} button:has-text('Участвовать')")
    c = wait_call(page, "api_join_game")
    check("И-30 «Участвовать» → api_join_game (игра 2)", has(c, p_game=2), c)

    mark(); page.click(f"{mine_card} button:has-text('Принять приглашение')")
    page.wait_for_selector(f"{dlg} >> text=Стать напарником: Любомир")
    in_dialog(page, "Да")
    c = wait_call(page, "api_partner_accept")
    check("И-35 «Принять приглашение» → подтверждение → api_partner_accept (пригласил Любомир)", has(c, p_game=2, p_inviter=4), c)

    page.wait_for_timeout(300)
    mark(); page.click(f"{mine_card} button:has-text('+ Новый отряд')")
    page.wait_for_selector(f"{dlg} h2:has-text('Новый отряд — Зои')")
    labels = page.locator(f"{dlg} label.inline").all_inner_texts()
    check("И-31 в сборке только свои фигуры (3), чужих нет", len(labels) == 3 and not any("шпион" in l for l in labels), labels)
    check("И-31 пустой отряд помечен «0 из 1–3» красным", page.locator(f"{dlg} .badge.bad:has-text('0 из 1–3')").count() == 1)
    page.fill(f"{dlg} input[placeholder='Уникальное в этой игре']", "Тени")
    page.check(f"{dlg} label.inline:has-text('Ладья-натиск') input")
    page.check(f"{dlg} label.inline:has-text('Конь-осведомлённый') input")
    summ = page.locator(f"{dlg} .row.small").inner_text()
    check("И-31 сводка: 2 из 1–3, С 7 · Л 5 · В 2", "2 из 1–3" in summ and "С 7 · Л 5 · В 2" in summ, summ)
    page.fill(f"{dlg} input[type=search]", "конь")
    check("И-31 поиск внутри окна сборки", page.locator(f"{dlg} label.inline").count() == 1)
    in_dialog(page, "Сохранить отряд")
    c = wait_call(page, "api_squad_save")
    check("И-31 «Сохранить отряд» → api_squad_save (новый, игра 2, 2 фигуры)",
          has(c, p_game=2, p_squad=None, p_name="Тени", p_strategist=None) and sorted(c["p_figures"]) == [11, 13], c)

    go(page, "samum-test", "#/game/2", "Моё участие: Самум")
    txt = page.locator(mine_card).inner_text()
    check("И-32 в «Моём участии» Самума: «отрядов 1 из 2», ферзь 1/1", "отрядов 1 из 2" in txt and "♛ 1/1" in txt, txt[:200])
    mark(); page.click(f"{mine_card} button:has-text('+ Новый отряд')")
    page.wait_for_selector(f"{dlg} h2:has-text('Новый отряд — Самум')")
    labels = page.locator(f"{dlg} label.inline").all_inner_texts()
    check("И-32 фигура из другого отряда («Ферзь бури») не предлагается", not any("Ферзь бури" in l for l in labels), labels)
    page.fill(f"{dlg} input[placeholder='Уникальное в этой игре']", "Пески")
    page.check(f"{dlg} label.inline:has-text('Ферзь песков') input")
    check("И-32 второй ферзь → предупреждение «слишком много: ферзь»",
          page.locator(f"{dlg} .badge.bad:has-text('слишком много: ферзь')").count() == 1)
    FAIL["api_squad_save"] = "Ферзь: не больше 1 на стратега"
    in_dialog(page, "Сохранить отряд")
    err = toast_error(page)
    check("И-32 база отказывает — причина видна игроку", "не больше 1 на стратега" in err, err)
    FAIL.clear(); page.keyboard.press("Escape")

    page.wait_for_timeout(300)
    mark(); squad(page, "Ветер", mine=True).locator("button:has-text('Изменить')").click()
    page.wait_for_selector(f"{dlg} h2:has-text('Отряд «Ветер» — Самум')")
    check("И-33 «Изменить»: название и состав подставлены",
          page.input_value(f"{dlg} input[placeholder='Уникальное в этой игре']") == "Ветер"
          and page.locator(f"{dlg} label.inline:has-text('Ферзь бури') input").is_checked())
    in_dialog(page, "Сохранить отряд")
    c = wait_call(page, "api_squad_save")
    check("И-33 сохранение изменённого отряда → api_squad_save с p_squad=5", has(c, p_squad=5, p_name="Ветер"), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Ветер", mine=True).locator("button:has-text('Распустить')").click()
    page.wait_for_selector(f"{dlg} >> text=Распустить отряд «Ветер»?")
    in_dialog(page, "Отмена")
    page.wait_for_timeout(300)
    check("И-34 «Распустить» → «Отмена» ничего не отправляет", not any(f == "api_squad_delete" for f, _ in calls[mark.at:]))
    squad(page, "Ветер", mine=True).locator("button:has-text('Распустить')").click()
    page.wait_for_selector(f"{dlg} >> text=Распустить отряд «Ветер»?")
    in_dialog(page, "Да")
    c = wait_call(page, "api_squad_delete")
    check("И-34 «Распустить» → «Да» → api_squad_delete", has(c, p_squad=5), c)

    page.wait_for_timeout(300)
    mark(); page.click(f"{mine_card} button:has-text('Пригласить напарника')")
    page.wait_for_selector(f"{dlg} select[name=p]")
    opts = page.locator(f"{dlg} select[name=p] option").all_inner_texts()
    check("И-36 в приглашении нет себя и ведущего", "Самум" not in opts and "Ведущий" not in opts, opts)
    page.select_option(f"{dlg} select[name=p]", label="Зои")
    in_dialog(page, "Пригласить")
    c = wait_call(page, "api_partner_invite")
    check("И-36 «Пригласить напарника» → api_partner_invite (Зои)", has(c, p_game=2, p_partner=2), c)

    T["trophies"] += [{"id": 2, "name": "Рог", "description": "+1 к Лояльности", "bonus_s": 0, "bonus_l": 1, "bonus_v": 0, "squad_id": None, "holder": 5, "status": "kept"},
                      {"id": 3, "name": "Чужой венец", "description": "", "bonus_s": 1, "bonus_l": 0, "bonus_v": 0, "squad_id": None, "holder": 3, "status": "kept"}]
    go(page, "samum-test", "#/game/2", "Трофеи в запасе")
    txt = page.locator(mine_card).inner_text()
    check("И-37 в «Моём участии» — свой трофей из запаса, чужого нет", "«Рог» → в отряд" in txt and "Чужой венец" not in txt, txt[:300])
    mark(); page.click(f"{mine_card} button:has-text('«Рог» → в отряд')")
    page.wait_for_selector(f"{dlg} h2:has-text('Трофей «Рог» в отряд')")
    check("И-37 в окне — только свои отряды", page.locator(f"{dlg} select[name=sq] option").all_inner_texts() == ["Ветер"])
    in_dialog(page, "Взять")
    c = wait_call(page, "api_trophy_equip")
    check("И-37 «Взять» → api_trophy_equip (Рог в «Ветер»)", has(c, p_trophy=2, p_squad=5), c)
    T["games"][1]["status"] = "running"
    go(page, "samum-test", "#/game/2", "Моё участие")
    check("И-37 после начала игры игрок трофей из запаса не берёт", page.locator("button:has-text('→ в отряд')").count() == 0)
    shot(page, "flows-draft")

    print("\nХод игры")
    setup()
    T["turns"][0]["phase"] = "intrigues"
    go(page, "zoi-test", "#/game/1", "Активировать интригу")
    check("И-40 в фазе интриг кнопки отряда серые («Сейчас не фаза действий»)",
          squad(page, "Волки", mine=True).locator("button:has-text('Ход')").get_attribute("title") == "Сейчас не фаза действий")
    mark(); page.click("button:has-text('Активировать интригу')")
    page.fill(f"{dlg} textarea[name=text]", "Шантаж советника")
    in_dialog(page, "Активировать")
    c = wait_call(page, "api_intrigue")
    check("И-40 «Активировать интригу» → api_intrigue с текстом", has(c, p_game=1, p_text="Шантаж советника"), c)

    setup()
    go(page, "zoi-test", "#/game/1", "Пропустить такт")
    mark(); page.click("button:has-text('Пропустить такт')")
    c = wait_call(page, "api_pass_turn")
    check("И-41 Чёрная луна: «Пропустить такт» → api_pass_turn", has(c, p_game=1), c)
    T["game_gifts"][:] = [g for g in T["game_gifts"] if g["gift"] != "chernaya"]
    go(page, "zoi-test", "#/game/1", "Закончить ход")
    check("И-41 без Чёрной луны кнопка называется «Закончить ход»", page.locator("button:has-text('Пропустить такт')").count() == 0)
    setup()

    go(page, "zoi-test", "#/game/1", "Моё участие")
    volki = squad(page, "Волки", mine=True)
    mark(); volki.locator("button:has-text('Ход')").click()
    page.wait_for_selector(f"{dlg} select[name=echo]")
    page.select_option(f"{dlg} select[name=action]", "Перемещение")
    page.select_option(f"{dlg} select[name=echo]", "stopped:1")
    page.fill(f"{dlg} input[name=comment]", "к мельнице")
    in_dialog(page, "Записать")
    c1 = wait_call(page, "api_squad_move"); c2 = wait_call(page, "api_squad_echo")
    check("И-42 «Ход» → api_squad_move (Перемещение)", has(c1, p_squad=1, p_action="Перемещение", p_comment="к мельнице"), c1)
    check("И-42 «Эхо по пути: остановился» → api_squad_echo (stopped, Святилище)", has(c2, p_squad=1, p_echo=1, p_mode="stopped"), c2)

    page.wait_for_timeout(300)
    volki = squad(page, "Волки", mine=True)
    volki.locator("button:has-text('Свойство')").click()
    err = toast_error(page)
    check("И-44 у отряда без свойств Перемещения — понятное сообщение", "нет свойств фазы Перемещения" in err, err)
    volki.locator("button:has-text('Обмен')").click()
    page.wait_for_timeout(400)
    err = " ".join(page.locator(".toast.error").all_inner_texts())
    check("И-43 «Обмен» без второго своего отряда — сообщение", "Нужен второй свой отряд" in err, err)

    mark(); volki.locator("button:has-text('Оплатить')").click()
    page.wait_for_selector(f"{dlg} input[name=amount]")
    page.fill(f"{dlg} input[name=amount]", "2"); page.fill(f"{dlg} input[name=reason]", "переправа")
    in_dialog(page, "Оплатить")
    c = wait_call(page, "api_pay")
    check("И-45 «Оплатить» → api_pay (2 Р.)", has(c, p_squad=1, p_amount=2, p_reason="переправа"), c)

    page.wait_for_timeout(300)
    mark(); squad(page, "Волки", mine=True).locator("button:has-text('Ярость')").click()
    page.wait_for_selector(f"{dlg} select[name=use]")
    page.select_option(f"{dlg} select[name=use]", "remote")
    in_dialog(page, "Потратить")
    c = wait_call(page, "api_rage_spend")
    check("И-47 «Ярость» → api_rage_spend (фишка издалека, вне боя)", has(c, p_squad=1, p_use="remote", p_battle=None), c)

    page.wait_for_timeout(300)
    mark(); squad(page, "Волки", mine=True).locator("button:has-text('Состояние фигур')").click()
    row = page.locator(f"{dlg} .row:has-text('Ладья-натиск')")
    row.locator("select").select_option("damaged")
    row.locator("button:has-text('✓')").click()
    c = wait_call(page, "api_figure_state")
    check("И-48 «Состояние фигур» → api_figure_state (повреждена)", has(c, p_squad=1, p_figure=11, p_state="damaged"), c)
    page.keyboard.press("Escape")

    page.wait_for_timeout(300)
    mark(); squad(page, "Волки", mine=True).locator("button:has-text('Эхо')").click()
    page.wait_for_selector(f"{dlg} select[name=e]")
    page.select_option(f"{dlg} select[name=mode]", "passed")
    in_dialog(page, "Отметить")
    c = wait_call(page, "api_squad_echo")
    check("И-50 кнопка «Эхо» → api_squad_echo (прошёл через Святилище)", has(c, p_squad=1, p_echo=1, p_mode="passed"), c)

    page.wait_for_timeout(300)
    RESULT["api_battle_open"] = 1
    mark(); squad(page, "Волки", mine=True).locator("button:has-text('Напасть')").click()
    page.wait_for_selector(f"{dlg} select[name=t]")
    opts = page.locator(f"{dlg} select[name=t] option").all_inner_texts()
    check("И-46 цели нападения — отряды противника, без уничтоженных и своих",
          any("Совы" in o for o in opts) and not any("Павшие" in o or "Волки" in o for o in opts), opts)
    page.select_option(f"{dlg} select[name=t]", "2")
    in_dialog(page, "Начать бой")
    c = wait_call(page, "api_battle_open")
    page.wait_for_selector("text=Очередь фигур", timeout=15000)
    check("И-46 «Напасть» → api_battle_open и переход на страницу боя",
          has(c, p_attacker=1, p_defender=2) and page.evaluate("location.hash") == "#/battle/1", c)

    # ход Ратбургера без Чёрной луны: Свойство и Обмен у пары с двумя отрядами
    setup()
    T["game_gifts"][:] = [g for g in T["game_gifts"] if g["gift"] != "chernaya"]
    T["turns"][0]["current_strategist"] = 2
    T["squad_moves"].clear()
    go(page, "rat-test", "#/game/1", "Моё участие")
    mark(); squad(page, "Запас", mine=True).locator("button:has-text('Свойство')").click()
    page.wait_for_selector(f"{dlg} select[name=p]")
    page.fill(f"{dlg} input[name=comment]", "рывок на 4 гекса")
    in_dialog(page, "Применить")
    c = wait_call(page, "api_property_use")
    check("И-44 «Свойство» (Перемещение) → api_property_use вне боя",
          has(c, p_squad=3, p_figure=24, p_property="Мобильность", p_battle=None, p_comment="рывок на 4 гекса"), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Совы", mine=True).locator("button:has-text('Обмен')").click()
    page.wait_for_selector(f"{dlg} >> text=Распределите фигуры")
    page.locator(f"{dlg} tr:has-text('Резервный конь') input[value=a]").check()
    page.locator(f"{dlg} tr:has-text('Ладья-лекарь') input[value=b]").check()
    in_dialog(page, "Обменяться")
    c = wait_call(page, "api_exchange")
    check("И-43 «Обмен» → api_exchange: конь к Совам, лекарь в Запас, трофей остаётся",
          c is not None and c["p_a"] == 2 and c["p_b"] == 3 and sorted(c["p_a_figures"]) == [21, 23, 24]
          and c["p_b_figures"] == [22] and c["p_a_trophies"] == [1] and c["p_b_trophies"] == [], c)

    page.wait_for_timeout(300)
    sovy = squad(page, "Совы", mine=True)
    sovy.locator("button:has-text('Трофеи')").click()
    page.wait_for_selector(f"{dlg} >> text=Знамя")
    check("И-61 во время боя «Выкинуть» трофей нельзя", page.locator(f"{dlg} button:has-text('Выкинуть')").is_disabled())
    page.keyboard.press("Escape")
    T["battles"][0].update(status="closed", winner=1)
    go(page, "rat-test", "#/game/1", "Моё участие")
    mark(); squad(page, "Совы", mine=True).locator("button:has-text('Трофеи')").click()
    in_dialog(page, "Выкинуть")
    c = wait_call(page, "api_trophy_drop")
    check("И-61 вне боя «Выкинуть» → api_trophy_drop", has(c, p_trophy=1), c)

    page.wait_for_timeout(300)
    RESULT["api_squad_death"] = 25
    mark(); squad(page, "Павшие", mine=True).locator("button:has-text('Кто погиб?')").click()
    page.wait_for_selector(f"{dlg} button:has-text('Погибает')")
    in_dialog(page, "Погибает")
    c = wait_call(page, "api_squad_death")
    check("И-60 «Кто погиб?» → выбор фигуры → api_squad_death", has(c, p_squad=4, p_figure=25), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Павшие", mine=True).locator("button:has-text('Кто погиб?')").click()
    in_dialog(page, "Жребий")
    c = wait_call(page, "api_squad_death")
    page.wait_for_selector(".toast >> text=Жребий: погибает «Выбывший пёс»", timeout=5000)
    check("И-60 «Жребий» → api_squad_death без фигуры, сайт называет погибшую", has(c, p_squad=4, p_figure=None), c)

    print("\nБой")
    setup()
    T["battle_actions"][:] = []
    go(page, "zoi-test", "#/battle/1", "Очередь фигур")
    check("И-51 нападающая не решает за фигуру защитника", "Решает Ратбургер и Любомир" in page.locator("#view").inner_text()
          and page.locator("button:has-text('Применить')").count() == 0)
    go(page, "rat-test", "#/battle/1", "Очередь фигур")
    mark(); page.click("button:has-text('Применить «Всем друг»')")
    c = wait_call(page, "api_property_use")
    check("И-51 «Применить» в бою → api_property_use (Всем друг, фаза Условие)",
          has(c, p_squad=2, p_figure=23, p_property="Всем друг", p_battle=1) and c["p_params"].get("phase") == "Условие", c)
    mark(); page.click("button:has-text('Пропустить ход фигуры')")
    c = wait_call(page, "api_battle_step")
    check("И-52 «Пропустить ход фигуры» → api_battle_step (skip)", has(c, p_battle=1, p_kind="skip", p_figure=23), c)

    T["battle_actions"][:] = [dict(a) for a in FULL_BATTLE[:1]]
    go(page, "zoi-test", "#/battle/1", "Очередь фигур")
    check("И-53 недоступное свойство помечено с причиной (Натиск — «Всем друг»)",
          "«Всем друг» противника" in page.locator("section.card:has(h2:has-text('Очередь фигур'))").inner_text())
    check("И-53 своя фигура: «Применить «Осведомленность»» и «Пропустить»",
          page.locator("button:has-text('Применить «Осведомленность»')").count() == 1)

    T["battle_actions"][:] = [dict(a) for a in FULL_BATTLE[:2]]
    go(page, "zoi-test", "#/battle/1", "Фаза Риска")
    now = page.locator("section.card:has(h2:text-is('Сейчас'))")
    check("И-54 бросок только за свой отряд (у Сов — «ждём броска»)",
          now.locator("button:has-text('Бросить d10')").count() == 1 and "ждём броска" in now.inner_text())
    mark(); now.locator("button:has-text('Бросить d10')").click()
    c = wait_call(page, "api_roll")
    page.wait_for_selector(".toast >> text=Выпало 7", timeout=5000)
    check("И-54 «Бросить d10» → api_roll (риск, не вручную), сайт пишет результат",
          has(c, p_battle=1, p_squad=1, p_purpose="risk", p_manual=None), c)
    mark(); page.click("button:has-text('Потратить Ярость: +5 к Силе')")
    c = wait_call(page, "api_rage_spend")
    check("И-56 Ярость в бою → api_rage_spend (power, бой 1)", has(c, p_squad=1, p_use="power", p_battle=1), c)
    mark(); page.select_option("select[aria-label='Состояние Ладья-натиск']", "damaged")
    c = wait_call(page, "api_figure_state")
    check("И-57 список состояния в бою → api_figure_state с пометкой боя", has(c, p_figure=11, p_state="damaged", p_comment="Бой #1"), c)
    check("И-57 у чужих фигур списков состояния нет", page.locator("select[aria-label='Состояние Пешка-шпион']").count() == 0)

    spy = {"id": 5, "battle_id": 1, "kind": "property", "squad_id": 2, "figure_id": 21, "property": "Шпионаж", "params": {"phase": "Риск"}, "roll": 9, "cost": 0}
    T["battle_actions"][:] = [dict(a) for a in FULL_BATTLE] + [spy]
    go(page, "zoi-test", "#/battle/1", "Проигравший выбирает")
    check("И-55 повреждение выбирает проигравший (у Зои кнопок нет)", page.locator("button:has-text('Повредить')").count() == 0)
    go(page, "rat-test", "#/battle/1", "Проигравший выбирает")
    mark(); page.locator("button:has-text('Повредить')").first.click()
    c = wait_call(page, "api_battle_step")
    check("И-55 «Повредить …» → api_battle_step (damage, отряд Сов)", has(c, p_battle=1, p_kind="damage", p_squad=2), c)

    T["battle_actions"].append({"id": 6, "battle_id": 1, "kind": "damage", "squad_id": 2, "figure_id": 21, "property": None, "params": {}, "roll": None, "cost": 0})
    T["battle_actions"] += [{"id": 7 + i, "battle_id": 1, "kind": "skip", "squad_id": s, "figure_id": f, "property": None, "params": {"phase": "Ущерб"}, "roll": None, "cost": 0}
                            for i, (s, f) in enumerate([(2, 22), (1, 12)])]
    go(page, "rat-test", "#/battle/1", "Исход")
    check("И-58 защитник не записывает итог", "Записать итог может нападающий или ведущий" in page.locator("#view").inner_text())
    go(page, "zoi-test", "#/battle/1", "Исход")
    mark(); page.click("button:has-text('Завершить бой и записать итог')")
    c = wait_call(page, "api_battle_close")
    check("И-58 «Завершить бой» → api_battle_close (победили Волки, итог 22:20)",
          has(c, p_battle=1, p_winner=1) and c["p_result"].get("totals") == {"attacker": 22, "defender": 20}, c)
    shot(page, "flows-battle-outcome")

    T["battles"][0].update(status="closed", winner=1, result={"reason": "Сила + кубик", "totals": {"attacker": 22, "defender": 20}})
    go(page, "rat-test", "#/battle/1", "Итог боя")
    check("И-59 проигравший не может забрать трофей", page.locator("button:has-text('Забрать')").count() == 0)
    go(page, "zoi-test", "#/battle/1", "Итог боя")
    mark(); page.click("button:has-text('Забрать «Знамя»')")
    c = wait_call(page, "api_trophy_take")
    check("И-59 победитель «Забрать «Знамя»» → api_trophy_take", has(c, p_battle=1, p_trophy=1), c)
    T["events"].append({"id": 9, "at": "2026-10-20T18:00:00Z", "actor": 2, "kind": "trophy_take", "game_id": 1, "figure_id": None, "squad_id": 1,
                        "player_id": None, "amount": None, "data": {"battle": 1}, "comment": None, "reverted": False})
    go(page, "zoi-test", "#/battle/1", "Итог боя")
    check("И-59 второй трофей за тот же бой взять нельзя", page.locator("button:has-text('Забрать')").count() == 0
          and "Трофей за этот бой уже забран" in page.locator("#view").inner_text())

    # ═════════════════════ ВЕДУЩИЙ ═════════════════════
    print("\nВедущий: доступ")
    setup()
    go(page, "zoi-test", "#/admin", "Только для ведущего")
    check("В-01 игроку раздел «Ведущий» закрыт и скрыт в меню", page.locator("#nav-admin").is_hidden())
    go(page, "zoi-test", "#/game/1", "Отряды")
    check("В-01 игроку не виден блок «Ведущему»", page.locator("h2:text-is('Ведущему')").count() == 0)
    go(page, "admin-test", "#/admin", "Последние записи журнала")
    check("В-01 ведущему виден раздел и пункт меню", page.locator("#nav-admin").is_visible())

    print("\nВедущий: подготовка игры")
    RESULT["api_admin_game"] = 2
    go(page, "admin-test", "#/games", "Все игры")
    mark(); page.click("button:has-text('+ Новая игра')")
    page.fill(f"{dlg} input[name=title]", "Сбор у старой мельницы")
    in_dialog(page, "Создать")
    c = wait_call(page, "api_admin_game")
    page.wait_for_selector("text=Подготовка", timeout=15000)
    check("В-10 «+ Новая игра» → api_admin_game (новая, сбор отрядов) и переход к игре",
          has(c, p_id=None, p_title="Сбор у старой мельницы", p_status="draft") and page.evaluate("location.hash") == "#/game/2", c)
    RESULT.clear()

    mark(); page.check("label:has-text('Чёрная луна') input")
    c = wait_call(page, "api_admin_gift")
    check("В-11 галочка дара → api_admin_gift (Чёрная луна вкл.)", has(c, p_game=2, p_gift="chernaya", p_on=True), c)
    page.wait_for_timeout(500)
    FAIL["api_admin_gift"] = "Нет прав"
    page.check("label:has-text('Алая луна') input")
    toast_error(page)
    page.wait_for_timeout(300)
    check("В-11 при отказе базы галочка возвращается", not page.locator("label:has-text('Алая луна') input").is_checked())
    FAIL.clear()

    mark(); page.fill("input[aria-label='Инициатива Самум']", "7")
    page.locator("label.inline:has(input[aria-label='Инициатива Самум']) button").click()
    c = wait_call(page, "api_admin_initiative")
    check("В-12 инициатива → api_admin_initiative (Самум 7)", has(c, p_strategist=3, p_value=7), c)

    page.wait_for_timeout(300)
    mark(); page.click("button:has-text('Добавить стратега')")
    page.wait_for_selector(f"{dlg} select[name=p]")
    opts = page.locator(f"{dlg} select[name=p] option").all_inner_texts()
    check("В-13 «Добавить стратега»: предлагаются только не участвующие", sorted(opts) == ["Зои", "Ратбургер"], opts)
    page.select_option(f"{dlg} select[name=p]", label="Зои")
    in_dialog(page, "Добавить")
    c = wait_call(page, "api_admin_join")
    check("В-13 → api_admin_join (Зои в игру 2)", has(c, p_game=2, p_player=2), c)

    page.wait_for_timeout(300)
    mark(); page.click("button:has-text('Сделать напарниками')")
    page.select_option(f"{dlg} select[name=a]", label="Самум")
    page.select_option(f"{dlg} select[name=b]", label="Любомир")
    in_dialog(page, "Сделать напарниками")
    c = wait_call(page, "api_admin_pair")
    check("В-14 «Сделать напарниками» → api_admin_pair", has(c, p_game=2, p_a=5, p_b=4), c)

    page.wait_for_timeout(300)
    mark(); page.locator(".row:has(h3:text-is('Самум')) button:has-text('+ Отряд')").click()
    page.wait_for_selector(f"{dlg} h2:has-text('Новый отряд — Самум')")
    page.fill(f"{dlg} input[placeholder='Уникальное в этой игре']", "Пески")
    page.check(f"{dlg} label:has-text('показать все фигуры') input")
    check("В-15 «показать все фигуры» открывает чужие фигуры", page.locator(f"{dlg} label.inline:has-text('Пешка-шпион')").count() == 1)
    page.check(f"{dlg} label.inline:has-text('Пешка ветра') input")
    in_dialog(page, "Сохранить отряд")
    c = wait_call(page, "api_squad_save")
    check("В-15 «+ Отряд» за стратега → api_squad_save с p_strategist=3", has(c, p_game=2, p_strategist=3, p_figures=[28]), c)

    page.wait_for_timeout(300)
    mark(); page.click("button:has-text('Начать игру')")
    page.wait_for_selector(f"{dlg} >> text=Составы отрядов зафиксируются")
    in_dialog(page, "Да")
    c = wait_call(page, "api_admin_game")
    check("В-16 «Начать игру» → подтверждение → api_admin_game (running)", has(c, p_id=2, p_status="running", p_title="Сбор у старой мельницы"), c)

    print("\nВедущий: Эхо")
    go(page, "admin-test", "#/game/1", "Ведущему")
    mark(); page.click("section.card:has(h2:text-is('Ведущему')) button:has-text('Эхо…')")
    page.wait_for_selector(f"{dlg} h2:has-text('видит только ведущий')")
    check("В-17 список Эхо ведущего (api_admin_echoes)", "Святилище" in dialog_text(page) and wait_call(page, "api_admin_echoes") is not None)
    in_dialog(page, "+ Эхо")
    page.wait_for_selector(f"{dlg} h2:has-text('Новое Эхо')")
    check("В-17 новое Эхо по умолчанию скрыто", page.input_value(f"{dlg} select[name=status]") == "hidden")
    page.fill(f"{dlg} input[name=name]", "Болото")
    page.fill(f"{dlg} textarea[name=description]", "Движение дороже")
    page.select_option(f"{dlg} select[name=blocked]", ["Мобильность"])
    page.fill(f"{dlg} input[name=move]", "1")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_admin_echo")
    check("В-17 «+ Эхо» → api_admin_echo (скрытое, цена движения 1, без Мобильности)",
          has(c, p_id=None, p_game=1, p_name="Болото", p_status="hidden", p_move_cost=1, p_blocked=["Мобильность"]), c)
    page.wait_for_timeout(300)
    mark(); page.click("section.card:has(h2:text-is('Ведущему')) button:has-text('Эхо…')")
    page.wait_for_selector(f"{dlg} button:has-text('Изменить')")
    in_dialog(page, "Изменить")
    page.wait_for_selector(f"{dlg} h2:has-text('Эхо «Святилище»')")
    page.select_option(f"{dlg} select[name=status]", "ended")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_admin_echo")
    check("В-17 «Изменить» Эхо → «закончилось» → api_admin_echo с p_id=1", has(c, p_id=1, p_status="ended", p_name="Святилище"), c)

    print("\nВедущий: ход")
    page.wait_for_timeout(300)
    RESULT["api_admin_turn_start"] = 3
    mark(); page.click("button:has-text('Новый ход')")
    page.fill(f"{dlg} input[name=tacts]", "3")
    in_dialog(page, "Начать ход")
    c = wait_call(page, "api_admin_turn_start")
    page.wait_for_selector(".toast >> text=Ход 3: интриги", timeout=5000)
    check("В-20 «Новый ход» (Чёрная луна, 3 такта) → api_admin_turn_start", has(c, p_game=1, p_tacts=3), c)
    RESULT.clear()
    page.wait_for_timeout(300)
    mark(); page.click("button:has-text('Передать ход')")
    page.select_option(f"{dlg} select[name=st]", "2")
    page.fill(f"{dlg} input[name=tact]", "2")
    in_dialog(page, "Передать")
    c = wait_call(page, "api_admin_turn_set")
    check("В-22 «Передать ход…» → api_admin_turn_set (Ратбургер и Любомир, такт 2)", has(c, p_game=1, p_strategist=2, p_tact=2), c)
    T["turns"][0]["phase"] = "intrigues"
    go(page, "admin-test", "#/game/1", "Интриги закончены")
    mark(); page.click("button:has-text('Интриги закончены')")
    c = wait_call(page, "api_admin_turn_actions")
    check("В-21 «Интриги закончены → действия» → api_admin_turn_actions", has(c, p_game=1), c)
    check("В-21 ведущий тоже может записать интригу", page.locator("button:has-text('Активировать интригу')").count() == 1)
    T["turns"][0]["phase"] = "actions"

    print("\nВедущий: Ресурсы")
    go(page, "admin-test", "#/people", "Стратеги и Ресурсы")
    check("В-30 у ведущего нет «Передать Ресурсы»", page.locator("button:has-text('Передать Ресурсы')").count() == 0)
    pair = page.locator("tr:has-text('Ратбургер и Любомир')")
    mark(); pair.locator("button:has-text('± Ресурсы')").click()
    page.wait_for_selector(f"{dlg} >> text=Пара — Ресурсы пойдут в общий кошелёк")
    page.fill(f"{dlg} input[name=amount]", "-2"); page.fill(f"{dlg} input[name=comment]", "штраф")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_admin_resources")
    check("В-30 «± Ресурсы» паре (минус) → api_admin_resources первому из пары", has(c, p_player=3, p_amount=-2, p_comment="штраф"), c)
    page.wait_for_timeout(300)
    mark(); page.locator("tr:has-text('Ратбургер и Любомир') button:has-text('Доп. отряды')").click()
    page.select_option(f"{dlg} select[name=p]", "4")
    page.fill(f"{dlg} input[name=bonus]", "3")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_admin_bonus")
    check("В-31 «Доп. отряды» паре: выбор, кому → api_admin_bonus (Любомир 3)", has(c, p_player=4, p_bonus=3), c)
    page.wait_for_timeout(300)
    page.click("summary:has-text('Не участвуют')")
    mark(); page.locator("tr:has-text('Самум') button:has-text('± Ресурсы')").click()
    page.fill(f"{dlg} input[name=amount]", "5")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_admin_resources")
    check("В-30 «± Ресурсы» не участвующему → api_admin_resources (Самум +5)", has(c, p_player=5, p_amount=5), c)

    print("\nВедущий: во время игры")
    go(page, "admin-test", "#/game/1", "Ведущему")
    mark(); squad(page, "Волки").locator("button:has-text('+ Трофей')").click()
    page.fill(f"{dlg} input[name=name]", "Кубок")
    page.fill(f"{dlg} input[name=s]", "1")
    in_dialog(page, "Выдать")
    c = wait_call(page, "api_admin_trophy_give")
    check("В-40 «+ Трофей» → api_admin_trophy_give (+1 Сила)", has(c, p_squad=1, p_name="Кубок", p_s=1, p_l=0, p_v=0), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Волки").locator("button:has-text('Ярость =')").click()
    page.fill(f"{dlg} input[name=rage]", "3")
    in_dialog(page, "Сохранить")
    c = wait_call(page, "api_admin_rage")
    check("В-41 «Ярость =» → api_admin_rage (3)", has(c, p_squad=1, p_rage=3), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Волки").locator("button:has-text('Фигуру в другой отряд')").click()
    page.select_option(f"{dlg} select[name=f]", "12")
    page.select_option(f"{dlg} select[name=to]", "2")
    page.fill(f"{dlg} input[name=comment]", "Подкуп")
    in_dialog(page, "Переместить")
    c = wait_call(page, "api_admin_move_figure")
    check("В-42 «Фигуру в другой отряд» → api_admin_move_figure (пешка к Совам)", has(c, p_from=1, p_to=2, p_figure=12, p_comment="Подкуп"), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Запас").locator("button:has-text('Распустить')").click()
    in_dialog(page, "Да")
    c = wait_call(page, "api_squad_delete")
    check("В-43 ведущий распускает отряд в идущей игре → api_squad_delete", has(c, p_squad=3), c)
    page.wait_for_timeout(300)
    mark(); squad(page, "Запас").locator("button:has-text('Изменить')").click()
    page.wait_for_selector(f"{dlg} h2:has-text('Отряд «Запас»')")
    check("В-43 при правке отряда в идущей игре — предупреждение о состоянии фигур", "сохранят своё состояние" in dialog_text(page))
    page.keyboard.press("Escape")

    print("\nВедущий: бой")
    T["battle_actions"][:] = [dict(a) for a in FULL_BATTLE[:2]]
    go(page, "admin-test", "#/battle/1", "Фаза Риска")
    check("В-50 ведущий может бросить за обе стороны", page.locator("button:has-text('Бросить d10')").count() == 2)
    mark(); page.locator("input[aria-label='Бросок вручную']").nth(1).fill("4")
    page.locator("button:has-text('Ввести (ведущий)')").nth(1).click()
    c = wait_call(page, "api_roll")
    check("В-50 «Ввести (ведущий)» → api_roll с живым кубиком (Совы, 4)", has(c, p_squad=2, p_manual=4, p_purpose="risk"), c)
    T["battle_actions"][:] = [dict(a) for a in FULL_BATTLE]
    go(page, "admin-test", "#/battle/1", "Шаги боя")
    check("В-51 у Шпионажа есть поле живого кубика", page.locator("input[placeholder='кубик']").count() == 1)
    mark(); page.locator("input[placeholder='кубик']").fill("2")
    page.click("button:has-text('Применить «Шпионаж»')")
    c = wait_call(page, "api_property_use")
    check("В-51 Шпионаж с живым кубиком → api_property_use (manual_roll 2)", has(c, p_property="Шпионаж") and c["p_params"].get("manual_roll") == 2, c)
    steps = page.locator("section.card:has(h2:has-text('Шаги боя')) li")
    check("В-52 «Шаги боя» перечисляют все 4 шага", steps.count() == 4, steps.count())
    mark(); steps.nth(2).locator("button:has-text('Отменить')").click()
    c = wait_call(page, "api_admin_battle_undo")
    check("В-52 «Отменить» шаг боя → api_admin_battle_undo (#3)", has(c, p_action=3), c)

    print("\nВедущий: конец игры")
    go(page, "admin-test", "#/game/1", "Ведущему")
    mark(); page.click("button:has-text('Разделить кошелёк')")
    check("В-60 по умолчанию кошелёк делится пополам (3 и 3)",
          page.input_value(f"{dlg} input[name=p3]") == "3" and page.input_value(f"{dlg} input[name=p4]") == "3")
    page.fill(f"{dlg} input[name=p3]", "4"); page.fill(f"{dlg} input[name=p4]", "2")
    in_dialog(page, "Разделить")
    c = wait_call(page, "api_admin_split_wallet")
    check("В-60 «Разделить кошелёк» → api_admin_split_wallet (4 и 2)", has(c, p_strategist=2, p_shares={"3": 4, "4": 2}), c)
    page.wait_for_timeout(300)
    mark(); row = page.locator(".row:has-text('«Знамя» (Совы)')")
    row.locator("select").select_option(label="остаётся у Ратбургер")
    row.locator("button:has-text('✓')").click()
    c = wait_call(page, "api_admin_trophy_end")
    check("В-61 судьба трофея → api_admin_trophy_end (остаётся у Ратбургера)", has(c, p_trophy=1, p_holder=3), c)
    page.wait_for_timeout(300)
    FAIL["api_admin_game"] = "Нельзя закончить: в отряде «Павшие» не выбрана погибшая фигура"
    mark(); page.click("button:has-text('Закончить игру')")
    in_dialog(page, "Да")
    err = toast_error(page)
    check("В-62 «Закончить игру» с нерешённым → сайт объясняет, что не решено", "не выбрана погибшая фигура" in err, err)
    c = wait_call(page, "api_admin_game")
    check("В-62 запрос ушёл со статусом closed", has(c, p_id=1, p_status="closed"), c)
    FAIL.clear(); page.keyboard.press("Escape")

    print("\nВедущий: журнал")
    T["events"][1]["reverted"] = True
    go(page, "admin-test", "#/admin", "Последние записи журнала")
    log = page.locator("section.card:has(h2:has-text('Последние записи журнала')) li")
    check("В-70 у отменённой записи нет кнопки «Отменить»",
          log.count() == 4 and page.locator("li.reverted button:has-text('Отменить')").count() == 0 and log.locator("button:has-text('Отменить')").count() == 3,
          (log.count(), log.locator("button:has-text('Отменить')").count()))
    mark(); log.locator("button:has-text('Отменить')").first.click()
    c = wait_call(page, "api_admin_revert")
    check("В-70 «Отменить» запись → api_admin_revert", c is not None and c["p_event"] in (1, 3, 4), c)
    go(page, "zoi-test", "#/log", "Журнал")
    check("В-71 общий журнал виден игроку; отменённые зачёркнуты",
          page.locator("ul.log li").count() == 4 and page.locator("ul.log li.reverted").count() == 1)

    print("\nЖурнал: метки игр, «Показать ещё», выгрузка")
    setup()
    T["events"].append({"id": 5, "at": "2026-10-19T10:00:00Z", "actor": 2, "kind": "resources_transfer", "game_id": None, "figure_id": None,
                        "squad_id": None, "player_id": 3, "amount": 1, "data": {"from": 2, "to": 3}, "comment": None, "reverted": False})
    go(page, "admin-test", "#/admin", "Последние записи журнала")
    log = page.locator("section.card:has(h2:has-text('Последние записи журнала')) li")
    check("В-72 журнал ведущего: у записей игры метка «Пять ликов одной Луны», у передачи Ресурсов — нет",
          log.locator("a.log-game").count() == 4 and log.filter(has_text="Передача").locator("a.log-game").count() == 0,
          log.locator("a.log-game").count())
    go(page, None, "#/log", "Журнал")
    badge = page.locator("ul.log li a.log-game").first
    check("И-70 у записи игры — метка-ссылка на игру; у записи без игры метки нет",
          page.locator("ul.log li a.log-game").count() == 4 and badge.inner_text() == "Пять ликов одной Луны"
          and badge.get_attribute("href") == "#/game/1"
          and page.locator("ul.log li", has_text="Передача").locator("a.log-game").count() == 0)
    T["events"][:] = [{"id": 1000 - i, "at": "2026-10-20T%02d:%02d:00Z" % (23 - i // 60, 59 - i % 60), "actor": 2,
                       "kind": "roll", "game_id": 1 if i % 2 else None, "figure_id": None, "squad_id": None, "player_id": None,
                       "amount": i % 10 + 1, "data": {}, "comment": "№%d" % i, "reverted": False} for i in range(650)]
    go(page, None, "#/log", "Журнал")
    li = lambda: page.locator("ul.log li").count()
    more = page.locator("button:has-text('Показать ещё')")
    check("И-71 сначала 300 записей и кнопка «Показать ещё 300»", li() == 300 and more.is_visible(), li())
    more.click(); page.wait_for_function("() => document.querySelectorAll('ul.log li').length === 600", timeout=10000)
    check("И-71 «Показать ещё» → 600, порядок сохранён", li() == 600 and "№599" in page.locator("ul.log li").nth(599).inner_text())
    more.click(); page.wait_for_function("() => document.querySelectorAll('ul.log li').length === 650", timeout=10000)
    check("И-71 последняя порция → 650, кнопки нет, «Это все записи»",
          li() == 650 and more.is_hidden() and page.locator("text=Это все записи.").is_visible(), li())
    with page.expect_download(timeout=15000) as dl:
        page.click("button:has-text('Скачать весь журнал')")
    text = pathlib.Path(dl.value.path()).read_text(encoding="utf-8")
    lines = text.lstrip("﻿").splitlines()
    check("И-72 «Скачать весь журнал (CSV)» → все 650 записей с заголовком и игрой",
          text.startswith("﻿") and lines[0] == "№;Время;Игра;Кто;Событие;Комментарий;Отменено" and len(lines) == 651
          and lines[1].startswith("1000;") and ";;Зои;Бросок d10: 1;№0;" in lines[1] and ";Пять ликов одной Луны;Зои;" in lines[2]
          and dl.value.suggested_filename.endswith(".csv"), (len(lines), lines[:3]))
    b.close()

srv.shutdown()
print("\nошибки в консоли:" if errors else "\nошибок в консоли нет", *errors, sep="\n  ")
if check.failed: print("не прошли:", *check.failed, sep="\n  ")
print(f"Итого: {check.ok} ✓, {check.fail} ✗")
sys.exit(1 if check.fail or errors else 0)
