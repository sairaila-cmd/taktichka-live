-- 008 (15.10.2026): фигуры Винсента Фламбо из игры «Пять цветов одной Луны».
-- Повторный запуск ничего не дублирует (фигура с таким названием пропускается).

with v(name, nominal, s, l, v, prop) as (values
  ('KIROV', 'ладья', 6, 4, 4, 'Только ты и я'),
  ('Гончая-автоматон из кафедры да Винчи одиличесской анимации «bar-BOSS»', 'ладья', 7, 5, 1, 'Провокация'),
  ('Немертвый-оккультист', 'конь', 2, 3, 5, 'Шпионаж'),
  ('Группа восторженных студентов с Виктории', 'пешка', 3, 3, 3, 'Разведка'),
  ('Бродяги с Пятницкого Шоссе', 'пешка', 3, 3, 3, 'Плен'),
  ('Полиночка', 'пешка', 3, 3, 1, 'Добивание')
), ins as (
  insert into figures (name, nominal, s, l, v, properties, owner_label, sources)
  select name, nominal, s, l, v, array[prop], 'Винсент Фламбо', 'Пять цветов одной Луны' from v
  on conflict (name) do nothing
  returning id, name, nominal, s, l, v, properties
), own as (
  insert into figure_owners select ins.id, p.id from ins, players p where p.name = 'Винсент Фламбо'
  returning figure_id
)
insert into events (kind, figure_id, player_id, data, comment)
select 'figure_add', ins.id, (select id from players where name = 'Винсент Фламбо'),
  jsonb_build_object('nominal', nominal, 's', s, 'l', l, 'v', v, 'properties', properties, 'source', 'Пять цветов одной Луны'),
  'Добавлено ведущим (миграция 008)'
from ins;

select count(*) as миграция_8 from figures f join figure_owners o on o.figure_id = f.id
join players p on p.id = o.player_id
where p.name = 'Винсент Фламбо' and f.sources = 'Пять цветов одной Луны';
