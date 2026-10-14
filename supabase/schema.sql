-- Тактичка онлайн: схема базы (Supabase / Postgres).
-- Чтение открыто всем; запись только через функции api_* с кодом игрока.
-- Запускать целиком в SQL Editor пустого проекта.

-- Расширения не нужны: sha256() и gen_random_uuid() встроены в Postgres 13+.

-- ───────────────────────── справочники ─────────────────────────

create table nominals (
  name  text primary key,
  rank  int  not null,          -- старшинство в бою: король 6 … пешка 1
  max_per_strategist int not null
);
insert into nominals values
  ('король', 6, 1), ('ферзь', 5, 1), ('ладья', 4, 2),
  ('офицер', 3, 2), ('конь', 2, 2), ('пешка', 1, 8);

create table properties (
  name        text primary key,
  phase       text not null check (phase in ('Условие','Сила','Риск','Ущерб','Перемещение')),
  description text not null,
  cost        int,               -- цена в Ресурсах; null = переменная (Натиск, Перспективы)
  cost_note   text
);

-- ───────────────────────── игроки и фигуры ─────────────────────────

create table players (
  id           serial primary key,
  name         text not null unique,          -- игрок
  characters   text[] not null default '{}',  -- персонажи (для сопоставления владельцев)
  is_admin     boolean not null default false,
  resources    int not null default 0 check (resources >= 0),
  bonus_squads int not null default 0 check (bonus_squads >= 0)  -- за Влияние, вносит админ
);

-- Хэши личных кодов отдельно: таблица без политики чтения, из браузера не видна.
create table player_codes (
  player_id int primary key references players(id) on delete cascade,
  code_hash text not null unique      -- sha256 кода (hex); сами коды в базе не хранятся
);
alter table player_codes enable row level security;

create table figures (
  id          serial primary key,
  name        text not null unique,
  nominal     text not null references nominals(name),
  s           int  not null check (s >= 0),
  l           int  not null check (l >= 0),
  v           int  not null check (v >= 0),
  properties  text[] not null default '{}',
  owner_label text not null default '',       -- исходная строка «Владелец» для показа
  sources     text not null default '',       -- исходная строка «Источники»
  status      text not null default 'active' check (status in ('active','dead')),
  died_game   int,
  died_how    text,
  created_at  timestamptz not null default now()
);

create table figure_owners (
  figure_id int references figures(id) on delete cascade,
  player_id int references players(id) on delete cascade,
  primary key (figure_id, player_id)
);

-- ───────────────────────── игры, стратеги, отряды ─────────────────────────

create table games (
  id        serial primary key,
  title     text not null,
  starts_at timestamptz,
  status    text not null default 'draft' check (status in ('draft','running','closed'))
);

create table strategists (
  id       serial primary key,
  game_id  int not null references games(id) on delete cascade,
  wallet   int check (wallet >= 0),   -- общий кошелёк пары; null у одиночки
  invited  int references players(id) -- приглашённый напарник, ещё не подтвердил
);

create table strategist_members (
  strategist_id int not null references strategists(id) on delete cascade,
  game_id       int not null references games(id) on delete cascade,
  player_id     int not null references players(id),
  primary key (strategist_id, player_id),
  unique (game_id, player_id)          -- игрок в игре только у одного стратега
);

create table squads (
  id            serial primary key,
  game_id       int not null references games(id) on delete cascade,
  strategist_id int not null references strategists(id) on delete cascade,
  name          text not null check (btrim(name) <> ''),
  name_key      text generated always as (lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))) stored,
  destroyed     boolean not null default false,
  dead_figure   int references figures(id),   -- погибшая в конце игры
  unique (game_id, name_key)
);

create table squad_figures (
  squad_id      int not null references squads(id) on delete cascade,
  figure_id     int not null references figures(id),
  game_id       int not null references games(id) on delete cascade,
  strategist_id int not null references strategists(id) on delete cascade,
  state         text not null default 'ok'
                check (state in ('ok','damaged','discard','reserve','dump')),
  borrowed      boolean not null default false,  -- взята у противника (Подкуп, Перспективы)
  primary key (squad_id, figure_id),
  unique (game_id, strategist_id, figure_id)
);

create table trophies (
  id          serial primary key,
  name        text not null,
  description text not null default '',
  bonus_s     int not null default 0,
  bonus_l     int not null default 0,
  bonus_v     int not null default 0,
  squad_id    int references squads(id) on delete set null,  -- где лежит сейчас
  holder      int references players(id),                    -- у кого хранится между играми
  status      text not null default 'active' check (status in ('active','kept','gone'))
);

-- ───────────────────────── бои ─────────────────────────

create table battles (
  id         serial primary key,
  game_id    int not null references games(id) on delete cascade,
  attacker   int not null references squads(id),
  defender   int not null references squads(id),
  status     text not null default 'open' check (status in ('open','closed')),
  winner     int references squads(id),     -- null при ничьей
  result     jsonb,
  opened_by  int references players(id),
  created_at timestamptz not null default now()
);

create table battle_actions (
  id         serial primary key,
  battle_id  int not null references battles(id) on delete cascade,
  kind       text not null,          -- property | skip | roll | reroll | damage | note
  squad_id   int references squads(id),
  figure_id  int references figures(id),
  property   text,
  params     jsonb not null default '{}',
  roll       int check (roll between 1 and 10),
  manual     boolean not null default false,
  cost       int not null default 0,
  actor      int references players(id),
  created_at timestamptz not null default now()
);

-- ───────────────────────── журнал ─────────────────────────

create table events (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  actor      int references players(id),
  kind       text not null,
  game_id    int references games(id) on delete set null,
  figure_id  int references figures(id) on delete set null,
  squad_id   int references squads(id) on delete set null,
  player_id  int references players(id),
  amount     int,
  data       jsonb not null default '{}',
  comment    text,
  reverted   boolean not null default false
);
create index on events (figure_id);
create index on events (game_id);
create index on events (player_id);

-- ───────────────────────── доступ ─────────────────────────
-- Все таблицы (кроме player_codes) читаются всеми; писать напрямую из браузера нельзя.

do $$
declare t text;
begin
  foreach t in array array['nominals','properties','players','figures','figure_owners','games',
    'strategists','strategist_members','squads','squad_figures','trophies','battles',
    'battle_actions','events']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy read_all on %I for select using (true)', t);
  end loop;
end $$;


-- Realtime для помощника боя и страницы игры.
alter publication supabase_realtime add table battles, battle_actions, squad_figures, strategists, players;

-- ───────────────────────── служебные функции ─────────────────────────

create or replace function hash_code(p_code text) returns text
language sql immutable as $$ select encode(sha256(convert_to(btrim(p_code), 'UTF8')), 'hex') $$;

-- Игрок по коду или исключение.
create or replace function auth(p_code text) returns players
language plpgsql security definer set search_path = public as $$
declare r players;
begin
  select p.* into r from players p join player_codes c on c.player_id = p.id
    where c.code_hash = hash_code(p_code);
  if not found then raise exception 'Неверный код'; end if;
  return r;
end $$;

create or replace function auth_admin(p_code text) returns players
language plpgsql security definer set search_path = public as $$
declare r players := auth(p_code);
begin
  if not r.is_admin then raise exception 'Нужны права ведущего'; end if;
  return r;
end $$;

create or replace function log_event(p_actor int, p_kind text, p_game int, p_figure int,
  p_squad int, p_player int, p_amount int, p_data jsonb, p_comment text) returns void
language sql security definer set search_path = public as $$
  insert into events (actor, kind, game_id, figure_id, squad_id, player_id, amount, data, comment)
  values (p_actor, p_kind, p_game, p_figure, p_squad, p_player, p_amount, coalesce(p_data,'{}'), p_comment)
$$;

create or replace function is_owner(p_player int, p_figure int) returns boolean
language sql stable as $$
  select exists (select 1 from figure_owners where figure_id = p_figure and player_id = p_player)
$$;

-- Стратег игрока в игре (null, если не участвует).
create or replace function strategist_of(p_player int, p_game int) returns int
language sql stable as $$
  select strategist_id from strategist_members where player_id = p_player and game_id = p_game
$$;

create or replace function require_strategist(p_player players, p_squad int) returns squads
language plpgsql security definer set search_path = public as $$
declare s squads;
begin
  select * into s from squads where id = p_squad;
  if not found then raise exception 'Нет такого отряда'; end if;
  if not p_player.is_admin and strategist_of(p_player.id, s.game_id) is distinct from s.strategist_id then
    raise exception 'Это не ваш отряд';
  end if;
  return s;
end $$;

-- Списать / начислить Ресурсы стратега (у пары — общий кошелёк).
create or replace function strategist_pay(p_strategist int, p_amount int, p_actor int,
  p_reason text, p_game int, p_figure int, p_squad int) returns void
