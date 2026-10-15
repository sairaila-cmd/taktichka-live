-- 007 (15.10.2026): игра в «Источниках» фигур, тестовые игры.
--   · Фигура попала в отряд игры → название игры дописывается в её «Источники» (и остаётся).
--     Переименование игры меняет название и в «Источниках».
--   · Тестовая игра — «тест» в названии: её название в «Источники» не пишется, а гибель в ней
--     не делает фигуру погибшей в общем списке (в самой игре погибшая видна по-прежнему).
--   · «Пользователь» в «Источниках» → «Пять цветов одной Луны».
-- Уже входит в schema.sql; для базы, созданной раньше, выполнить в SQL Editor.

-- Тестовая игра — «тест» в названии: гибель в ней не делает фигуру погибшей насовсем,
-- а название не попадает в «Источники» фигур.
create or replace function is_test_game(p_game int) returns boolean
language sql stable as $$
  select coalesce((select title ilike '%тест%' from games where id = p_game), false)
$$;

-- Дописать источник фигуре, если его ещё нет среди частей «a; b; c».
create or replace function add_source(p_figure int, p_title text) returns void
language sql security definer set search_path = public as $$
  update figures set sources = case when btrim(sources) = '' then btrim(p_title)
                                    else sources || '; ' || btrim(p_title) end
  where id = p_figure and coalesce(btrim(p_title), '') <> ''
    and not (btrim(p_title) = any (select btrim(x) from unnest(string_to_array(sources, ';')) x))
$$;

-- Фигура попала в отряд игры — название игры в её «Источники» (и остаётся там).
create or replace function squad_figures_add_game_source() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_test_game(new.game_id) then
    perform add_source(new.figure_id, (select title from games where id = new.game_id));
  end if;
  return new;
end $$;

drop trigger if exists squad_figures_game_source on squad_figures;
create trigger squad_figures_game_source after insert on squad_figures
  for each row execute function squad_figures_add_game_source();

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
      update figures f set sources = array_to_string(array(
          select btrim(x) from unnest(string_to_array(f.sources, ';')) with ordinality u(x, n)
          where btrim(x) <> btrim(old_title) and btrim(x) <> '' order by n), '; ')
        where f.id in (select figure_id from squad_figures where game_id = gid);
      if not is_test_game(gid) then
        perform add_source(sf.figure_id, p_title) from squad_figures sf where sf.game_id = gid;
      end if;
    end if;
  end if;
  perform log_event(me.id, 'game_' || coalesce(p_status,'draft'), gid, null, null, null, null,
    jsonb_build_object('title', p_title), null);
  return gid;
end $$;

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
  -- в тестовой игре гибель видна только в самой игре, в общем списке фигура жива
  if not is_test_game(s.game_id) then
    update figures set status = 'dead', died_game = s.game_id, died_how = how where id = f;
  end if;
  perform log_event(me.id, 'figure_death', s.game_id, f, p_squad, null, null,
    jsonb_build_object('how', how) || case when is_test_game(s.game_id) then '{"test": true}'::jsonb else '{}' end, null);
  return f;
end $$;

revoke execute on function is_test_game(int), add_source(int, text), squad_figures_add_game_source()
  from anon, authenticated, public;

-- данные: фигуры, погибшие в тестовых играх, снова живы
update figures set status = 'active', died_game = null, died_how = null
where status = 'dead' and is_test_game(died_game);

-- данные: переименованный источник
update figures set sources = replace(sources, 'Пользователь', 'Пять цветов одной Луны')
where sources like '%Пользователь%';

-- данные: игры, уже сыгранные (кроме тестовых), — в «Источники» фигур их отрядов
select add_source(sf.figure_id, g.title)
from squad_figures sf join games g on g.id = sf.game_id
where not is_test_game(g.id);

select (select count(*) from pg_trigger where tgname = 'squad_figures_game_source')
     + (select count(*) from figures where status = 'dead' and is_test_game(died_game)) as миграция_7;
