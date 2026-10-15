"""Начальные данные для базы «Тактички онлайн».

Читает фигуры из дашборда (блок <script id="fz-data">) и справочник свойств
(supabase/properties.json) и пишет:
  supabase/seed.sql                 — свойства, персонажи, фигуры, владельцы (публичное);
  ~/.config/taktichka/codes.csv     — персонаж → личный код (только локально, раздать в личку);
  ~/.config/taktichka/codes.sql     — хэши кодов для базы (вставить в SQL Editor после seed.sql).

Коды создаются один раз: если codes.csv уже есть, существующие коды сохраняются,
новые персонажи получают новые.

  python tools/make_seed.py "<путь к Фигуры тактички/index.html>"
"""
import csv, hashlib, json, re, secrets, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
CONF = Path.home() / ".config" / "taktichka"

ADMIN = "Ведущий"

# Разные написания одного персонажа → основное имя (подтвердил пользователь 14.10.2026).
ALIASES = {
    "Ирен": "Ирэн Голицына",
    "Сотис": "Принцесса Сотис",
    "Пятая Эгле": "Пятая", "Черрел": "Пятая",
    "Бьянка Дегоя": "Нимур",
    "Четвертый": "Четвёртый",
    "Винсент": "Винсент Фламбо",
    "Зои Вебер": "Зои", "Зои Элкси": "Зои",
    # 16.10.2026
    "Эгле": "Королевна Эгле", "Роланд": "Неро", "Гнойный": "СМС",
    "Александр Смит": "Сэр Малеагант",
}

# Названия свойств в дашборде → как в таблице свойств.
PROPERTY_NAMES = {
    "Один в поле": "Один в поле воин",
    "Суперподкуп": "СуперПодкуп",
    "Закон талиона": "Закон Талиона",
    "Замри": "Замри!",
    "Приключения ждут": "Приключения ждут!",
    "Я лист на ветру": "Я — лист на ветру",
}

CODE_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"   # без 0/o, 1/l/i


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def arr(items):
    return "array[" + ", ".join(q(x) for x in items) + "]::text[]" if items else "'{}'::text[]"


def owner_entries(raw):
    """«Ратбургер + Зои; Сэр Малеагант» → [['Ратбургер', 'Зои'], ['Сэр Малеагант']]."""
    out = []
    for entry in str(raw or "").split(";"):
        names = [ALIASES.get(t.strip(), t.strip())
                 for t in re.split(r"\s*\+\s*|\s+и\s+|,\s*", entry) if t.strip()]
        if names:
            out.append(names)
    return out


def property_cost(p):
    if "cost" in p:
        return p["cost"]
    m = re.search(r"(?:Потрать|Заплати)\s+(\d+)\s+Ресурс", p["description"])
    return int(m.group(1)) if m else 0


def new_code():
    return "-".join("".join(secrets.choice(CODE_ALPHABET) for _ in range(4)) for _ in range(3))