language plpgsql security definer set search_path = public as $$
declare st strategists; pl int;
begin
  select * into st from strategists where id = p_strategist for update;
  if st.wallet is not null then
    if st.wallet - p_amount < 0 then raise exception 'Не хватает Ресурсов (есть %)', st.wallet; end if;
    update strategists set wallet = wallet - p_amount where id = p_strategist;
  else
    select player_id into pl from strategist_members where strategist_id = p_strategist;
    if (select resources from players where id = pl) - p_amount < 0 then
      raise exception 'Не хватает Ресурсов';
    end if;
    update players set resources = resources - p_amount where id = pl;
  end if;
  perform log_event(p_actor, case when p_amount >= 0 then 'resources_spend' else 'resources_gain' end,
    p_game, p_figure, p_squad, null, -p_amount, jsonb_build_object('strategist', p_strategist), p_reason);
end $$;

-- Честный d10: байты 250–255 отбрасываются, чтобы не было перекоса в пользу 1–6.

create or replace function d10() returns int
language plpgsql volatile as $$
declare b int;
begin
  loop
    b := get_byte(uuid_send(gen_random_uuid()), 0);  -- байт 0 у UUID v4 случайный
    exit when b < 250;
  end loop;
  return 1 + b % 10;
end $$;

-- Проверка состава всех отрядов стратега в игре.
create or replace function check_strategist_squads(p_strategist int) returns void
language plpgsql security definer set search_path = public as $$
declare
  g int; n_squads int; max_squads int; bad record;
begin
  select game_id into g from strategists where id = p_strategist;
  select count(*) into n_squads from squads where strategist_id = p_strategist;
  select 2 + coalesce(max(p.bonus_squads), 0) into max_squads
    from strategist_members m join players p on p.id = m.player_id where m.strategist_id = p_strategist;
  if n_squads > max_squads then
    raise exception 'Отрядов больше, чем можно (% из %)', n_squads, max_squads;
  end if;
  for bad in
    select s.name, count(sf.figure_id) n from squads s left join squad_figures sf on sf.squad_id = s.id
    where s.strategist_id = p_strategist group by s.id having count(sf.figure_id) not between 1 and 3
  loop
    raise exception 'В отряде «%» должно быть от 1 до 3 фигур (сейчас %)', bad.name, bad.n;
  end loop;
  for bad in
    select f.nominal, count(*) n, max(nm.max_per_strategist) mx
    from squad_figures sf join figures f on f.id = sf.figure_id join nominals nm on nm.name = f.nominal
    where sf.strategist_id = p_strategist and not sf.borrowed
    group by f.nominal having count(*) > max(nm.max_per_strategist)
  loop
    raise exception 'Слишком много фигур номинала «%»: % (можно %)', bad.nominal, bad.n, bad.mx;
  end loop;
  for bad in
    select count(*) n, s.id from squads s join trophies t on t.squad_id = s.id and t.status = 'active'
    where s.strategist_id = p_strategist group by s.id having count(*) > 3
  loop
    raise exception 'У отряда не больше 3 трофеев';
  end loop;
end $$;

-- ───────────────────────── API: вход ─────────────────────────

create or replace function api_whoami(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r players := auth(p_code);
begin
  return jsonb_build_object('id', r.id, 'name', r.name, 'characters', r.characters, 'is_admin', r.is_admin);
end $$;

-- ───────────────────────── API: фигуры ─────────────────────────

create or replace function api_figure_add(p_code text, p_name text, p_nominal text,
  p_s int, p_l int, p_v int, p_properties text[], p_source text, p_comment text) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); fid int;
begin
  insert into figures (name, nominal, s, l, v, properties, owner_label, sources)
  values (btrim(p_name), p_nominal, p_s, p_l, p_v, coalesce(p_properties,'{}'),
          coalesce(me.characters[1], me.name), coalesce(p_source,''))
  returning id into fid;
  insert into figure_owners values (fid, me.id);
  perform log_event(me.id, 'figure_add', null, fid, null, me.id, null,
    jsonb_build_object('nominal',p_nominal,'s',p_s,'l',p_l,'v',p_v,'properties',p_properties,'source',p_source), p_comment);
  return fid;
end $$;

create or replace function api_figure_edit(p_code text, p_figure int, p_name text, p_nominal text,
  p_s int, p_l int, p_v int, p_properties text[], p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); old figures;
begin
  select * into old from figures where id = p_figure for update;
  if not found then raise exception 'Нет такой фигуры'; end if;
  if not me.is_admin and not is_owner(me.id, p_figure) then raise exception 'Это не ваша фигура'; end if;
  update figures set name = btrim(p_name), nominal = p_nominal, s = p_s, l = p_l, v = p_v,
    properties = coalesce(p_properties,'{}') where id = p_figure;
  perform log_event(me.id, 'figure_edit', null, p_figure, null, null, null,
    jsonb_build_object('old', to_jsonb(old) - 'owner_label' - 'sources',
      'new', jsonb_build_object('name',p_name,'nominal',p_nominal,'s',p_s,'l',p_l,'v',p_v,'properties',p_properties)),
    p_comment);
end $$;

-- Передать свою долю владения другому игроку (админ — от любого владельца).
create or replace function api_figure_transfer(p_code text, p_figure int, p_from int, p_to int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); src int := coalesce(p_from, me.id);
begin
  if src <> me.id and not me.is_admin then raise exception 'Передавать можно только своё'; end if;
  if not is_owner(src, p_figure) then raise exception 'У этого игрока нет такой фигуры'; end if;
  if (select status from figures where id = p_figure) <> 'active' then raise exception 'Фигура погибла'; end if;
  delete from figure_owners where figure_id = p_figure and player_id = src;
  insert into figure_owners values (p_figure, p_to) on conflict do nothing;
  update figures set owner_label = (
    select string_agg(coalesce(p.characters[1], p.name), ' и ' order by p.name)
    from figure_owners o join players p on p.id = o.player_id where o.figure_id = p_figure)
  where id = p_figure;
  perform log_event(me.id, 'figure_transfer', null, p_figure, null, p_to, null,
    jsonb_build_object('from', src, 'to', p_to), p_comment);
end $$;

-- Отметить применение фигуры (на игре или вне сайта).
create or replace function api_figure_use(p_code text, p_figure int, p_game int, p_where text, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code);
begin
  if not me.is_admin and not is_owner(me.id, p_figure) then raise exception 'Это не ваша фигура'; end if;
  perform log_event(me.id, 'figure_use', p_game, p_figure, null, me.id, null,
    jsonb_build_object('where', p_where), p_comment);
end $$;

-- ───────────────────────── API: ресурсы ─────────────────────────

-- Общий кошелёк пары, в которой игрок состоит в незакрытой игре (null — играет один или не играет).
-- Пока пара играет, все Ресурсы участников идут через этот кошелёк.
create or replace function open_wallet(p_player int) returns int
language sql stable as $$
  select s.id from strategist_members m
    join strategists s on s.id = m.strategist_id
    join games g on g.id = s.game_id
  where m.player_id = p_player and s.wallet is not null and g.status <> 'closed'
  order by g.id desc limit 1
$$;

-- Сколько Ресурсов у игрока сейчас (у пары — общий кошелёк).
create or replace function balance_of(p_player int) returns int
language sql stable as $$
  select coalesce((select wallet from strategists where id = open_wallet(p_player)),
                  (select resources from players where id = p_player))
$$;

-- Изменить Ресурсы игрока (или общий кошелёк его пары); в минус нельзя.
create or replace function add_resources(p_player int, p_amount int) returns int
language plpgsql security definer set search_path = public as $$
declare w int := open_wallet(p_player); have int := balance_of(p_player);
begin
  if have + p_amount < 0 then
    raise exception 'Не хватает Ресурсов (есть %)', have || case when w is null then '' else ' в общем кошельке пары' end;
  end if;
  if w is not null then update strategists set wallet = wallet + p_amount where id = w;
  else update players set resources = resources + p_amount where id = p_player; end if;
  return w;
end $$;

-- Починка 14.10.2026: Ресурсы, начисленные участникам пары после её оформления, легли на личные
-- балансы. Переносит их в общий кошелёк (для пар в незакрытых играх). Возвращает число пар.
create or replace function fix_pair_wallets() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select s.id sid, s.game_id, array_agg(p.id) members, sum(p.resources)::int total
    from strategists s join games g on g.id = s.game_id
      join strategist_members m on m.strategist_id = s.id join players p on p.id = m.player_id
    where s.wallet is not null and g.status <> 'closed'
    group by s.id, s.game_id having sum(p.resources) > 0
  loop
    update strategists set wallet = wallet + r.total where id = r.sid;
    update players set resources = 0 where id = any(r.members);
    perform log_event(null, 'pair', r.game_id, null, null, null, r.total,
      jsonb_build_object('players', to_jsonb(r.members), 'strategist', r.sid),
      'Ресурсы, начисленные после оформления пары, перенесены в общий кошелёк');
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function api_resources_transfer(p_code text, p_to int, p_amount int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); wf int; wt int;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  if p_to = me.id then raise exception 'Нельзя передать самому себе'; end if;
  if open_wallet(me.id) is not null and open_wallet(me.id) = open_wallet(p_to) then
    raise exception 'Вы напарники: Ресурсы и так общие';
  end if;
  wf := add_resources(me.id, -p_amount);
  wt := add_resources(p_to, p_amount);
  perform log_event(me.id, 'resources_transfer', null, null, null, p_to, p_amount,
    jsonb_build_object('from', me.id, 'to', p_to, 'from_wallet', wf, 'to_wallet', wt), p_comment);
