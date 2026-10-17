-- 015 (17.10.2026): новые стратеги.
--   · Алехандро Дренте, Вестник — новые персонажи без фигур (личные коды — codes-015.sql, только у ведущего).
-- Повторный запуск ничего не дублирует.

insert into players (name, characters, is_admin) values
  ('Алехандро Дренте', array['Алехандро Дренте']::text[], false),
  ('Вестник', array['Вестник']::text[], false)
on conflict (name) do nothing;

select (select count(*) from players where name in ('Алехандро Дренте', 'Вестник')) as миграция_15;
