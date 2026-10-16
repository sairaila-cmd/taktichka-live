-- 012 (16.10.2026): «Сэр Малеагант» → «Александр Смит» (основное имя персонажа).
--   · имя игрока и первое имя в characters (по нему подписи стратега и владельца);
--     «Сэр Малеагант» остаётся вторым именем — для поиска и сопоставления;
--   · строка «Владелец» у фигур.
-- Личный код не меняется (привязан к игроку, а не к имени). Повторный запуск ничего не портит.

update players
set name = 'Александр Смит',
    characters = array['Александр Смит', 'Сэр Малеагант']
       || array(select c from unnest(characters) c where c not in ('Александр Смит', 'Сэр Малеагант'))
where name = 'Сэр Малеагант';

update figures set owner_label = replace(owner_label, 'Сэр Малеагант', 'Александр Смит')
where owner_label like '%Сэр Малеагант%';

select (select count(*) from players where name = 'Александр Смит' and characters[1] = 'Александр Смит')
     + (select count(*) from players where name = 'Сэр Малеагант')
     + (select count(*) from figures where owner_label like '%Сэр Малеагант%') as миграция_12;
-- ожидается 1