end $$;

create or replace function api_admin_resources(p_code text, p_player int, p_amount int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); w int;
begin
  w := add_resources(p_player, p_amount);
  perform log_event(me.id, 'resources_grant', null, null, null, p_player, p_amount,
    jsonb_build_object('wallet', w), p_comment);
end $$;

create or replace function api_admin_bonus(p_code text, p_player int, p_bonus int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code);
begin
  update players set bonus_squads = p_bonus where id = p_player;
  perform log_event(me.id, 'bonus_squads', null, null, null, p_player, p_bonus, '{}', p_comment);
end $$;

-- ───────────────────────── API: игры и стратеги ─────────────────────────

create or replace function api_admin_game(p_code text, p_id int, p_title text, p_starts_at timestamptz,
  p_status text) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); gid int; pending int;
begin
  if p_status = 'closed' then
    select count(*) into pending from squads where game_id = p_id and destroyed and dead_figure is null
      and exists (select 1 from squad_figures sf where sf.squad_id = squads.id and not sf.borrowed);
    if pending > 0 then raise exception 'Не выбраны погибшие фигуры в % уничтоженных отрядах', pending; end if;
    if exists (select 1 from strategists where game_id = p_id and wallet > 0) then
      raise exception 'Сначала разделите остаток общих кошельков напарников';
    end if;
    if exists (select 1 from trophies t join squads s on s.id = t.squad_id
               where s.game_id = p_id and t.status = 'active') then
      raise exception 'Сначала решите судьбу трофеев (остаются или исчезают)';
    end if;
  end if;
  if p_id is null then
    insert into games (title, starts_at, status) values (p_title, p_starts_at, coalesce(p_status,'draft'))
    returning id into gid;
  else
    update games set title = p_title, starts_at = p_starts_at, status = p_status where id = p_id;
    gid := p_id;
  end if;
  perform log_event(me.id, 'game_' || coalesce(p_status,'draft'), gid, null, null, null, null,
    jsonb_build_object('title', p_title), null);
  return gid;
end $$;

create or replace function game_open_for_setup(p_game int, p_admin boolean) returns void
language plpgsql as $$
begin
  if (select status from games where id = p_game) <> 'draft' and not p_admin then
    raise exception 'Игра уже началась — состав меняется только Обменом и свойствами';
  end if;
end $$;

-- Участвовать в игре (создаёт одиночного стратега).
create or replace function api_join_game(p_code text, p_game int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); sid int;
begin
  perform game_open_for_setup(p_game, me.is_admin);
  sid := strategist_of(me.id, p_game);
  if sid is not null then return sid; end if;
  insert into strategists (game_id) values (p_game) returning id into sid;
  insert into strategist_members values (sid, p_game, me.id);
  perform log_event(me.id, 'join_game', p_game, null, null, me.id, null, '{}', null);
  return sid;
end $$;

-- Слить двух игроков в одного стратега: общий кошелёк, все отряды вместе.
create or replace function merge_pair(p_game int, p_a int, p_b int, p_actor int) returns int
language plpgsql security definer set search_path = public as $$
declare sa int; sb int; total int;
begin
  if p_a = p_b then raise exception 'Нужны два разных игрока'; end if;
  sa := strategist_of(p_a, p_game); sb := strategist_of(p_b, p_game);
  if sa is null then
    insert into strategists (game_id) values (p_game) returning id into sa;
    insert into strategist_members values (sa, p_game, p_a);
  end if;
  if sb is not null and sb <> sa then
    if (select count(*) from strategist_members where strategist_id = sb) > 1 then
      raise exception 'У второго игрока уже есть напарник';
    end if;
    update squads set strategist_id = sa where strategist_id = sb;
    update squad_figures set strategist_id = sa where strategist_id = sb;
    delete from strategist_members where strategist_id = sb;
    delete from strategists where id = sb;
  end if;
  if (select count(*) from strategist_members where strategist_id = sa) > 1 then
    raise exception 'Напарник может быть только один';
  end if;
  insert into strategist_members values (sa, p_game, p_b);
  select coalesce(sum(resources),0) into total from players where id in (p_a, p_b);
  update players set resources = 0 where id in (p_a, p_b);
  update strategists set wallet = total, invited = null where id = sa;
  perform check_strategist_squads(sa);
  perform log_event(p_actor, 'pair', p_game, null, null, null, total,
    jsonb_build_object('players', jsonb_build_array(p_a, p_b), 'strategist', sa), 'Ресурсы слиты в общий кошелёк');
  return sa;
end $$;

create or replace function api_partner_invite(p_code text, p_game int, p_partner int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); sid int;
begin
  perform game_open_for_setup(p_game, false);
  sid := api_join_game(p_code, p_game);
  if (select count(*) from strategist_members where strategist_id = sid) > 1 then
    raise exception 'Напарник может быть только один';
  end if;
  update strategists set invited = p_partner where id = sid;
  perform log_event(me.id, 'partner_invite', p_game, null, null, p_partner, null, '{}', null);
end $$;

create or replace function api_partner_accept(p_code text, p_game int, p_inviter int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); sid int := strategist_of(p_inviter, p_game);
begin
  perform game_open_for_setup(p_game, false);
  if sid is null or (select invited from strategists where id = sid) is distinct from me.id then
    raise exception 'Приглашения нет';
  end if;
  return merge_pair(p_game, p_inviter, me.id, me.id);
end $$;

create or replace function api_admin_pair(p_code text, p_game int, p_a int, p_b int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code);
begin
  return merge_pair(p_game, p_a, p_b, me.id);
end $$;

-- Раздел остатка общего кошелька после игры: p_shares = {"<player_id>": n, ...}.
create or replace function api_admin_split_wallet(p_code text, p_strategist int, p_shares jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); st strategists; k text; total int := 0;
begin
  select * into st from strategists where id = p_strategist for update;
  for k in select jsonb_object_keys(p_shares) loop
    if not exists (select 1 from strategist_members where strategist_id = p_strategist and player_id = k::int) then
      raise exception 'Игрок % не из этой пары', k;
    end if;
    total := total + (p_shares->>k)::int;
  end loop;
  if total <> coalesce(st.wallet,0) then
    raise exception 'Сумма долей (%) не равна остатку (%)', total, st.wallet;
  end if;
  for k in select jsonb_object_keys(p_shares) loop
    update players set resources = resources + (p_shares->>k)::int where id = k::int;
  end loop;
  update strategists set wallet = 0 where id = p_strategist;
  perform log_event(me.id, 'wallet_split', st.game_id, null, null, null, total, p_shares, null);
end $$;

-- ───────────────────────── API: отряды ─────────────────────────

-- Создать или пересобрать отряд до старта игры (админ — в любой момент).
-- Ведущий добавляет персонажа в игру (создаёт ему стратега), чтобы собрать за него отряды.
create or replace function api_admin_join(p_code text, p_game int, p_player int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); sid int := strategist_of(p_player, p_game);
begin
  if sid is not null then return sid; end if;
  insert into strategists (game_id) values (p_game) returning id into sid;
  insert into strategist_members values (sid, p_game, p_player);
  perform log_event(me.id, 'join_game', p_game, null, null, p_player, null, '{}', 'добавил ведущий');
  return sid;
end $$;

-- Создать или пересобрать отряд. Игрок — только свой и до старта игры; ведущий — за любого
-- стратега (p_strategist) и в любой момент. Лимиты действуют для всех. При правке фигуры,
-- оставшиеся в отряде, сохраняют состояние (повреждена, в отбое) и отметку «взята у противника».
create or replace function api_squad_save(p_code text, p_game int, p_squad int, p_name text, p_figures int[],
  p_strategist int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); sid int; sq int := p_squad; f int; owners int[];
