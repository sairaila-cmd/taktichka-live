-- Индексы по порядку журнала и постраничное чтение без OFFSET.
drop index if exists events_game_id_idx;
create index if not exists events_at_id_idx on events (at desc, id desc);
create index if not exists events_game_at_id_idx on events (game_id, at desc, id desc);

create or replace function journal_page(p_before_at timestamptz, p_before_id bigint, p_limit int)
returns setof events
language plpgsql stable set search_path = public as $$
begin
  if (p_before_at is null) <> (p_before_id is null) then
    raise exception 'Курсор журнала должен содержать время и номер записи';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'Размер страницы журнала должен быть от 1 до 1000';
  end if;
  if p_before_at is null then
    return query
      select * from events order by at desc, id desc limit p_limit;
  else
    return query
      select * from events where (at, id) < (p_before_at, p_before_id)
      order by at desc, id desc limit p_limit;
  end if;
end $$;

revoke execute on function journal_page(timestamptz, bigint, int) from public, anon, authenticated;
grant execute on function journal_page(timestamptz, bigint, int) to anon, authenticated;

select 'ok' as migration_006;
