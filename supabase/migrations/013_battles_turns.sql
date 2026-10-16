-- 013 (16.10.2026): бои, ходы, Ресурсы по игре, realtime.
--   · бои отряда удаляются вместе с отрядом (раньше «Убрать» стратега и «Отменить игру» после боёв
--     падали на battles_attacker_fkey / battle_actions_squad_id_fkey); отряд в идущем бою нельзя
--     распустить или слить Обменом;
--   · итог боя записывает атакующий, защищающийся или ведущий;
--   · ход не уходит к следующему стратегу, пока идёт бой его отряда (Чёрная луна: такт нападавшего
--     уходит после итога боя; «Закончить ход / Пропустить такт» во время боя — отказ);
--   · ± Ресурсы и передача Ресурсов — в кошелёк пары выбранной игры (p_game), а не последней;
--   · таблицы страницы игры и боя — в публикации realtime (ход обновляется без перезагрузки).
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor. Повторный запуск ничего не портит.

-- ───────── внешние ключи боёв ─────────
alter table battles
  drop constraint if exists battles_attacker_fkey,
  add constraint battles_attacker_fkey foreign key (attacker) references squads(id) on delete cascade,
  drop constraint if exists battles_defender_fkey,
  add constraint battles_defender_fkey foreign key (defender) references squads(id) on delete cascade,
  drop constraint if exists battles_winner_fkey,
  add constraint battles_winner_fkey foreign key (winner) references squads(id) on delete set null;
alter table battle_actions
  drop constraint if exists battle_actions_squad_id_fkey,
  add constraint battle_actions_squad_id_fkey foreign key (squad_id) references squads(id) on delete cascade;

-- ───────── функции: старые сигнатуры Ресурсов убираются (новые — с p_game) ─────────
drop function if exists api_resources_transfer(text, int, int, text);
drop function if exists api_admin_resources(text, int, int, text);
drop function if exists add_resources(int, int);
drop function if exists balance_of(int);
drop function if exists open_wallet(int);

-- Общий кошелёк пары, в которой игрок состоит в незакрытой игре (null — играет один или не играет).
-- Пока пара играет, все Ресурсы участников идут через этот кошелёк. p_game — именно в этой игре
-- (страница «Персонажи» выбранной игры); без неё — в последней незакрытой.
create or replace function open_wallet(p_player int, p_game int default null) returns int
language sql stable as $$
  select s.id from strategist_members m
    join strategists s on s.id = m.strategist_id
    join games g on g.id = s.game_id
  where m.player_id = p_player and s.wallet is not null and g.status <> 'closed'
    and (p_game is null or g.id = p_game)
  order by g.id desc limit 1
$$;

-- Сколько Ресурсов у игрока сейчас (у пары — общий кошелёк).
create or replace function balance_of(p_player int, p_game int default null) returns int
language sql stable as $$
  select coalesce((select wallet from strategists where id = open_wallet(p_player, p_game)),
                  (select resources from players where id = p_player))
$$;

-- Изменить Ресурсы игрока (или общий кошелёк его пары); в минус нельзя.
create or replace function add_resources(p_player int, p_amount int, p_game int default null) returns int
language plpgsql security definer set search_path = public as $$
declare w int := open_wallet(p_player, p_game); have int := balance_of(p_player, p_game);
begin
  if have + p_amount < 0 then
    raise exception 'Не хватает Ресурсов (есть %)', have || case when w is null then '' else ' в общем кошельке пары' end;
  end if;
  if w is not null then update strategists set wallet = wallet + p_amount where id = w;
  else update players set resources = resources + p_amount where id = p_player; end if;
  return w;
end $$;

-- p_game — игра, выбранная на странице «Персонажи»: кошельки пар берутся из неё (null — как раньше).
create or replace function api_resources_transfer(p_code text, p_to int, p_amount int, p_comment text,
  p_game int default null) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); wf int; wt int;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  if p_to = me.id then raise exception 'Нельзя передать самому себе'; end if;
  if open_wallet(me.id, p_game) is not null and open_wallet(me.id, p_game) = open_wallet(p_to, p_game) then
    raise exception 'Вы напарники: Ресурсы и так общие';
  end if;
  wf := add_resources(me.id, -p_amount, p_game);
  wt := add_resources(p_to, p_amount, p_game);
  perform log_event(me.id, 'resources_transfer', p_game, null, null, p_to, p_amount,
    jsonb_build_object('from', me.id, 'to', p_to, 'from_wallet', wf, 'to_wallet', wt), p_comment);