begin
  perform game_open_for_setup(p_game, me.is_admin);
  if coalesce(btrim(p_name), '') = '' then raise exception 'У отряда должно быть название'; end if;
  if exists (select 1 from squads where game_id = p_game and id is distinct from sq
             and name_key = lower(regexp_replace(btrim(p_name), '\s+', ' ', 'g'))) then
    raise exception 'Название «%» в этой игре уже занято', btrim(p_name);
  end if;
  if cardinality(p_figures) <> (select count(distinct x) from unnest(p_figures) x) then
    raise exception 'Одна фигура указана дважды';
  end if;
  if sq is not null then
    sid := (require_strategist(me, sq)).strategist_id;
  elsif p_strategist is not null then
    if not me.is_admin and strategist_of(me.id, p_game) is distinct from p_strategist then
      raise exception 'Собирать отряды за другого стратега может только ведущий';
    end if;
    if (select game_id from strategists where id = p_strategist) is distinct from p_game then
      raise exception 'Стратег не из этой игры';
    end if;
    sid := p_strategist;
  else
    sid := api_join_game(p_code, p_game);
  end if;
  select array_agg(player_id) into owners from strategist_members where strategist_id = sid;
  foreach f in array coalesce(p_figures, '{}') loop
    if (select status from figures where id = f) <> 'active' then
      raise exception 'Фигура «%» погибла', (select name from figures where id = f);
    end if;
    if not me.is_admin and not exists (select 1 from figure_owners where figure_id = f and player_id = any(owners)) then
      raise exception 'Фигура «%» не принадлежит стратегу', (select name from figures where id = f);
    end if;
  end loop;
  if sq is null then
    insert into squads (game_id, strategist_id, name) values (p_game, sid, p_name) returning id into sq;
  else
    update squads set name = p_name where id = sq;
    delete from squad_figures where squad_id = sq and not (figure_id = any(coalesce(p_figures, '{}')));
  end if;
  insert into squad_figures (squad_id, figure_id, game_id, strategist_id)
    select sq, x, p_game, sid from unnest(p_figures) x
    where not exists (select 1 from squad_figures where squad_id = sq and figure_id = x);
  update squads set destroyed = not exists (select 1 from squad_figures where squad_id = sq and state = 'ok')
    where id = sq;
  perform check_strategist_squads(sid);
  perform log_event(me.id, 'squad_save', p_game, null, sq, null, null,
    jsonb_build_object('name', p_name, 'figures', p_figures), null);
  return sq;
exception when unique_violation then
  raise exception 'Одна из фигур уже стоит в другом вашем отряде этой игры';
end $$;

create or replace function api_squad_delete(p_code text, p_squad int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad);
begin
  perform game_open_for_setup(s.game_id, me.is_admin);
  delete from squads where id = p_squad;
  perform log_event(me.id, 'squad_delete', s.game_id, null, null, null, null,
    jsonb_build_object('name', s.name), null);
end $$;

-- Обмен между двумя своими отрядами: новое распределение фигур и трофеев.
-- Пустой второй отряд = слияние (второй отряд удаляется).
create or replace function api_exchange(p_code text, p_a int, p_b int,
  p_a_figures int[], p_b_figures int[], p_a_trophies int[], p_b_trophies int[]) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); a squads := require_strategist(me, p_a); b squads := require_strategist(me, p_b);
  before_f int[]; after_f int[]; before_t int[]; after_t int[];
begin
  if a.strategist_id <> b.strategist_id then raise exception 'Обмен только между своими отрядами'; end if;
  if (select status from games where id = a.game_id) <> 'running' then raise exception 'Игра не идёт'; end if;
  -- Обмен — действие отряда, который его начал: его ход на этом заканчивается (второй ходит дальше).
  perform squad_act(p_a, 'Обмен', me);
  select array_agg(figure_id order by figure_id) into before_f from squad_figures where squad_id in (p_a, p_b);
  select array_agg(x order by x) into after_f from unnest(coalesce(p_a_figures,'{}') || coalesce(p_b_figures,'{}')) x;
  if before_f is distinct from after_f then raise exception 'Обмен не может добавлять или убирать фигуры'; end if;
  select array_agg(id order by id) into before_t from trophies where squad_id in (p_a, p_b) and status = 'active';
  select array_agg(x order by x) into after_t from unnest(coalesce(p_a_trophies,'{}') || coalesce(p_b_trophies,'{}')) x;
  if before_t is distinct from after_t then raise exception 'Обмен не может добавлять или убирать трофеи'; end if;
  update squad_figures set squad_id = p_a where squad_id = p_b and figure_id = any(coalesce(p_a_figures,'{}'));
  update squad_figures set squad_id = p_b where squad_id = p_a and figure_id = any(coalesce(p_b_figures,'{}'));
  update trophies set squad_id = p_a where id = any(coalesce(p_a_trophies,'{}'));
  update trophies set squad_id = p_b where id = any(coalesce(p_b_trophies,'{}'));
  if coalesce(cardinality(p_b_figures),0) = 0 then
    if coalesce(cardinality(p_b_trophies),0) > 0 then raise exception 'В пустом отряде не может быть трофеев'; end if;
    delete from squads where id = p_b;
  end if;
  perform check_strategist_squads(a.strategist_id);
  perform log_event(me.id, 'exchange', a.game_id, null, p_a, null, null,
    jsonb_build_object('a', p_a, 'b', p_b, 'a_figures', p_a_figures, 'b_figures', p_b_figures,
      'a_trophies', p_a_trophies, 'b_trophies', p_b_trophies), null);
end $$;

-- Состояние фигуры в отряде (повреждена, отбой и т. п.) — стратег отряда или ведущий.
create or replace function api_figure_state(p_code text, p_squad int, p_figure int, p_state text, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad); old text;
begin
  select state into old from squad_figures where squad_id = p_squad and figure_id = p_figure;
  if not found then raise exception 'Фигуры нет в отряде'; end if;
  update squad_figures set state = p_state where squad_id = p_squad and figure_id = p_figure;
  -- уничтожен, если в строю не осталось ни одной целой фигуры
  update squads set destroyed = not exists (
    select 1 from squad_figures where squad_id = p_squad and state = 'ok'
  ) where id = p_squad;
  perform log_event(me.id, 'figure_state', s.game_id, p_figure, p_squad, null, null,
    jsonb_build_object('from', old, 'to', p_state), p_comment);
end $$;

-- Переместить фигуру в отряд противника (Подкуп, Перспективы и т. п.) — только ведущий
-- или через помощник боя. Возвращается владельцу по итогам игры.
create or replace function api_admin_move_figure(p_code text, p_from int, p_to int, p_figure int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); t squads;
begin
  select * into t from squads where id = p_to;
  update squad_figures set squad_id = p_to, strategist_id = t.strategist_id,
    borrowed = (select strategist_id from squads where id = p_from) <> t.strategist_id or borrowed
  where squad_id = p_from and figure_id = p_figure;
  perform log_event(me.id, 'figure_move', t.game_id, p_figure, p_to, null, null,
    jsonb_build_object('from', p_from, 'to', p_to), p_comment);
end $$;

-- ───────────────────────── API: свойства и кубики ─────────────────────────

-- Бросок d10: без p_manual — бросает база; p_manual (1–10) — только ведущий.
create or replace function api_roll(p_code text, p_game int, p_battle int, p_squad int, p_purpose text, p_manual int)
returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); r int;
begin
  if p_manual is not null then
    if not me.is_admin then raise exception 'Вводить бросок вручную может только ведущий'; end if;
    if p_manual not between 1 and 10 then raise exception 'Бросок d10: от 1 до 10'; end if;
    r := p_manual;
  else
    if p_squad is not null then perform require_strategist(me, p_squad); end if;
    r := d10();
  end if;
  if p_battle is not null then
    insert into battle_actions (battle_id, kind, squad_id, roll, manual, actor, params)
    values (p_battle, 'roll', p_squad, r, p_manual is not null, me.id, jsonb_build_object('purpose', p_purpose));
  end if;
  perform log_event(me.id, 'roll', p_game, null, p_squad, null, r,
    jsonb_build_object('purpose', p_purpose, 'manual', p_manual is not null, 'battle', p_battle), null);
  return r;
end $$;

-- Использовать свойство фигуры вне боя (фаза Перемещения): списать цену, записать в журнал.
-- Воротила: бросок, на чёт +1 Ресурс. Возвращает {cost, roll, gain}.
create or replace function api_property_use(p_code text, p_squad int, p_figure int, p_property text,
  p_cost int, p_battle int, p_params jsonb, p_comment text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad);
  pr properties; cost int; r int; gain int := 0; fig figures; sf squad_figures; b battles;
