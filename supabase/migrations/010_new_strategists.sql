-- 010 (16.10.2026): новые стратеги и второе имя персонажа.
--   · Стужа, Вилена, Фифи — новые персонажи без фигур (личные коды — codes-010.sql, только у ведущего);
--   · Сэр Малеагант = Александр Смит.
-- Повторный запуск ничего не дублирует.

insert into players (name, characters, is_admin) values
  ('Стужа', array['Стужа']::text[], false),
  ('Вилена', array['Вилена']::text[], false),
  ('Фифи', array['Фифи']::text[], false)
on conflict (name) do nothing;

update players set characters = characters || array['Александр Смит']
where name = 'Сэр Малеагант' and not ('Александр Смит' = any(characters));

select (select count(*) from players where name in ('Стужа', 'Вилена', 'Фифи'))
     + (select count(*) from players where name = 'Сэр Малеагант' and 'Александр Смит' = any(characters)) as миграция_10;
