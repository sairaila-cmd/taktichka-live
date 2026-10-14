-- 002 (14.10.2026): правила после первой пробной настройки игры.
--  * Ресурсы напарников: пока пара играет, начисления и передачи идут через общий кошелёк;
--    Ресурсы, начисленные после оформления пары, переносятся в кошелёк (fix_pair_wallets).
--  * Ход отряда: движение (Перемещение / Стоит на месте) + одно действие (Нападение / Обмен /
--    Активация фишки / Стоит на месте); действие заканчивает ход. Обмен — только начавшему отряду.
--  * Чёрная луна: стратег с 3+ отрядами сам встаёт после первой тройки (без ошибки инициативы).
--  * Эхо — зона: запреты действуют только на отряд, стоящий в Эхо; проход через Эхо — цена движения.
--  * Трофей нельзя выкинуть во время боя. Ведущий собирает и правит отряды за стратегов.
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor целиком.

alter table squad_moves add column if not exists movement text;
alter table squad_moves add column if not exists act text;
update squad_moves set act = action where act is null;   -- старые записи — законченные ходы
alter table squads add column if not exists echo_id int references echoes(id) on delete set null;

drop function if exists check_echo_blocks(int, text);
drop function if exists api_squad_save(text, int, int, text, int[]);

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

-- Раньше запрещала стратегу с 3+ отрядами место в первой тройке; теперь turn_order сам ставит его
-- после тройки (14.10.2026), поэтому проверка ничего не запрещает. Оставлена, чтобы не менять вызовы.
create or replace function check_initiative(p_game int) returns void
language plpgsql as $$
begin
  return;
end $$;

-- Есть ли у стратега отряды, чей ход в этом ходу ещё не закончен.
create or replace function strategist_has_unmoved(p_strategist int, p_turn int) returns boolean
language sql stable as $$
  select exists (select 1 from squads s where s.strategist_id = p_strategist and not s.destroyed
    and not exists (select 1 from squad_moves m where m.turn_id = p_turn and m.squad_id = s.id and m.act is not null))
$$;

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

select 'ok' as миграция_002, fix_pair_wallets() as пар_починено,
  (select string_agg(strategist_label(id) || ': ' || wallet, '; ') from strategists where wallet is not null) as кошельки_пар;