begin
  if (select status from games where id = s.game_id) <> 'running' then raise exception 'Игра не идёт'; end if;
  select * into sf from squad_figures where squad_id = p_squad and figure_id = p_figure;
  if not found then raise exception 'Фигуры нет в этом отряде'; end if;
  if sf.state not in ('ok','damaged') then raise exception 'Фигура не в строю'; end if;
  select * into fig from figures where id = p_figure;
  if not (p_property = any(fig.properties)) and not ('Перезагрузка' = any(fig.properties)) then
    raise exception 'У фигуры нет свойства «%»', p_property;
  end if;
  select * into pr from properties where name = p_property;
  if not found then raise exception 'Нет свойства «%» в справочнике', p_property; end if;
  perform check_echo_blocks(p_squad, p_property);
  cost := coalesce(pr.cost, p_cost, 0);
  if pr.cost is null and p_cost is null then raise exception 'Укажите, сколько Ресурсов тратится'; end if;
  if p_property = 'Натиск' and cost not between 1 and 3 then raise exception 'Натиск: от 1 до 3 Ресурсов'; end if;

  if p_battle is not null then
    select * into b from battles where id = p_battle;
    if b.status <> 'open' then raise exception 'Бой закрыт'; end if;
    if p_squad not in (b.attacker, b.defender) then raise exception 'Отряд не участвует в бою'; end if;
    -- одно действие за бой; пропуск в одной фазе не мешает свойству другой фазы
    if exists (select 1 from battle_actions where battle_id = p_battle and figure_id = p_figure
               and squad_id = p_squad and kind = 'property') then
      raise exception 'Фигура уже действовала в этом бою';
    end if;
    -- «Всем друг» противника: запрет тратить ресурсы
    if cost > 0 and exists (select 1 from battle_actions where battle_id = p_battle and kind = 'property'
         and property = 'Всем друг' and squad_id <> p_squad) then
      raise exception 'Противник применил «Всем друг»: тратить Ресурсы нельзя';
    end if;
  end if;

  if cost > 0 then
    perform strategist_pay(s.strategist_id, cost, me.id, 'Свойство «' || p_property || '»', s.game_id, p_figure, p_squad);
  end if;
  -- Свойства с броском: бросает база (Шпионаж — переброс противника, Множественность и
  -- Воротила — на чёт). Ведущий может передать значение живого кубика в p_params.manual_roll.
  if p_property in ('Воротила', 'Шпионаж', 'Множественность') then
    if p_params ? 'manual_roll' then
      if not me.is_admin then raise exception 'Вводить бросок вручную может только ведущий'; end if;
      r := (p_params->>'manual_roll')::int;
      if r not between 1 and 10 then raise exception 'Бросок d10: от 1 до 10'; end if;
    else
      r := d10();
    end if;
  end if;
  if p_property = 'Воротила' then
    if r % 2 = 0 then
      gain := 1;
      perform strategist_pay(s.strategist_id, -1, me.id, 'Воротила: выпало ' || r, s.game_id, p_figure, p_squad);
    end if;
  end if;
  if p_battle is not null then
    insert into battle_actions (battle_id, kind, squad_id, figure_id, property, params, roll, cost, actor)
    values (p_battle, 'property', p_squad, p_figure, p_property, coalesce(p_params,'{}'), r, cost, me.id);
  end if;
  perform log_event(me.id, 'property_use', s.game_id, p_figure, p_squad, null, cost,
    coalesce(p_params,'{}') || jsonb_build_object('property', p_property, 'roll', r, 'gain', gain, 'battle', p_battle),
    p_comment);
  return jsonb_build_object('cost', cost, 'roll', r, 'gain', gain);
end $$;

-- ───────────────────────── API: бои ─────────────────────────

create or replace function api_battle_open(p_code text, p_attacker int, p_defender int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); a squads := require_strategist(me, p_attacker); d squads; bid int;
begin
  select * into d from squads where id = p_defender;
  if d.game_id <> a.game_id then raise exception 'Отряды из разных игр'; end if;
  if d.strategist_id = a.strategist_id then raise exception 'Нельзя напасть на свой отряд'; end if;
  if (select status from games where id = a.game_id) <> 'running' then raise exception 'Игра не идёт'; end if;
  if exists (select 1 from battles where status = 'open' and (attacker in (p_attacker, p_defender) or defender in (p_attacker, p_defender))) then
    raise exception 'Один из отрядов уже в бою';
  end if;
  -- Нападение — действие отряда: после него ход отряда заканчивается.
  perform squad_act(p_attacker, 'Нападение', me);
  insert into battles (game_id, attacker, defender, opened_by) values (a.game_id, p_attacker, p_defender, me.id)
  returning id into bid;
  perform log_event(me.id, 'battle_open', a.game_id, null, p_attacker, null, null,
    jsonb_build_object('battle', bid, 'attacker', p_attacker, 'defender', p_defender), null);
  return bid;
end $$;

-- Пропустить ход фигуры в бою или записать прочий шаг (повреждение, пометка).
create or replace function api_battle_step(p_code text, p_battle int, p_kind text, p_squad int,
  p_figure int, p_params jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); b battles;
begin
  select * into b from battles where id = p_battle;
  if b.status <> 'open' then raise exception 'Бой закрыт'; end if;
  if p_kind not in ('skip','damage','note') then raise exception 'Неизвестный шаг'; end if;
  perform require_strategist(me, p_squad);
  insert into battle_actions (battle_id, kind, squad_id, figure_id, params, actor)
  values (p_battle, p_kind, p_squad, p_figure, coalesce(p_params,'{}'), me.id);
  if p_kind = 'damage' then
    perform api_figure_state(p_code, p_squad, p_figure, 'damaged', 'Бой #' || p_battle);
  end if;
end $$;

-- Отменить шаг боя (ведущий): ресурсы за отменённое свойство возвращаются.
create or replace function api_admin_battle_undo(p_code text, p_action int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); a battle_actions; s squads;
begin
  select * into a from battle_actions where id = p_action;
  select * into s from squads where id = a.squad_id;
  if a.cost > 0 then
    perform strategist_pay(s.strategist_id, -a.cost, me.id, 'Отмена шага боя', s.game_id, a.figure_id, a.squad_id);
  end if;
  delete from battle_actions where id = p_action;
  perform log_event(me.id, 'battle_undo', s.game_id, a.figure_id, a.squad_id, null, null, to_jsonb(a), null);
end $$;

-- Закрыть бой: победитель (null = ничья), итог (силы, броски) — считает помощник.
create or replace function api_battle_close(p_code text, p_battle int, p_winner int, p_result jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); b battles;
begin
  select * into b from battles where id = p_battle for update;
  if b.status <> 'open' then raise exception 'Бой уже закрыт'; end if;
  if not me.is_admin then
    perform require_strategist(me, b.attacker);
  end if;
  if p_winner is not null and p_winner not in (b.attacker, b.defender) then raise exception 'Победитель не из боя'; end if;
  update battles set status = 'closed', winner = p_winner, result = p_result where id = p_battle;
  -- Алая луна: поражение даёт +1 Ярость, победа сжигает всю накопленную; ничья — без изменений
  if p_winner is not null and has_gift(b.game_id, 'alaya') then
    update squads set rage = 0 where id = p_winner;
    update squads set rage = rage + 1
      where id = case when p_winner = b.attacker then b.defender else b.attacker end;
  end if;
  perform log_event(me.id, 'battle_close', b.game_id, null, p_winner, null, null,
    coalesce(p_result,'{}') || jsonb_build_object('battle', p_battle, 'winner', p_winner), null);
end $$;

-- ───────────────────────── API: трофеи ─────────────────────────

create or replace function api_admin_trophy_give(p_code text, p_squad int, p_name text, p_description text,
  p_s int, p_l int, p_v int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); tid int; s squads;
begin
  select * into s from squads where id = p_squad;
  if (select count(*) from trophies where squad_id = p_squad and status = 'active') >= 3 then
    raise exception 'У отряда уже 3 трофея';
  end if;
  insert into trophies (name, description, bonus_s, bonus_l, bonus_v, squad_id)
  values (p_name, coalesce(p_description,''), coalesce(p_s,0), coalesce(p_l,0), coalesce(p_v,0), p_squad)
  returning id into tid;
  perform log_event(me.id, 'trophy_give', s.game_id, null, p_squad, null, null,
    jsonb_build_object('trophy', tid, 'name', p_name), null);
  return tid;
end $$;

-- Взять в отряд трофей, сохранённый с прошлых игр (до старта игры).
create or replace function api_trophy_equip(p_code text, p_trophy int, p_squad int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad); t trophies;
begin
  perform game_open_for_setup(s.game_id, me.is_admin);
  select * into t from trophies where id = p_trophy;
  if t.status <> 'kept' then raise exception 'Трофей не хранится у игрока'; end if;
  if not me.is_admin and not exists (select 1 from strategist_members
      where strategist_id = s.strategist_id and player_id = t.holder) then
    raise exception 'Это не ваш трофей';
  end if;
  update trophies set squad_id = p_squad, status = 'active' where id = p_trophy;
  perform check_strategist_squads(s.strategist_id);
  perform log_event(me.id, 'trophy_equip', s.game_id, null, p_squad, null, null,
    jsonb_build_object('trophy', p_trophy), null);
end $$;

create or replace function api_trophy_drop(p_code text, p_trophy int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); t trophies; s squads;
begin
  select * into t from trophies where id = p_trophy;
  if t.status <> 'active' then raise exception 'Трофей не в отряде'; end if;
  s := require_strategist(me, t.squad_id);
  if exists (select 1 from battles where status = 'open' and t.squad_id in (attacker, defender)) then
    raise exception 'Во время боя трофей выкинуть нельзя';
  end if;
  update trophies set status = 'gone', squad_id = null where id = p_trophy;
  perform log_event(me.id, 'trophy_drop', s.game_id, null, s.id, null, null,
    jsonb_build_object('trophy', p_trophy, 'name', t.name), null);
end $$;

