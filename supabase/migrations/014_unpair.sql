-- 014 (16.10.2026): ведущий разделяет напарников на подготовке игры.
--   · api_admin_unpair — пара снова становится двумя одиночными стратегами: отряд уходит тому,
--     чьих фигур в нём больше (поровну — остаётся у p_keep), фигуры только другого напарника
--     из него снимаются (трофеи остаются у отряда), общий кошелёк делится пополам (нечётный остаток — p_keep, у него же остаётся прежний стратег с инициативой).
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor.

create or replace function api_admin_unpair(p_code text, p_strategist int, p_keep int) returns int
language plpgsql security definer set search_path = public as $$
declare me players := auth_admin(p_code); st strategists; other int; share int; sb int;
  sq record; nk int; no int; removed int[]; gone int[] := '{}'; n_moved int := 0;
begin
  select * into st from strategists where id = p_strategist for update;
  if st.id is null then raise exception 'Стратег не найден'; end if;
  perform game_open_for_setup(st.game_id, false);
  if (select count(*) from strategist_members where strategist_id = p_strategist) <> 2 then
    raise exception 'Это не пара';
  end if;
  if not exists (select 1 from strategist_members where strategist_id = p_strategist and player_id = p_keep) then
    raise exception 'Игрок не из этой пары';
  end if;
  select player_id into other from strategist_members where strategist_id = p_strategist and player_id <> p_keep;
  share := coalesce(st.wallet, 0) / 2;
  update players set resources = resources + share where id = other;
  update players set resources = resources + coalesce(st.wallet, 0) - share where id = p_keep;
  update strategists set wallet = null, invited = null where id = p_strategist;
  delete from strategist_members where strategist_id = p_strategist and player_id = other;
  insert into strategists (game_id) values (st.game_id) returning id into sb;
  insert into strategist_members values (sb, st.game_id, other);
  for sq in select id from squads where strategist_id = p_strategist order by id loop
    select count(*) filter (where is_owner(p_keep, figure_id) and not is_owner(other, figure_id)),
           count(*) filter (where is_owner(other, figure_id) and not is_owner(p_keep, figure_id))
      into nk, no from squad_figures where squad_id = sq.id;
    if no > nk then
      update squads set strategist_id = sb where id = sq.id;
      update squad_figures set strategist_id = sb where squad_id = sq.id;
      update squad_moves set strategist_id = sb where squad_id = sq.id;
      with d as (delete from squad_figures where squad_id = sq.id
                   and is_owner(p_keep, figure_id) and not is_owner(other, figure_id) returning figure_id)
      select array_agg(figure_id) into removed from d;
      n_moved := n_moved + 1;
    else
      with d as (delete from squad_figures where squad_id = sq.id
                   and is_owner(other, figure_id) and not is_owner(p_keep, figure_id) returning figure_id)
      select array_agg(figure_id) into removed from d;
    end if;
    gone := gone || coalesce(removed, '{}');
  end loop;
  -- отряд не пустеет: у ушедшего остаются фигуры нового хозяина, у оставшегося — фигуры p_keep
  update squads s set destroyed = not exists (select 1 from squad_figures sf where sf.squad_id = s.id and sf.state = 'ok')
    where s.strategist_id in (p_strategist, sb);
  perform check_strategist_squads(p_strategist);
  perform check_strategist_squads(sb);
  if not is_test_game(st.game_id) then
    perform drop_source(f, (select title from games where id = st.game_id)) from unnest(gone) f
      where not exists (select 1 from squad_figures where game_id = st.game_id and figure_id = f);
  end if;
  perform log_event(me.id, 'unpair', st.game_id, null, null, other, coalesce(st.wallet, 0),
    jsonb_build_object('players', jsonb_build_array(p_keep, other), 'strategist', p_strategist, 'new', sb,
      'moved', n_moved), null);
  return sb;
end $$;

revoke execute on function api_admin_unpair(text, int, int) from public;
grant execute on function api_admin_unpair(text, int, int) to anon, authenticated;

select count(*) as миграция_14 from pg_proc where proname = 'api_admin_unpair';
