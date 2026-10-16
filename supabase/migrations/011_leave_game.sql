-- 011 (16.10.2026): уход из игры и отмена игры на подготовке.
--   · api_strategist_leave — игрок выходит сам, ведущий убирает любого; из пары уходит один,
--     общий кошелёк делится пополам, отряды без фигур распускаются, трофеи — в запас;
--   · api_admin_game_cancel — ведущий отменяет (удаляет) игру на подготовке;
--   · drop_source — у фигур, снятых из игры, её название убирается из «Источников»
--     (api_admin_game при переименовании пользуется им же).
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor.

-- Убрать источник из «a; b; c» фигуры (игру переименовали, отменили или фигуру из неё сняли).
create or replace function drop_source(p_figure int, p_title text) returns void
language sql security definer set search_path = public as $$
  update figures f set sources = array_to_string(array(
      select btrim(x) from unnest(string_to_array(f.sources, ';')) with ordinality u(x, n)
      where btrim(x) <> btrim(p_title) and btrim(x) <> '' order by n), '; ')
  where f.id = p_figure
$$;

create or replace function api_admin_game(p_code text, p_id int, p_title text, p_starts_at timestamptz,
  p_status text) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); gid int; pending int; old_title text;
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
    select title into old_title from games where id = p_id;
    update games set title = p_title, starts_at = p_starts_at, status = p_status where id = p_id;
    gid := p_id;
    -- переименование: у фигур отрядов этой игры старое название в «Источниках» меняется на новое
    if btrim(old_title) is distinct from btrim(p_title) then
      perform drop_source(x.figure_id, old_title)
        from (select distinct figure_id from squad_figures where game_id = gid) x;
      if not is_test_game(gid) then
        perform add_source(sf.figure_id, p_title) from squad_figures sf where sf.game_id = gid;
      end if;
    end if;
  end if;
  perform log_event(me.id, 'game_' || coalesce(p_status,'draft'), gid, null, null, null, null,
    jsonb_build_object('title', p_title), null);
  return gid;
end $$;

-- Выйти из игры на подготовке: игрок — только сам, ведущий — убирает любого (p_player).
-- Одиночка уходит со всеми отрядами. Из пары уходит один: его фигуры снимаются с общих отрядов
-- (опустевшие отряды распускаются), общий кошелёк делится пополам (нечётный остаток — оставшемуся),
-- напарник остаётся одиночкой. Трофеи из распущенных отрядов и трофеи ушедшего — в запас владельцу.
create or replace function api_strategist_leave(p_code text, p_game int, p_player int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); pid int := coalesce(p_player, me.id); sid int; st strategists;
  other int; share int := 0; gone int[]; empty int[]; n_squads int := 0;
begin
  if pid <> me.id and not me.is_admin then raise exception 'Убрать другого стратега может только ведущий'; end if;
  perform game_open_for_setup(p_game, false);
  sid := strategist_of(pid, p_game);
  if sid is null then raise exception 'Персонаж не участвует в игре'; end if;
  select * into st from strategists where id = sid for update;
  select player_id into other from strategist_members where strategist_id = sid and player_id <> pid;
  if other is null then
    select array_agg(distinct figure_id) into gone from squad_figures where strategist_id = sid;
    select array_agg(id) into empty from squads where strategist_id = sid;
  else
    share := coalesce(st.wallet, 0) / 2;
    update players set resources = resources + share where id = pid;
    update players set resources = resources + coalesce(st.wallet, 0) - share where id = other;
    update strategists set wallet = null, invited = null where id = sid;
    select array_agg(distinct figure_id) into gone from squad_figures
      where strategist_id = sid and is_owner(pid, figure_id) and not is_owner(other, figure_id);
    delete from squad_figures where strategist_id = sid and figure_id = any(coalesce(gone, '{}'));
    update trophies set status = 'kept', squad_id = null
      where holder = pid and status = 'active' and squad_id in (select id from squads where strategist_id = sid);
    delete from strategist_members where strategist_id = sid and player_id = pid;
    select array_agg(id) into empty from squads s where s.strategist_id = sid
      and not exists (select 1 from squad_figures sf where sf.squad_id = s.id);
  end if;
  n_squads := coalesce(cardinality(empty), 0);
  update trophies set status = 'kept', squad_id = null
    where holder is not null and status = 'active' and squad_id = any(coalesce(empty, '{}'));
  if other is null then delete from strategists where id = sid;
  else delete from squads where id = any(coalesce(empty, '{}')); end if;
  if not is_test_game(p_game) then
    perform drop_source(f, (select title from games where id = p_game)) from unnest(coalesce(gone, '{}')) f
      where not exists (select 1 from squad_figures where game_id = p_game and figure_id = f);
  end if;
  perform log_event(me.id, 'leave_game', p_game, null, null, pid, share,
    jsonb_build_object('squads', n_squads, 'partner', other), case when pid <> me.id then 'убрал ведущий' end);
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
  delete from games where id = p_game;
end $$;

revoke execute on function drop_source(int, text) from public, anon, authenticated;
revoke execute on function api_strategist_leave(text, int, int), api_admin_game_cancel(text, int) from public;
grant execute on function api_strategist_leave(text, int, int), api_admin_game_cancel(text, int) to anon, authenticated;

select count(*) as миграция_11 from pg_proc
where proname in ('api_strategist_leave', 'api_admin_game_cancel', 'drop_source');
