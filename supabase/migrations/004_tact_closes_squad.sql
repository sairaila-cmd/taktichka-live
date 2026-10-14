-- 004 (14.10.2026): Чёрная луна — отряд, которым стратег ходил в такте, в следующих тактах этого хода
-- больше не действует (незаконченный ход закрывается, когда такт уходит от стратега).
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor.

create or replace function advance_turn(p_turn int) returns void
language plpgsql security definer set search_path = public as $$
declare t turns; cur_pos int; nxt int;
begin
  select * into t from turns where id = p_turn for update;
  -- Чёрная луна: отряд, которым стратег ходил в этом такте, в следующих тактах хода больше не действует —
  -- незаконченный ход (например, только Перемещение) закрывается, когда такт уходит от стратега.
  if has_gift(t.game_id, 'chernaya') and t.current_strategist is not null then
    update squad_moves set act = 'Такт закончился', action = concat_ws(' → ', movement, 'Такт закончился')
      where turn_id = p_turn and strategist_id = t.current_strategist and act is null;
  end if;
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
  -- такт уходит дальше, когда ход отряда текущего стратега закончен
  if chern and done and t.current_strategist = s.strategist_id then perform advance_turn(t.id); end if;
end $$;

-- починка: незаконченные ходы из прошедших тактов текущих ходов при Чёрной луне — закрыть
update squad_moves m set act = 'Такт закончился', action = concat_ws(' → ', m.movement, 'Такт закончился')
from turns t
where m.turn_id = t.id and m.act is null and m.tact < t.tact and has_gift(t.game_id, 'chernaya');

select 'ok' as миграция_004;