end $$;

create or replace function api_admin_resources(p_code text, p_player int, p_amount int, p_comment text,
  p_game int default null) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); w int;
begin
  w := add_resources(p_player, p_amount, p_game);
  perform log_event(me.id, 'resources_grant', p_game, null, null, p_player, p_amount,
    jsonb_build_object('wallet', w), p_comment);
end $$;

-- Идущий бой, в котором участвует отряд стратега (null — такого нет).
create or replace function open_battle_of(p_strategist int) returns battles
language sql stable as $$
  select b.* from battles b
  where b.status = 'open' and exists (select 1 from squads s
    where s.id in (b.attacker, b.defender) and s.strategist_id = p_strategist)
  order by b.id limit 1
$$;

-- Отряд в идущем бою нельзя распустить или слить — сначала итог боя.
create or replace function check_not_in_battle(p_squad int) returns void
language plpgsql as $$
begin
  if exists (select 1 from battles where status = 'open' and p_squad in (attacker, defender)) then
    raise exception 'Отряд «%» сейчас в бою — сначала подведите итог боя', (select name from squads where id = p_squad);
  end if;
end $$;

-- Отменить игру на подготовке: игра удаляется со стратегами и отрядами. Общие кошельки пар —
-- участникам поровну (нечётный остаток — первому), трофеи — в запас, название игры — из «Источников».
create or replace function api_admin_game_cancel(p_code text, p_game int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); g games; r record; share int;
begin
  select * into g from games where id = p_game for update;
  if not found then raise exception 'Игра не найдена'; end if;
  if g.status <> 'draft' then raise exception 'Отменить можно только игру на подготовке'; end if;
  for r in select s.id, s.wallet, array_agg(m.player_id order by m.player_id) as members
           from strategists s join strategist_members m on m.strategist_id = s.id
           where s.game_id = p_game and coalesce(s.wallet, 0) > 0 group by s.id, s.wallet
  loop
    share := r.wallet / cardinality(r.members);
    update players set resources = resources + share where id = any(r.members);
    update players set resources = resources + r.wallet - share * cardinality(r.members) where id = r.members[1];
  end loop;
  update trophies set status = 'kept', squad_id = null
    where holder is not null and status = 'active' and squad_id in (select id from squads where game_id = p_game);
  if not is_test_game(p_game) then
    perform drop_source(x.figure_id, g.title)
      from (select distinct figure_id from squad_figures where game_id = p_game) x;
  end if;
  perform log_event(me.id, 'game_cancel', null, null, null, null, null,
    jsonb_build_object('title', g.title, 'game', p_game), null);
  delete from battles where game_id = p_game;   -- бои (если игру запускали) — до отрядов
  delete from games where id = p_game;
end $$;

create or replace function api_squad_delete(p_code text, p_squad int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad);
begin
  perform game_open_for_setup(s.game_id, me.is_admin);
  perform check_not_in_battle(p_squad);
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
    perform check_not_in_battle(p_b);
    delete from squads where id = p_b;
  end if;
  perform check_strategist_squads(a.strategist_id);
  perform log_event(me.id, 'exchange', a.game_id, null, p_a, null, null,
    jsonb_build_object('a', p_a, 'b', p_b, 'a_figures', p_a_figures, 'b_figures', p_b_figures,
      'a_trophies', p_a_trophies, 'b_trophies', p_b_trophies), null);
end $$;