-- Победитель забирает один трофей у побеждённого (один раз за бой).
create or replace function api_trophy_take(p_code text, p_battle int, p_trophy int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); b battles; loser int; t trophies;
begin
  select * into b from battles where id = p_battle;
  if b.status <> 'closed' or b.winner is null then raise exception 'В бою нет победителя'; end if;
  perform require_strategist(me, b.winner);
  loser := case when b.winner = b.attacker then b.defender else b.attacker end;
  select * into t from trophies where id = p_trophy;
  if t.squad_id is distinct from loser or t.status <> 'active' then raise exception 'Трофея нет у побеждённого'; end if;
  if exists (select 1 from events where kind = 'trophy_take' and (data->>'battle')::int = p_battle and not reverted) then
    raise exception 'Трофей за этот бой уже взят';
  end if;
  if (select count(*) from trophies where squad_id = b.winner and status = 'active') >= 3 then
    raise exception 'Нет места: у отряда уже 3 трофея';
  end if;
  update trophies set squad_id = b.winner where id = p_trophy;
  perform log_event(me.id, 'trophy_take', b.game_id, null, b.winner, null, null,
    jsonb_build_object('battle', p_battle, 'trophy', p_trophy, 'from', loser, 'name', t.name), null);
end $$;

-- Итог игры по трофею: остаётся у игрока (p_holder) или исчезает (p_holder = null).
create or replace function api_admin_trophy_end(p_code text, p_trophy int, p_holder int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); t trophies; g int;
begin
  select * into t from trophies where id = p_trophy;
  select game_id into g from squads where id = t.squad_id;
  update trophies set squad_id = null, holder = p_holder,
    status = case when p_holder is null then 'gone' else 'kept' end where id = p_trophy;
  perform log_event(me.id, 'trophy_end', g, null, t.squad_id, p_holder, null,
    jsonb_build_object('trophy', p_trophy, 'name', t.name, 'kept', p_holder is not null), null);
end $$;

-- ───────────────────────── API: гибель фигур в конце игры ─────────────────────────

-- Выбор погибшей фигуры (стратег/ведущий) или жребий (p_figure = null → случайно).
create or replace function api_squad_death(p_code text, p_squad int, p_figure int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad); f int := p_figure; how text;
begin
  if not s.destroyed then raise exception 'Отряд не уничтожен'; end if;
  if s.dead_figure is not null then raise exception 'Погибшая фигура уже выбрана'; end if;
  if f is null then
    select figure_id into f from squad_figures where squad_id = p_squad and not borrowed
      order by gen_random_uuid() limit 1;
    how := 'жребий';
  else
    if not exists (select 1 from squad_figures where squad_id = p_squad and figure_id = f and not borrowed) then
      raise exception 'Эту фигуру выбрать нельзя (её нет в отряде или она взята у противника)';
    end if;
    how := 'выбор';
  end if;
  if f is null then raise exception 'В отряде нет своих фигур'; end if;
  update squads set dead_figure = f where id = p_squad;
  update figures set status = 'dead', died_game = s.game_id, died_how = how where id = f;
  perform log_event(me.id, 'figure_death', s.game_id, f, p_squad, null, null,
    jsonb_build_object('how', how), null);
  return f;
end $$;

-- ───────────────────────── API: откат записи журнала (ведущий) ─────────────────────────
-- Отмечает запись отменённой; фактическое исправление ведущий делает соответствующей
-- функцией (передача обратно, начисление и т. п.) — так история остаётся честной.
create or replace function api_admin_revert(p_code text, p_event bigint, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code);
begin
  update events set reverted = true where id = p_event;
  perform log_event(me.id, 'revert', null, null, null, null, null, jsonb_build_object('event', p_event), p_comment);
end $$;

-- ───────────────────────── представления ─────────────────────────

-- Совладельцы взяли одну фигуру в одну игру у разных стратегов — решает ведущий.
create view figure_conflicts with (security_invoker = true) as
  select sf.game_id, sf.figure_id, f.name, array_agg(sf.squad_id) squads
  from squad_figures sf join figures f on f.id = sf.figure_id
  where not sf.borrowed
  group by sf.game_id, sf.figure_id, f.name having count(*) > 1;

-- Отряд с суммами С/Л/В (фигуры в строю + прибавки трофеев).
create view squad_totals with (security_invoker = true) as
  select s.id squad_id, s.game_id, s.strategist_id, s.name, s.destroyed,
    coalesce((select sum(f.s) from squad_figures sf join figures f on f.id = sf.figure_id
              where sf.squad_id = s.id and sf.state in ('ok','damaged')), 0)
      + coalesce((select sum(bonus_s) from trophies where squad_id = s.id and status = 'active'), 0) s,
    coalesce((select sum(f.l) from squad_figures sf join figures f on f.id = sf.figure_id
              where sf.squad_id = s.id and sf.state in ('ok','damaged')), 0)
      + coalesce((select sum(bonus_l) from trophies where squad_id = s.id and status = 'active'), 0) l,
    coalesce((select sum(f.v) from squad_figures sf join figures f on f.id = sf.figure_id
              where sf.squad_id = s.id and sf.state in ('ok','damaged')), 0)
      + coalesce((select sum(bonus_v) from trophies where squad_id = s.id and status = 'active'), 0) v
  from squads s;

grant select on figure_conflicts, squad_totals to anon, authenticated;

-- ═════════════════════ v2: инициатива, ходы, интриги, Дары лун ═════════════════════

alter table strategists add column initiative int;                 -- задаёт ведущий; у пары одна
alter table squads add column rage int not null default 0 check (rage >= 0);  -- Алая луна

-- Дары лун, включённые в игре (несколько одновременно, ведущий меняет по ходу игры).
create table game_gifts (
  game_id int not null references games(id) on delete cascade,
  gift    text not null check (gift in ('alaya','belaya','gorkaya','chernaya')),
  primary key (game_id, gift)
);

-- Ход игры: сначала интриги, потом действия по инициативе (при Чёрной луне — по тактам).
create table turns (
  id                 serial primary key,
  game_id            int not null references games(id) on delete cascade,
  number             int not null,
  phase              text not null default 'intrigues' check (phase in ('intrigues','actions','done')),
  tacts              int not null default 1 check (tacts >= 1),
  tact               int not null default 1,
  current_strategist int references strategists(id) on delete set null,
  unique (game_id, number)
);

create table squad_moves (
  turn_id       int not null references turns(id) on delete cascade,
  squad_id      int not null references squads(id) on delete cascade,
  strategist_id int not null references strategists(id) on delete cascade,
  tact          int not null,
  action        text not null,   -- для показа: «Перемещение → Нападение»
  movement      text,            -- Перемещение | Стоит на месте (ход ещё не закончен)
  act           text,            -- Нападение | Обмен | Активация фишки | Стоит на месте — ход закончен
  created_at    timestamptz not null default now(),
  primary key (turn_id, squad_id)
);

-- Эхо Расколотого мира (Горькая луна). Скрытые не читаются никем, кроме функций;
-- наружу — только открытые, через представление echoes_public.
create table echoes (
  id                 serial primary key,
  game_id            int not null references games(id) on delete cascade,
  name               text not null,
  description        text not null default '',
  status             text not null default 'hidden' check (status in ('hidden','open','active','ended')),
  end_condition      text not null default '',
  blocked_properties text[] not null default '{}',   -- Святилище: {Подкуп, Плен}
  move_cost          int not null default 0          -- Болото: 1
);