def main(dashboard):
    html = Path(dashboard).read_text(encoding="utf-8")
    figures = json.loads(re.search(r'<script id="fz-data"[^>]*>(.*?)</script>', html, re.S).group(1))
    props = json.loads((ROOT / "supabase" / "properties.json").read_text(encoding="utf-8"))
    known = {p["name"] for p in props}

    names = [f["Фигура"] for f in figures]
    dups = {n for n in names if names.count(n) > 1}
    if dups:
        sys.exit(f"Повторяются названия фигур: {', '.join(sorted(dups))}")

    owners = set()
    for f in figures:
        for e in owner_entries(f["Владелец"]):
            owners.update(e)
    characters = sorted(owners)

    sql = ["-- Начальные данные (создано tools/make_seed.py). Запускать после schema.sql.", "begin;", ""]
    sql.append("insert into properties (name, phase, description, cost, cost_note) values")
    sql.append(",\n".join(
        f"  ({q(p['name'])}, {q(p['phase'])}, {q(p['description'])}, "
        f"{'null' if property_cost(p) is None else property_cost(p)}, {q(p['cost_note']) if p.get('cost_note') else 'null'})"
        for p in props) + ";\n")

    alias_of = {}
    for a, c in ALIASES.items():
        alias_of.setdefault(c, []).append(a)
    sql.append("insert into players (name, characters, is_admin) values")
    rows = [f"  ({q(ADMIN)}, '{{}}'::text[], true)"]
    rows += [f"  ({q(c)}, {arr([c] + sorted(alias_of.get(c, [])))}, false)" for c in characters]
    sql.append(",\n".join(rows) + ";\n")

    unknown = set()
    for f in figures:
        fprops = []
        for p in str(f["Свойство"]).split("/"):
            p = PROPERTY_NAMES.get(p.strip(), p.strip())
            if p:
                fprops.append(p)
                if p not in known:
                    unknown.add(p)
        entries = owner_entries(f["Владелец"])
        label = "; ".join(" и ".join(e) for e in entries)
        sql.append(
            f"insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values "
            f"({q(f['Фигура'])}, {q(f['Номинал'])}, {int(f['С'])}, {int(f['Л'])}, {int(f['В'])}, "
            f"{arr(fprops)}, {q(label)}, {q(f.get('Источники') or '')});")
        owner_set = sorted({n for e in entries for n in e})
        sql.append(
            f"insert into figure_owners select currval('figures_id_seq'), id from players "
            f"where name in ({', '.join(q(n) for n in owner_set)});")
    if unknown:
        sys.exit(f"Свойства фигур, которых нет в справочнике: {', '.join(sorted(unknown))}")

    sql.append("\ninsert into events (kind, data, comment) values ('import', "
               f"jsonb_build_object('figures', {len(figures)}, 'players', {len(characters)}), "
               "'Перенос из дашборда «Фигуры тактички»');")
    sql.append("commit;")
    (ROOT / "supabase" / "seed.sql").write_text("\n".join(sql) + "\n", encoding="utf-8")

    # Личные коды: только локально.
    CONF.mkdir(parents=True, exist_ok=True)
    codes_csv = CONF / "codes.csv"
    codes = {}
    if codes_csv.exists():
        with codes_csv.open(encoding="utf-8-sig") as fh:
            codes = {r["Персонаж"]: r["Код"] for r in csv.DictReader(fh)}
    for name in [ADMIN] + characters:
        codes.setdefault(name, new_code())
    with codes_csv.open("w", encoding="utf-8-sig", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Персонаж", "Код"])
        for name in [ADMIN] + characters:
            w.writerow([name, codes[name]])
    # Один запрос с подсчётом в конце: в SQL Editor сразу видно, сколько кодов записалось
    # (вариант с begin/commit и отдельными insert там молча ничего не записал).
    vals = ",\n  ".join(
        f"({q(name)}, {q(hashlib.sha256(codes[name].strip().encode('utf-8')).hexdigest())})"
        for name in [ADMIN] + characters)
    (CONF / "codes.sql").write_text(
        "-- Хэши личных кодов (не публиковать). Запускать после seed.sql.\n"
        "insert into player_codes (player_id, code_hash)\n"
        f"select p.id, v.h from (values\n  {vals}\n) v(n, h) join players p on p.name = v.n\n"
        "on conflict (player_id) do update set code_hash = excluded.code_hash;\n\n"
        "select count(*) as кодов_записано from player_codes;\n", encoding="utf-8")

    print(f"фигур: {len(figures)}, персонажей: {len(characters)} (+ {ADMIN}), свойств: {len(props)}")
    print("персонажи:", ", ".join(characters))
    print(f"seed.sql → {ROOT / 'supabase' / 'seed.sql'}")
    print(f"коды → {codes_csv} и {CONF / 'codes.sql'} (не публиковать)")


if __name__ == "__main__":
    main(sys.argv[1])
