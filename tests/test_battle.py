"""Проверка js/battle.js в V8 (mini-racer): пример боя из правил и крайние случаи.

  python tests/test_battle.py
"""
import json, pathlib, sys
from py_mini_racer import MiniRacer

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parent.parent
js = MiniRacer()
js.eval((ROOT / "js" / "battle.js").read_text(encoding="utf-8"))
PROPS = {p["name"]: {"phase": p["phase"], "cost": p.get("cost", "auto")}
         for p in json.loads((ROOT / "supabase" / "properties.json").read_text(encoding="utf-8"))}
import re
for name, p in PROPS.items():   # цена как в make_seed.py
    if p["cost"] == "auto":
        desc = next(x["description"] for x in json.loads((ROOT / "supabase" / "properties.json").read_text(encoding="utf-8")) if x["name"] == name)
        m = re.search(r"(?:Потрать|Заплати)\s+(\d+)\s+Ресурс", desc)
        p["cost"] = int(m.group(1)) if m else 0

ok = fail = 0
def check(name, cond, info=""):
    global ok, fail
    if cond: ok += 1; print(f"  ✓ {name}")
    else: fail += 1; print(f"  ✗ {name} {info}")

def compute(state):
    state = dict(state, properties=PROPS)
    return js.eval(f"Battle.compute({json.dumps(state, ensure_ascii=False)})")

def fig(i, name, nom, s, l, prop, st="ok"):
    return {"id": i, "name": name, "nominal": nom, "s": s, "l": l, "v": 1, "properties": [prop], "state": st}

aid = [0]
def act(kind, squad, figure=None, prop=None, params=None, roll=None, cost=0):
    aid[0] += 1
    return {"id": aid[0], "kind": kind, "squad_id": squad, "figure_id": figure, "property": prop,
            "params": params or {}, "roll": roll, "cost": cost}

print("Пример боя из правил")
A = {"squad_id": 1, "name": "Отряд 1", "figures": [
    fig(11, "Ладья", "ладья", 5, 3, "Натиск"), fig(12, "Пешка", "пешка", 1, 2, "Добивание"),
    fig(13, "Конь", "конь", 2, 2, "Осведомленность")]}
D = {"squad_id": 2, "name": "Отряд 2", "figures": [
    fig(21, "Пешка", "пешка", 3, 1, "Шпионаж"), fig(22, "Ладья", "ладья", 7, 2, "Лечение"),
    fig(23, "Офицер", "офицер", 5, 3, "Всем друг")]}
acts = []
st = lambda: {"attacker": A, "defender": D, "actions": acts, "gifts": [], "echoBlocked": []}

r = compute(st())
check("первым ходит офицер «Всем друг» (фаза Условий)", r["need"] and r["need"]["figure"]["id"] == 23, r["need"])
acts.append(act("property", 2, 23, "Всем друг"))
r = compute(st())
lad = next(e for e in r["entries"] if e["key"] == "11:Сила")
check("Натиск недоступен из-за «Всем друг»", lad["status"] == "unavailable" and "Всем друг" in lad["reason"], lad.get("reason"))
check("ходит конь с Осведомленностью", r["need"]["figure"]["id"] == 13)
check("до Осведомленности: 8 против 15", r["strength"]["attacker"]["total"] == 8 and r["strength"]["defender"]["total"] == 15)
acts.append(act("property", 1, 13, "Осведомленность"))
r = compute(st())
check("Сила 13 и 15", r["strength"]["attacker"]["total"] == 13 and r["strength"]["defender"]["total"] == 15,
      (r["strength"]["attacker"]["total"], r["strength"]["defender"]["total"]))
check("ждём броски обоих", r["need"]["type"] == "roll" and len(r["need"]["sides"]) == 2)
acts.append(act("roll", 2, roll=3, params={"purpose": "risk"}))
acts.append(act("roll", 1, roll=10, params={"purpose": "risk"}))
r = compute(st())
check("ходит пешка со Шпионажем", r["need"]["type"] == "decide" and r["need"]["figure"]["id"] == 21)
acts.append(act("property", 2, 21, "Шпионаж", roll=9))
r = compute(st())
check("после Шпионажа у отряда 1 берётся 9", r["rolls"]["attacker"]["final"] == 9)
check("победил отряд 1 (13+9=22 > 15+3=18)", r["outcome"] and r["outcome"]["winner"] == "attacker"
      and r["outcome"]["totals"] == {"attacker": 22, "defender": 18}, r["outcome"])
check("проигравший выбирает, какую фигуру повредить", r["need"]["type"] == "damage" and r["need"]["side"] == "defender")
acts.append(act("damage", 2, 21))
D["figures"][0]["state"] = "damaged"
r = compute(st())
check("Лечение ладьи раньше Добивания пешки", r["need"]["figure"]["id"] == 22)
acts.append(act("property", 2, 22, "Лечение", cost=1))
D["figures"][0]["state"] = "ok"
r = compute(st())
dob = next(e for e in r["entries"] if e["key"] == "12:Ущерб")
check("Добивание недоступно", dob["status"] == "unavailable", dob)
check("бой закончен", r["phase"] == "Итог" and r["need"] is None, (r["phase"], r["need"]))