do $$
declare t text;
begin
  foreach t in array array['game_gifts','turns','squad_moves'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy read_all on %I for select using (true)', t);
  end loop;
end $$;
alter table echoes enable row level security;   -- без политики: напрямую не читается

-- Эхо занимает часть карты: в каком Эхо отряд стоит сейчас (его запреты действуют только на этот отряд).
alter table squads add column echo_id int references echoes(id) on delete set null;

create view echoes_public as
  select id, game_id, name, description, status, end_condition, blocked_properties, move_cost
  from echoes where status <> 'hidden';

-- Бонус Белой луны: три разных соседних номинала; число повторов номиналов (для штрафа).
create view squad_moon with (security_invoker = true) as
  select s.id squad_id, s.game_id,
    count(sf.figure_id) = 3 and count(distinct n.rank) = 3 and max(n.rank) - min(n.rank) = 2 white_streak,
    count(sf.figure_id) - count(distinct n.rank) duplicate_nominals
  from squads s
  join squad_figures sf on sf.squad_id = s.id and sf.state in ('ok','damaged')
  join figures f on f.id = sf.figure_id
  join nominals n on n.name = f.nominal
  group by s.id, s.game_id;

grant select on echoes_public, squad_moon to anon, authenticated;

alter publication supabase_realtime add table turns, squad_moves, squads, game_gifts;

create or replace function has_gift(p_game int, p_gift text) returns boolean
language sql stable as $$
  select exists (select 1 from game_gifts where game_id = p_game and gift = p_gift)
$$;

-- Порядок хода: по убыванию инициативы (без инициативы — в конце).
-- Порядок хода: по убыванию инициативы. Чёрная луна: места 1–3 — только стратегам с 1–2 отрядами
-- (по инициативе); стратеги с 3+ отрядами и все, кто не вошёл в тройку, — дальше, по инициативе.
create or replace function turn_order(p_game int) returns table (strategist_id int, pos int)
language sql stable as $$
  with base as (
    select s.id, (select count(*) from squads q where q.strategist_id = s.id) n,
      row_number() over (order by s.initiative desc nulls last, s.id) r
    from strategists s where s.game_id = p_game),
  top3 as (select id from base where n < 3 order by r limit 3)
  select b.id, (row_number() over (order by
      case when has_gift(p_game, 'chernaya') and b.id not in (select id from top3) then 1 else 0 end, b.r))::int
  from base b
$$;

create or replace function strategist_label(p_strategist int) returns text
language sql stable as $$
  select string_agg(coalesce(p.characters[1], p.name), ' и ' order by p.name)
  from strategist_members m join players p on p.id = m.player_id where m.strategist_id = p_strategist
$$;

-- Раньше запрещала стратегу с 3+ отрядами место в первой тройке; теперь turn_order сам ставит его
-- после тройки (14.10.2026), поэтому проверка ничего не запрещает. Оставлена, чтобы не менять вызовы.
create or replace function check_initiative(p_game int) returns void
language plpgsql as $$
begin
  return;
end $$;

create or replace function current_turn(p_game int) returns turns
language sql stable as $$
  select * from turns where game_id = p_game order by number desc limit 1
$$;

-- Есть ли у стратега отряды, чей ход в этом ходу ещё не закончен.
create or replace function strategist_has_unmoved(p_strategist int, p_turn int) returns boolean
language sql stable as $$
  select exists (select 1 from squads s where s.strategist_id = p_strategist and not s.destroyed
    and not exists (select 1 from squad_moves m where m.turn_id = p_turn and m.squad_id = s.id and m.act is not null))
$$;

-- Передать ход следующему стратегу. Обычный ход: каждый по разу по инициативе.
-- Чёрная луна: по кругу тактами, пропуская тех, у кого все отряды уже ходили.
create or replace function advance_turn(p_turn int) returns void
language plpgsql security definer set search_path = public as $$
declare t turns; cur_pos int; nxt int;
begin
  select * into t from turns where id = p_turn for update;
  select pos into cur_pos from turn_order(t.game_id) where strategist_id = t.current_strategist;
  cur_pos := coalesce(cur_pos, 0);
  if not has_gift(t.game_id, 'chernaya') then
    select strategist_id into nxt from turn_order(t.game_id) where pos > cur_pos order by pos limit 1;
    if nxt is null then
      update turns set phase = 'done', current_strategist = null where id = p_turn;
    else
      update turns set current_strategist = nxt where id = p_turn;
    end if;
    return;
  end if;
  loop
    -- следующий по инициативе, у кого есть не ходившие отряды и кто ещё не действовал в этом такте
    select o.strategist_id into nxt from turn_order(t.game_id) o
      where o.pos > cur_pos and strategist_has_unmoved(o.strategist_id, p_turn)
        and not exists (select 1 from squad_moves m where m.turn_id = p_turn
                        and m.strategist_id = o.strategist_id and m.tact = t.tact)
      order by o.pos limit 1;
    exit when nxt is not null;
    t.tact := t.tact + 1;  -- круг закончился — следующий такт
    cur_pos := 0;
    if t.tact > t.tacts or not exists (select 1 from strategists st
         where st.game_id = t.game_id and strategist_has_unmoved(st.id, p_turn)) then
      update turns set phase = 'done', current_strategist = null where id = p_turn;
      return;
    end if;
  end loop;
  update turns set current_strategist = nxt, tact = t.tact where id = p_turn;
end $$;

-- Запрет свойства действующим Эхо — только для отряда, который стоит в этом Эхо.
create or replace function check_echo_blocks(p_squad int, p_property text) returns void
language plpgsql security definer set search_path = public as $$
declare e text;
begin
  select e2.name into e from squads s join echoes e2 on e2.id = s.echo_id
    where s.id = p_squad and e2.status = 'active' and p_property = any(e2.blocked_properties);
  if e is not null then
    raise exception 'Действует Эхо «%»: свойство «%» здесь не работает', e, p_property;
  end if;
end $$;

-- ───────────────────────── API v2: дары, инициатива ─────────────────────────

create or replace function api_admin_gift(p_code text, p_game int, p_gift text, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code);
begin
  if p_on then
    insert into game_gifts values (p_game, p_gift) on conflict do nothing;
    perform check_initiative(p_game);
  else
    delete from game_gifts where game_id = p_game and gift = p_gift;
  end if;
  perform log_event(me.id, case when p_on then 'gift_on' else 'gift_off' end, p_game, null, null, null, null,
    jsonb_build_object('gift', p_gift), null);
end $$;

create or replace function api_admin_initiative(p_code text, p_strategist int, p_value int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); g int;
begin
  update strategists set initiative = p_value where id = p_strategist returning game_id into g;
  if g is null then raise exception 'Нет такого стратега'; end if;
  perform check_initiative(g);
  perform log_event(me.id, 'initiative', g, null, null, null, p_value,
    jsonb_build_object('strategist', p_strategist, 'label', strategist_label(p_strategist)), null);
end $$;

-- ───────────────────────── API v2: ходы ─────────────────────────

-- Новый ход: фаза интриг. p_tacts — число тактов (только при Чёрной луне, по умолчанию 2).
create or replace function api_admin_turn_start(p_code text, p_game int, p_tacts int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); n int; tid int;
begin
  if (select status from games where id = p_game) <> 'running' then raise exception 'Игра не идёт'; end if;
  perform check_initiative(p_game);
  select coalesce(max(number), 0) + 1 into n from turns where game_id = p_game;
  update turns set phase = 'done', current_strategist = null where game_id = p_game and phase <> 'done';
  insert into turns (game_id, number, tacts)
  values (p_game, n, case when has_gift(p_game, 'chernaya') then greatest(coalesce(p_tacts, 2), 1) else 1 end)
  returning id into tid;
  perform log_event(me.id, 'turn_start', p_game, null, null, null, n, '{}', null);
  return n;
end $$;

-- Интриги закончены — действия по инициативе.
create or replace function api_admin_turn_actions(p_code text, p_game int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); t turns := current_turn(p_game);
begin
  if t.id is null or t.phase <> 'intrigues' then raise exception 'Сейчас не фаза интриг'; end if;
  update turns set phase = 'actions' where id = t.id;
  perform advance_turn(t.id);
  perform log_event(me.id, 'turn_actions', p_game, null, null, null, t.number, '{}', null);
end $$;

-- Ведущий вручную ставит указатель хода.
create or replace function api_admin_turn_set(p_code text, p_game int, p_strategist int, p_tact int, p_phase text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); t turns := current_turn(p_game);
begin
  if t.id is null then raise exception 'Ходов ещё не было'; end if;
  update turns set current_strategist = p_strategist, tact = coalesce(p_tact, tact),
    phase = coalesce(p_phase, phase) where id = t.id;
  perform log_event(me.id, 'turn_set', p_game, null, null, null, t.number,
    jsonb_build_object('strategist', p_strategist, 'tact', p_tact, 'phase', p_phase), null);
end $$;

create or replace function api_intrigue(p_code text, p_game int, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); t turns := current_turn(p_game); sid int := strategist_of(me.id, p_game);
begin
  if not me.is_admin then
    if sid is null then raise exception 'Вы не участвуете в этой игре'; end if;
    if t.id is null or t.phase <> 'intrigues' then
      raise exception 'Интриги активируют в начале хода, до действий по инициативе';
    end if;
  end if;
  perform log_event(me.id, 'intrigue', p_game, null, null, null, t.number,
    jsonb_build_object('strategist', sid, 'label', strategist_label(sid)), p_text);
end $$;

-- Отметить ход отряда (Перемещение, Активация фишки, Обмен, Нападение…).
-- Ход отряда за ход игры — две части:
--   движение: «Перемещение» или «Стоит на месте» (ход ещё не закончен);
--   действие: «Нападение», «Обмен», «Активация фишки» или «Стоит на месте» — ход закончен.
-- Действие можно заявить и без движения. Чёрная луна: за такт стратег действует одним отрядом;
-- такт уходит дальше, когда ход этого отряда закончен.
create or replace function squad_turn_step(p_squad int, p_kind text, p_value text, p_actor players, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare s squads; t turns; m squad_moves; chern boolean; other text; done boolean;
begin
  select * into s from squads where id = p_squad;
  t := current_turn(s.game_id);
  if t.id is null or t.phase <> 'actions' then
    if p_kind = 'act' and p_value in ('Нападение', 'Обмен') then return; end if;  -- вне трекера ходов — без отметки
    raise exception 'Сейчас не фаза действий';
  end if;
  if not p_actor.is_admin and t.current_strategist is distinct from s.strategist_id then
    raise exception 'Сейчас ходит %', coalesce(strategist_label(t.current_strategist), 'другой стратег');
  end if;
  chern := has_gift(s.game_id, 'chernaya');
  select * into m from squad_moves where turn_id = t.id and squad_id = p_squad;
  if m.act is not null then raise exception 'Ход отряда «%» в этом ходу уже закончен', s.name; end if;
  if chern and m.squad_id is null then
    select q.name into other from squad_moves mm join squads q on q.id = mm.squad_id
      where mm.turn_id = t.id and mm.strategist_id = s.strategist_id and mm.tact = t.tact and mm.squad_id <> p_squad limit 1;
    if other is not null then raise exception 'Чёрная луна: в этом такте вы уже действовали отрядом «%»', other; end if;
  end if;
  if p_kind = 'movement' then
    if m.movement is not null then raise exception 'Отряд «%» уже двигался в этом ходу', s.name; end if;
    insert into squad_moves (turn_id, squad_id, strategist_id, tact, action, movement)
    values (t.id, p_squad, s.strategist_id, t.tact, p_value, p_value)
    on conflict (turn_id, squad_id) do update set movement = p_value, action = p_value;
    if p_value = 'Перемещение' then update squads set echo_id = null where id = p_squad; end if;  -- ушёл из Эхо
  else
    insert into squad_moves (turn_id, squad_id, strategist_id, tact, action, act)
    values (t.id, p_squad, s.strategist_id, t.tact, p_value, p_value)
    on conflict (turn_id, squad_id) do update set act = p_value, action = concat_ws(' → ', squad_moves.movement, p_value);
  end if;
  done := p_kind = 'act';
  perform log_event(p_actor.id, 'squad_move', s.game_id, null, p_squad, null, t.number,
    jsonb_build_object('action', p_value, 'part', p_kind, 'tact', t.tact, 'finished', done), p_comment);
  -- такт уходит дальше, когда ход отряда текущего стратега закончен
  if chern and done and t.current_strategist = s.strategist_id then perform advance_turn(t.id); end if;
end $$;

-- Действие отряда из боя и обмена (Нападение, Обмен): ход отряда заканчивается.
create or replace function squad_act(p_squad int, p_act text, p_actor players) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform squad_turn_step(p_squad, 'act', p_act, p_actor, null);
end $$;

-- Отметить ход отряда: «Перемещение», «Стоит на месте», «Активация фишки».
-- «Стоит на месте»: до движения — вместо движения; после движения — вместо действия (ход закончен).
create or replace function api_squad_move(p_code text, p_squad int, p_action text, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad); t turns := current_turn(s.game_id);
  moved boolean;
begin
  moved := exists (select 1 from squad_moves where turn_id = t.id and squad_id = p_squad and movement is not null);
  case p_action
    when 'Перемещение' then perform squad_turn_step(p_squad, 'movement', p_action, me, p_comment);
    when 'Стоит на месте' then
      perform squad_turn_step(p_squad, case when moved then 'act' else 'movement' end, p_action, me, p_comment);
    when 'Активация фишки' then perform squad_turn_step(p_squad, 'act', p_action, me, p_comment);
    else raise exception 'Нападение и Обмен — своими кнопками; здесь: Перемещение, Стоит на месте, Активация фишки';
  end case;
end $$;

-- Отряд прошёл через Эхо (разово: цена движения) или остановился в нём (эффект действует, пока не уйдёт);
-- p_mode: passed | stopped | left. Игрок — только открытые Эхо; ведущий — любые.
create or replace function api_squad_echo(p_code text, p_squad int, p_echo int, p_mode text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad); e echoes; cost int := 0;
begin
  if p_mode not in ('passed', 'stopped', 'left') then raise exception 'Неизвестная отметка Эхо'; end if;
  if p_mode = 'left' then
    update squads set echo_id = null where id = p_squad;
    perform log_event(me.id, 'squad_echo', s.game_id, null, p_squad, null, null, jsonb_build_object('mode', 'left'), null);
    return;
  end if;
  select * into e from echoes where id = p_echo;
  if e.id is null or e.game_id <> s.game_id then raise exception 'Нет такого Эхо в этой игре'; end if;
  if not me.is_admin and e.status not in ('open', 'active') then raise exception 'Это Эхо ещё не обнаружено'; end if;
  if e.status = 'active' and e.move_cost > 0 then
    cost := e.move_cost;
    perform strategist_pay(s.strategist_id, cost, me.id, 'Эхо: движение', s.game_id, null, p_squad);
  end if;
  if p_mode = 'stopped' then update squads set echo_id = p_echo where id = p_squad; end if;
  perform log_event(me.id, 'squad_echo', s.game_id, null, p_squad, null, cost,
    case when e.status = 'hidden' then jsonb_build_object('mode', p_mode)
         else jsonb_build_object('mode', p_mode, 'echo', e.id, 'name', e.name) end, null);
end $$;

-- Закончить свой ход (обычный режим) или пропустить такт.
create or replace function api_pass_turn(p_code text, p_game int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); t turns := current_turn(p_game);
begin
  if t.id is null or t.phase <> 'actions' then raise exception 'Сейчас не фаза действий'; end if;
  if not me.is_admin and t.current_strategist is distinct from strategist_of(me.id, p_game) then
    raise exception 'Сейчас не ваш ход';
  end if;
  perform log_event(me.id, 'turn_pass', p_game, null, null, null, t.number,
    jsonb_build_object('strategist', t.current_strategist, 'tact', t.tact), null);
  perform advance_turn(t.id);
end $$;

-- ───────────────────────── API v2: Ярость, оплата, Эхо ─────────────────────────

-- Трата 1 Ярости: move (+1 к перемещению), power (+5 Силы, раз за бой), remote (фишка издалека).
create or replace function api_rage_spend(p_code text, p_squad int, p_use text, p_battle int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad); b battles;
begin
  if not has_gift(s.game_id, 'alaya') then raise exception 'Дар Алой луны не действует'; end if;
  if p_use not in ('move','power','remote') then raise exception 'Неизвестная трата Ярости'; end if;
  select * into s from squads where id = p_squad for update;
  if s.rage < 1 then raise exception 'У отряда «%» нет Ярости', s.name; end if;
  if p_use = 'power' then
    select * into b from battles where id = p_battle;
    if b.id is null or b.status <> 'open' or p_squad not in (b.attacker, b.defender) then
      raise exception '+5 к Силе — только в идущем бою этого отряда';
    end if;
    if exists (select 1 from battle_actions where battle_id = p_battle and squad_id = p_squad
               and kind = 'rage' and params->>'use' = 'power') then
      raise exception '+5 к Силе от Ярости — только один раз за бой';
    end if;
    insert into battle_actions (battle_id, kind, squad_id, params, actor)
    values (p_battle, 'rage', p_squad, jsonb_build_object('use', 'power', 'bonus', 5), me.id);
  end if;
  update squads set rage = rage - 1 where id = p_squad;
  perform log_event(me.id, 'rage_spend', s.game_id, null, p_squad, null, 1,
    jsonb_build_object('use', p_use, 'battle', p_battle), p_comment);
end $$;

create or replace function api_admin_rage(p_code text, p_squad int, p_rage int, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); g int;
begin
  update squads set rage = p_rage where id = p_squad returning game_id into g;
  perform log_event(me.id, 'rage_set', g, null, p_squad, null, p_rage, '{}', p_comment);
end $$;

-- Оплата Ресурсами вне свойств (Болото и подобное).
create or replace function api_pay(p_code text, p_squad int, p_amount int, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad);
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  if (select status from games where id = s.game_id) <> 'running' then raise exception 'Игра не идёт'; end if;
  perform strategist_pay(s.strategist_id, p_amount, me.id, coalesce(p_reason, 'Оплата'), s.game_id, null, p_squad);
end $$;

-- Завести или изменить Эхо. Пока скрыто — в журнал попадает только факт изменения.
create or replace function api_admin_echo(p_code text, p_id int, p_game int, p_name text, p_description text,
  p_status text, p_end_condition text, p_blocked text[], p_move_cost int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); eid int := p_id;
begin
  if eid is null then
    insert into echoes (game_id, name, description, status, end_condition, blocked_properties, move_cost)
    values (p_game, p_name, coalesce(p_description,''), coalesce(p_status,'hidden'), coalesce(p_end_condition,''),
            coalesce(p_blocked,'{}'), coalesce(p_move_cost,0))
    returning id into eid;
  else
    update echoes set name = p_name, description = coalesce(p_description,''), status = p_status,
      end_condition = coalesce(p_end_condition,''), blocked_properties = coalesce(p_blocked,'{}'),
      move_cost = coalesce(p_move_cost,0)
    where id = eid;
  end if;
  perform log_event(me.id, 'echo', p_game, null, null, null, null,
    case when coalesce(p_status,'hidden') = 'hidden' then jsonb_build_object('echo', eid)
         else jsonb_build_object('echo', eid, 'name', p_name, 'status', p_status) end, null);
  return eid;
end $$;

-- Ведущему: все Эхо игры, включая скрытые.
create or replace function api_admin_echoes(p_code text, p_game int) returns setof echoes
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code);
begin
  return query select * from echoes where game_id = p_game order by id;
end $$;

-- Вызывать из браузера можно только api_*; служебные функции закрыты.
revoke execute on all functions in schema public from anon, authenticated, public;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'api\_%'
  loop
    execute format('grant execute on function %s to anon, authenticated', f.sig);
  end loop;
end $$;
