-- 003 (14.10.2026): свойство фазы Перемещения — не больше одного раза за ход на фигуру.
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor.

create or replace function api_property_use(p_code text, p_squad int, p_figure int, p_property text,
  p_cost int, p_battle int, p_params jsonb, p_comment text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me players := auth(p_code); s squads := require_strategist(me, p_squad);
  pr properties; cost int; r int; gain int := 0; fig figures; sf squad_figures; b battles;
  turn_no int;   -- номер текущего хода (null — ходы не начаты)
begin
  if (select status from games where id = s.game_id) <> 'running' then raise exception 'Игра не идёт'; end if;
  select number into turn_no from turns where game_id = s.game_id order by number desc limit 1;
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
  -- Свойство фазы Перемещения — не больше одного раза за ход на фигуру (любое из её свойств этой фазы).
  -- Пока ходы на сайте не начаты, ограничения нет.
  if p_battle is null and pr.phase = 'Перемещение' and turn_no is not null and exists (
       select 1 from events where kind = 'property_use' and game_id = s.game_id and figure_id = p_figure
         and not reverted and data->>'phase' = 'Перемещение' and (data->>'turn')::int = turn_no) then
    raise exception 'Фигура «%» уже применяла свойство в этом ходу', fig.name;
  end if;

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
    coalesce(p_params,'{}') || jsonb_build_object('property', p_property, 'roll', r, 'gain', gain, 'battle', p_battle,
      'phase', pr.phase, 'turn', turn_no),
    p_comment);
  return jsonb_build_object('cost', cost, 'roll', r, 'gain', gain);
end $$;

select 'ok' as миграция_003;