print("\nКрайние случаи")
def duel(a_props, d_props, a_roll, d_roll, extra=None, gifts=()):
    A2 = {"squad_id": 1, "name": "А", "figures": [fig(31, "А1", "ладья", 5, 1, a_props[0])]}
    D2 = {"squad_id": 2, "name": "Д", "figures": [fig(41, "Д1", "ладья", 5, 1, d_props[0])]}
    seq = list(extra or [])
    while True:
        r = compute({"attacker": A2, "defender": D2, "actions": seq, "gifts": list(gifts), "echoBlocked": []})
        n = r["need"]
        if not n: return r
        if n["type"] == "roll":
            seq.append(act("roll", 1, roll=a_roll, params={"purpose": "risk"}))
            seq.append(act("roll", 2, roll=d_roll, params={"purpose": "risk"}))
        elif n["type"] == "decide":
            e = next(e for e in r["entries"] if e["key"] == n["key"])
            o = next(o for o in e["options"] if o["available"])
            seq.append(act("property", 1 if n["side"] == "attacker" else 2, n["figure"]["id"], o["property"],
                           cost=(2 if o["property"] == "Натиск" else (o["cost"] or 0))))
        elif n["type"] == "damage":
            seq.append(act("damage", 1 if n["side"] == "attacker" else 2, n["candidates"][0]["id"]))
            for f in (A2 if n["side"] == "attacker" else D2)["figures"]:
                if f["id"] == n["candidates"][0]["id"]: f["state"] = "damaged"

r = duel(["Мобильность"], ["Мобильность"], 10, 10)
check("10 у обоих — ничья", r["outcome"]["winner"] is None and "обе" in r["outcome"]["reason"], r["outcome"])
r = duel(["Мобильность"], ["Мобильность"], 10, 9)
check("10 — автопобеда", r["outcome"]["winner"] == "attacker" and "10" in r["outcome"]["reason"])
r = duel(["Штурм"], ["Укрепление"], 3, 3)
check("Штурм против Укрепления: 10 и 10, ничья", r["strength"]["attacker"]["total"] == 10 and r["strength"]["defender"]["total"] == 10 and r["outcome"]["winner"] is None)
r = duel(["Натиск"], ["Мобильность"], 1, 1)
check("Натиск за 2 Ресурса: +8", r["strength"]["attacker"]["total"] == 13)
r = duel(["Мобильность"], ["Переговоры"], 9, 1)
check("Переговоры — ничья при любом кубике", r["outcome"]["winner"] is None and r["outcome"]["reason"] == "Переговоры")
r = duel(["Только ты и я"], ["Мобильность"], 8, 9)
check("Только ты и я на 8 — автопобеда", r["outcome"]["winner"] == "attacker")
r = duel(["Только ты и я"], ["Мобильность"], 7, 1)
e = next(e for e in r["entries"] if e["key"] == "31:Риск")
check("Только ты и я на 7 — недоступно", e["status"] == "unavailable" and "8" in e["reason"])
r = duel(["Один в поле воин"], ["Мобильность"], 1, 1)
check("Один в поле воин утраивает: 15", r["strength"]["attacker"]["total"] == 15)
r = duel(["Мат"], ["Мобильность"], 1, 1)
check("Мат добавляет Силу противника: 10", r["strength"]["attacker"]["total"] == 10)
r = duel(["Мобильность"], ["Совершенная оборона"], 1, 1)
check("Совершенная оборона защитника срабатывает", any(e["key"] == "41:Условие" and e["status"] == "done" for e in r["entries"]))
r = duel(["Провокация"], ["Мобильность"], 1, 1)
check("Провокация: базовая Сила защитника 0", r["strength"]["defender"]["total"] == 0, r["strength"]["defender"])
r = duel(["Мобильность"], ["Мобильность"], 2, 2, extra=[act("rage", 1, params={"use": "power"})])
check("Ярость +5 к Силе", r["strength"]["attacker"]["total"] == 10)

print("\nОчередь: номинал → Лояльность → атакующий")
A3 = {"squad_id": 1, "name": "А", "figures": [fig(51, "пешка А", "пешка", 1, 5, "Штурм"), fig(52, "конь А", "конь", 1, 1, "Штурм")]}
D3 = {"squad_id": 2, "name": "Д", "figures": [fig(61, "пешка Д", "пешка", 1, 5, "Укрепление"), fig(62, "пешка Д2", "пешка", 1, 9, "Укрепление")]}
r = compute({"attacker": A3, "defender": D3, "actions": [], "gifts": [], "echoBlocked": []})
order = [e["figure"]["name"] for e in r["entries"]]
check("конь, пешка Д2 (Л9), пешка А (Л5, атакующий), пешка Д", order == ["конь А", "пешка Д2", "пешка А", "пешка Д"], order)

print(f"\nИтого: {ok} ✓, {fail} ✗")
sys.exit(1 if fail else 0)
