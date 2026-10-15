"""Дымовая проверка сайта в Chromium против живой базы — только чтение (и вход по коду).

  python tests/smoke.py [код_для_входа] [папка_для_снимков]
"""
import functools, http.server, pathlib, sys, threading
from playwright.sync_api import sync_playwright

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parent.parent
CODE = sys.argv[1] if len(sys.argv) > 1 else None
SHOTS = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
handler = functools.partial(Quiet, directory=str(ROOT))
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}/index.html"

errors = []
with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 1280, "height": 900})
    page.on("console", lambda m: m.type == "error" and errors.append(m.text))
    page.on("pageerror", lambda e: errors.append(str(e)))

    def visit(route, name, wait_text=None):
        page.goto(BASE + route)
        page.wait_for_function("() => !document.querySelector('#view .loading')", timeout=20000)
        if wait_text:
            page.wait_for_selector(f"text={wait_text}", timeout=10000)
        h1 = page.locator("#view h1, #view h2").first.inner_text() if page.locator("#view h1, #view h2").count() else "?"
        print(f"  {name}: «{h1}»")
        if SHOTS:
            page.screenshot(path=str(SHOTS / f"{name}.png"), full_page=False)

    visit("#/", "figures", "Все фигуры")
    rows = page.locator("tbody tr").count()
    print("    строк в таблице:", rows)
    page.fill("input[type=search]", "Ратбургер")
    print("    поиск «Ратбургер»:", page.locator("tbody tr").count())
    page.click("tbody tr >> visible=true >> nth=0")
    page.wait_for_selector("dialog[open]", timeout=10000)
    print("    карточка фигуры:", page.locator("dialog h2").first.inner_text())
    if SHOTS: page.screenshot(path=str(SHOTS / "figure-card.png"))
    page.keyboard.press("Escape")
    visit("#/people", "people")
    print("    лишний текст «null»:", "есть" if "\nnull\n" in "\n" + page.locator("#view").inner_text() + "\n" else "нет")
    print("    столбец «Другие имена»:", "есть" if "Другие имена" in page.locator("#view").inner_text() else "убран")
    visit("#/games", "games")
    visit("#/rules", "rules")
    visit("#/log", "log")
    visit("#/help", "help-player", "Ход отряда")
    visit("#/help/admin", "help-admin", "Конец игры")
    if CODE:
        page.goto(BASE + "#/")
        page.wait_for_function("() => !document.querySelector('#view .loading')", timeout=20000)
        page.fill("#who input", CODE)
        page.click("#who button")
        page.wait_for_selector("#who .me", timeout=10000)
        print("  вход:", page.locator("#who").inner_text())
        visit("#/admin", "admin")
    # узкий экран
    page.set_viewport_size({"width": 390, "height": 844})
    visit("#/", "figures-phone")
    sw = page.evaluate("document.documentElement.scrollWidth")
    print("    ширина страницы на телефоне:", sw, "(экран 390)")
    b.close()

srv.shutdown()
print("\nошибки в консоли:" if errors else "\nошибок в консоли нет", *errors, sep="\n  ")
sys.exit(1 if errors else 0)
