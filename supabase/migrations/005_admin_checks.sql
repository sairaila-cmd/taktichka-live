-- 005 (15.10.2026): проверки в действиях ведущего.
--   · Фигура, возвращённая владельцу («Фигуру в другой отряд»), больше не остаётся «взятой у противника».
--   · Перенос фигуры, которой нет в отряде (или в отряд другой игры), — отказ, а не пустая запись в журнале.
--   · Отмена несуществующего шага боя — отказ.
--   · «Передать ход…» — только стратегу этой игры.
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor.

-- Переместить фигуру в другой отряд (Подкуп, Перспективы и т. п.) — только ведущий
-- или через помощник боя. Возвращается владельцу по итогам игры.
create or replace function api_admin_move_figure(p_code text, p_from int, p_to int, p_figure int, p_comment text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); f squads; t squads; sf squad_figures;
begin
  select * into f from squads where id = p_from;
  select * into t from squads where id = p_to;
  if f.id is null or t.id is null then raise exception 'Нет такого отряда'; end if;
  if f.id = t.id then raise exception 'Фигура уже в этом отряде'; end if;
  if f.game_id <> t.game_id then raise exception 'Отряды из разных игр'; end if;
  select * into sf from squad_figures where squad_id = p_from and figure_id = p_figure;
  if not found then raise exception 'Фигуры нет в отряде «%»', f.name; end if;
  -- «взята у противника» — если у нового стратега нет владельца фигуры; между своими отрядами — как было
  update squad_figures set squad_id = p_to, strategist_id = t.strategist_id,
    borrowed = case when t.strategist_id = f.strategist_id then sf.borrowed
      else not exists (select 1 from figure_owners o join strategist_members m on m.player_id = o.player_id
                       where o.figure_id = p_figure and m.strategist_id = t.strategist_id) end
  where squad_id = p_from and figure_id = p_figure;
  perform log_event(me.id, 'figure_move', t.game_id, p_figure, p_to, null, null,
    jsonb_build_object('from', p_from, 'to', p_to), p_comment);
end $$;

-- Отменить шаг боя (ведущий): ресурсы за отменённое свойство возвращаются.
create or replace function api_admin_battle_undo(p_code text, p_action int) returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); a battle_actions; s squads;
begin
  select * into a from battle_actions where id = p_action;
  if not found then raise exception 'Нет такого шага боя (возможно, уже отменён)'; end if;
  select * into s from squads where id = a.squad_id;
  if a.cost > 0 then
    perform strategist_pay(s.strategist_id, -a.cost, me.id, 'Отмена шага боя', s.game_id, a.figure_id, a.squad_id);
  end if;
  delete from battle_actions where id = p_action;
  perform log_event(me.id, 'battle_undo', s.game_id, a.figure_id, a.squad_id, null, null, to_jsonb(a), null);
end $$;

-- Ведущий вручную ставит указатель хода.
create or replace function api_admin_turn_set(p_code text, p_game int, p_strategist int, p_tact int, p_phase text)
returns void
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); t turns := current_turn(p_game);
begin
  if t.id is null then raise exception 'Ходов ещё не было'; end if;
  if p_strategist is not null and not exists (select 1 from strategists where id = p_strategist and game_id = p_game) then
    raise exception 'Этот стратег не участвует в игре';
  end if;
  update turns set current_strategist = p_strategist, tact = coalesce(p_tact, tact),
    phase = coalesce(p_phase, phase) where id = t.id;
  perform log_event(me.id, 'turn_set', p_game, null, null, null, t.number,
    jsonb_build_object('strategist', p_strategist, 'tact', p_tact, 'phase', p_phase), null);
end $$;

-- починка: фигуры, которые стоят у стратега, где есть их владелец, — не «взятые»
update squad_figures sf set borrowed = false
where sf.borrowed and exists (select 1 from figure_owners o join strategist_members m on m.player_id = o.player_id
                              where o.figure_id = sf.figure_id and m.strategist_id = sf.strategist_id);

select 'ok' as миграция_005;