-- Закрыть бой: победитель (null = ничья), итог (силы, броски) — считает помощник.
-- Записать итог может атакующий, защищающийся (любой из пары) или ведущий — кто нажмёт первым.
-- Чёрная луна: такт нападавшего уходит дальше только теперь, когда бой закончен.
create or replace function api_battle_close(p_code text, p_battle int, p_winner int, p_result jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); b battles; att squads; t record;   -- turns объявлена ниже
begin
  select * into b from battles where id = p_battle for update;
  if not found then raise exception 'Бой не найден'; end if;
  if b.status <> 'open' then raise exception 'Бой уже закрыт'; end if;
  select * into att from squads where id = b.attacker;
  if not me.is_admin and strategist_of(me.id, b.game_id) is distinct from att.strategist_id
     and strategist_of(me.id, b.game_id) is distinct from (select strategist_id from squads where id = b.defender) then
    raise exception 'Записать итог может атакующий, защищающийся или ведущий';
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
  select * into t from turns where game_id = b.game_id order by number desc limit 1;
  if found and t.phase = 'actions' and has_gift(b.game_id, 'chernaya')
     and t.current_strategist = att.strategist_id
     and exists (select 1 from squad_moves where turn_id = t.id and squad_id = b.attacker
                 and act = 'Нападение' and tact = t.tact)
     and (open_battle_of(att.strategist_id)).id is null then
    perform advance_turn(t.id);
  end if;
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
  if chern and m.squad_id is not null and m.tact < t.tact then
    raise exception 'Отряд «%» уже ходил в такте % этого хода', s.name, m.tact;
  end if;
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
  -- такт уходит дальше, когда ход отряда текущего стратега закончен; после Нападения — когда закончится бой
  -- (api_battle_close)
  if chern and done and p_value <> 'Нападение' and t.current_strategist = s.strategist_id then
    perform advance_turn(t.id);
  end if;
end $$;

-- Закончить свой ход (обычный режим) или пропустить такт. Пока идёт бой с отрядом ходящего
-- стратега, ход дальше не уходит (ведущий может переставить указатель «Передать ход…»).
create or replace function api_pass_turn(p_code text, p_game int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); t turns := current_turn(p_game); b battles;
begin
  if t.id is null or t.phase <> 'actions' then raise exception 'Сейчас не фаза действий'; end if;
  if not me.is_admin and t.current_strategist is distinct from strategist_of(me.id, p_game) then
    raise exception 'Сейчас не ваш ход';
  end if;
  b := open_battle_of(t.current_strategist);
  if b.id is not null then
    raise exception 'Идёт бой «%» → «%» — сначала подведите итог боя',
      (select name from squads where id = b.attacker), (select name from squads where id = b.defender);
  end if;
  perform log_event(me.id, 'turn_pass', p_game, null, null, null, t.number,
    jsonb_build_object('strategist', t.current_strategist, 'tact', t.tact), null);
  perform advance_turn(t.id);
end $$;

-- ───────── права: служебные закрыты, api_* открыты ─────────
revoke execute on function open_wallet(int, int), balance_of(int, int), add_resources(int, int, int),
  open_battle_of(int), check_not_in_battle(int) from public, anon, authenticated;
revoke execute on function api_resources_transfer(text, int, int, text, int), api_admin_resources(text, int, int, text, int)
  from public;
grant execute on function api_resources_transfer(text, int, int, text, int), api_admin_resources(text, int, int, text, int),
  api_admin_game_cancel(text, int), api_squad_delete(text, int),
  api_exchange(text, int, int, int[], int[], int[], int[]), api_battle_close(text, int, int, jsonb),
  api_pass_turn(text, int) to anon, authenticated;

-- ───────── realtime: таблицы страницы игры и боя ─────────
do $$
declare t text;
begin
  foreach t in array array['battles','battle_actions','squad_figures','strategists','players',
                           'turns','squad_moves','squads','game_gifts'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;

select format('realtime %s из 9; ключи боёв %s из 4; функции %s из 2',
  (select count(*) from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'
     and tablename in ('battles','battle_actions','squad_figures','strategists','players','turns','squad_moves','squads','game_gifts')),
  (select count(*) from pg_constraint where conname in ('battles_attacker_fkey','battles_defender_fkey',
     'battles_winner_fkey','battle_actions_squad_id_fkey') and confdeltype in ('c','n')),
  (select count(*) from pg_proc where proname in ('open_battle_of','check_not_in_battle'))) as миграция_13;
-- ожидается: realtime 9 из 9; ключи боёв 4 из 4; функции 2 из 2
