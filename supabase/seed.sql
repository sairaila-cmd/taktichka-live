-- Начальные данные (создано tools/make_seed.py). Запускать после schema.sql.
begin;

insert into properties (name, phase, description, cost, cost_note) values
  ('Мобильность', 'Перемещение', '"+2" к дистанции Перемещения отряда.', 0, null),
  ('Воротила', 'Перемещение', 'Кинь кубик. Если выпал чёт, получи 1 ресурс.', 0, null),
  ('Штурм', 'Сила', 'Если отряд нападает, увеличь силу отряда на 5.', 0, null),
  ('Укрепление', 'Сила', 'Если отряд защищается, увеличь силу отряда на 5.', 0, null),
  ('Натиск', 'Сила', 'Потрать от 1 до 3 Ресурсов; увеличь силу отряда на 4 за каждый потраченный ресурс.', null, '1–3'),
  ('Шпионаж', 'Риск', 'Противник кидает 2 кубика; активировавший Шпионаж выбирает, какое значение использовать.', 0, null),
  ('Контрразведка', 'Сила', 'Потрать 1 Ресурс. Выбери одну фигуру в отряде противника. Увеличь силу своего отряда на Силу этой фигуры.', 1, null),
  ('Добивание', 'Ущерб', 'Потрать 1 Ресурс. Противник обязан убрать в отбой (из отряда) одну поврежденную фигуру в своем отряде. Если таких фигур более одной, выбирает хозяин отряда. Обратите внимание: эта фигура всё ещё не "умерла"; к окончательной смерти фигуры может привести только смерть всего отряда (см. фаза Ущерба).', 1, null),
  ('Подкуп', 'Ущерб', 'Потрать 1 Ресурс. Забери из отряда противника пешку или коня по своему выбору на место фигуры с подкупом. В этой игре дальше эта фигура сражается за вас, а подкупивший ушёл в резерв. После игры фигура возвращается владельцу.', 1, null),
  ('Переговоры', 'Риск', 'Потрать 1 Ресурс. Вне зависимости от значения на кубике бой закончился ничьей. Все фигуры в обоих отрядах не выполняют больше никаких действий в этой и последующих фазах боя.', 1, null),
  ('Плен', 'Условие', 'Потрать 1 Ресурс. Укажи фигуру в отряде противника, чей ранг не превышает ранг фигуры с пленом более чем на 1. В фазе Силы данная фигура не добавляет отряду свою силу. Т. е. пешка может убрать силу у пешки и коня, конь — у пешки, ферзь — у кого угодно.', 1, null),
  ('Множественность', 'Ущерб', 'Если фигура с Множественностью добита, кинь кубик. На чёт фигура выжила (остаётся в отряде). Если все фигуры в отряде повреждены, восстанови фигуру с Множественностью.', 0, null),
  ('Осведомленность', 'Сила', 'Если сила отряда с Осведомленностью меньше, чем у отряда противника, увеличь силу на 5.', 0, null),
  ('Разведка', 'Перемещение', 'Разведка и Расследование работают одинаково. Позволяет узнать примерное сюжетное содержание фишки, расположенной не дальше, чем Влияние отряда с этим свойством. Точная информация на усмотрение ведущего. Помогает понять, нужно ли вообще лезть в это событие. Стратег может задать два уточняющих вопроса.', 0, null),
  ('Расследование', 'Перемещение', 'Разведка и Расследование работают одинаково. Позволяет узнать примерное сюжетное содержание фишки, расположенной не дальше, чем Влияние отряда с этим свойством. Точная информация на усмотрение ведущего. Помогает понять, нужно ли вообще лезть в это событие. Стратег может задать два уточняющих вопроса.', 0, null),
  ('Лечение', 'Ущерб', 'Потрать 1 Ресурс. Восстанови любое количество поврежденных фигур в отряде с лечением.', 1, null),
  ('Оно пришло из-под земли', 'Перемещение', 'Возьми любой свой отряд, который находится на дистанции не более, чем Влияние отряда, использующего "Оно пришло из-под земли". Поставь его рядом с этим отрядом на любой соседний не занятый сектор.', 0, null),
  ('Замри!', 'Перемещение', 'Потрать 1 Ресурс. Передвинь отряд противника в пределах Влияния отряда с Замри! на 2 сектора или меньше.', 1, null),
  ('Закон и честь', 'Условие', 'В фазу Ущерба все фигуры противника не выполняют действий, которые убирают фигуры из вашего отряда. Помимо этого на отряд не работают свойства "Профессионал" и "Перспективы".', 0, null),
  ('Всем друг', 'Условие', 'В этой и последующих фазах все фигуры в отряде противника не выполняют действия, тратящие ресурсы.', 0, null),
  ('Дураки и дороги', 'Перемещение', 'Потрать 1 Ресурс. Передвинь отряд, в котором находится эта фигура, по прямой на число секторов не более его Влияния.', 1, null),
  ('Будьте здоровы', 'Перемещение', 'Потрать 1 Ресурс. Восстанови любую поврежденную фигуру в пределах радиуса Влияния отряда с этой фигурой.', 1, null),
  ('Профессионал', 'Перемещение', 'Потрать 1 Ресурс. Повреди любую фигуру противника, расположенную строго по прямой на дистанции, равной Влиянию отряда с Профессионалом. Отряд, использующий это свойство, не может использовать другие свойства своих фигур во время Перемещения или двигаться в этом ходу.', 1, null),
  ('Закон Талиона', 'Условие', 'Укажи фигуру в отряде противника. В этой и последующих фазах данная фигура не выполняет своих действий.', 0, null),
  ('Я — лист на ветру', 'Перемещение', 'Потрать 1 Ресурс. Передвинь любой свой отряд в пределах радиуса Влияния отряда с листом-на-ветру в любой свободный сектор в этом радиусе.', 1, null),
  ('Только ты и я', 'Риск', 'Если на твоём кубике выпало 8 или больше, твой отряд автопобедил в бою. Фигуры в отряде противника не выполняют свои действия в эту фазу.', 0, null),
  ('Quid pro quo', 'Ущерб', 'Поменяй поврежденную фигуру с Quid pro quo на любую неповрежденную фигуру из других твоих отрядов или Резерва по своему выбору, или же на случайную фигуру из Боевой Колоды.', 0, null),
  ('Приключения ждут!', 'Перемещение', 'Активирует фишку в пределах радиуса Влияния отряда, но в событие попадает не одна фигура, а две фигуры из вашего отряда (можно не использовать эту опцию). Отряд считается походившим.', 0, null),
  ('Провокация', 'Условие', 'Потрать 1 Ресурс. Если твой отряд атакующий, фигуры противника не добавляют Силе отряда свою базовую Силу и вынуждены сражаться только свойствами фигур.', 1, null),
  ('Шлагбаум', 'Перемещение', 'Выбери одну неповрежденную фигуру противника со свойствами Мобильность, Оно пришло из под земли, Дураки и дороги или Лист на ветру в пределах радиуса Влияния отряда со Шлагбаумом. Противник должен выплатить тебе 1 ресурс или повредить неоплаченную фигуру.', 0, null),
  ('Совершенная оборона', 'Условие', 'Если отряд с этой фигурой обороняется, то в этой и последующих фазах боя фигуры противника не выполняют своих действий.', 0, null),
  ('Фаталити', 'Ущерб', 'Заплати 2 Ресурса. Если отряд победил в бою, убери одну любую фигуру противника по своему выбору на свалку.', 2, null),
  ('Идеальный шаг', 'Перемещение', 'Заплати 1 Ресурс. Поменяй отряд, в котором находится идеальный шаг, с любым другим отрядом в пределах Влияния отряда с идеальным шагом.', 1, null),
  ('Один в поле воин', 'Сила', 'Утрой силу отряда с этой фигурой.', 0, null),
  ('Перспективы', 'Перемещение', 'Заплати 1 Ресурс за пешку, 2 за коня, 3 за офицера, 4 за ладью, 5 за ферзя, 6 за короля. Забери из отряда противника, находящегося в пределах Влияния отряда с перспективами, фигуру на место фигуры с перспективами. В этой игре дальше эта фигура сражается за вас, а подкупивший ушёл в резерв. После игры фигура возвращается владельцу (уничтожить её нельзя).', null, '1–6 по номиналу цели'),
  ('Регенерация', 'Перемещение', 'Убери в отбой фигуру с регенерацией; возьми вместо неё из отбоя любую другую свою фигуру неповрежденной.', 0, null),
  ('Перезагрузка', 'Перемещение', 'В фазу движения выбери любое свойство пешки или коня для этой фигуры на этот ход.', 0, null),
  ('Милая людоедка', 'Перемещение', 'Выбери отряд в радиусе, равном влиянию отряда с людоедкой. Повреди в нём одну фигуру с силой меньше 4 по своему выбору. Если успешно повредил — восстанови милую людоедку, если повреждена.', 0, null),
  ('Абсолютное превосходство', 'Риск', 'Если на твоём кубике выпало 5 или больше, твой отряд победил в бою. Фигуры в отряде противника не выполняют свои действия в эту фазу.', 0, null),
  ('Пожирание', 'Ущерб', 'Потрать 1 Ресурс. Противник обязан убрать в отбой (из отряда) одну поврежденную фигуру в своем отряде. Если таких фигур более одной, выбирает хозяин отряда. Обратите внимание: эта фигура всё ещё не "умерла"; к окончательной смерти фигуры может привести только смерть всего отряда (см. фаза Ущерба). В случае если фигура противника успешно ушла в отбой, восстанови любое количество поврежденных фигур в отряде с Пожиранием.', 1, null),
  ('Мудрец', 'Перемещение', 'Активирует фишку в пределах радиуса Влияния отряда. Отряд считается походившим. Также эта фигура не может погибнуть или быть повреждена при прохождении события, как бы ни сложилась ситуация.', 0, null),
  ('Мат', 'Сила', 'Добавь своему отряду силу, равную сумме силы фигур в отряде противника.', 0, null),
  ('СуперПодкуп', 'Ущерб', 'Потрать 1 Ресурс. Забери из отряда противника фигуру номиналом ладья или ниже по своему выбору на место фигуры с подкупом. В этой игре дальше эта фигура сражается за вас, а подкупивший ушёл в резерв. После игры фигура возвращается владельцу.', 1, null);

insert into players (name, characters, is_admin) values
  ('Ведущий', '{}'::text[], true),
  ('Аврора', array['Аврора']::text[], false),
  ('Андромеда', array['Андромеда']::text[], false),
  ('Беличий Хвост', array['Беличий Хвост']::text[], false),
  ('Винсент Фламбо', array['Винсент Фламбо', 'Винсент']::text[], false),
  ('Всем друг', array['Всем друг']::text[], false),
  ('Дед Егор', array['Дед Егор']::text[], false),
  ('Зои', array['Зои', 'Зои Вебер', 'Зои Элкси']::text[], false),
  ('Ирэн Голицына', array['Ирэн Голицына', 'Ирен']::text[], false),
  ('Лале', array['Лале']::text[], false),
  ('Любомир', array['Любомир']::text[], false),
  ('Майорский', array['Майорский']::text[], false),
  ('Мэт', array['Мэт']::text[], false),
  ('Нимур', array['Нимур', 'Бьянка Дегоя']::text[], false),
  ('Парадокс', array['Парадокс']::text[], false),
  ('Принцесса Сотис', array['Принцесса Сотис', 'Сотис']::text[], false),
  ('Пятая', array['Пятая', 'Пятая Эгле', 'Черрел']::text[], false),
  ('Ратбургер', array['Ратбургер']::text[], false),
  ('Ржавый', array['Ржавый']::text[], false),
  ('Самум', array['Самум']::text[], false),
  ('Смысловский', array['Смысловский']::text[], false),
  ('Сэр Малеагант', array['Сэр Малеагант']::text[], false),
  ('Тара', array['Тара']::text[], false),
  ('Телеграфист', array['Телеграфист']::text[], false),
  ('Четвёртый', array['Четвёртый', 'Четвертый']::text[], false),
  ('Элли', array['Элли']::text[], false);

insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Амбициозная провинциалка', 'пешка', 3, 3, 2, array['Натиск']::text[], 'Ирэн Голицына и Майорский; Парадокс и Ирэн Голицына', 'Золотое кольцо; Мы пламя');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Майорский', 'Парадокс');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Бездомный воитель', 'пешка', 3, 4, 0, array['Множественность']::text[], 'Ирэн Голицына', 'Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Бледный детектив', 'пешка', 1, 5, 4, array['Расследование']::text[], 'Зои и Четвёртый', 'Шрам; Метро; 182/8; Золотое кольцо; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Вася первоотрядный', 'пешка', 2, 4, 4, array['Воротила']::text[], 'Тара и Мэт; Сэр Малеагант', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Мэт', 'Сэр Малеагант', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Верные ученики деда', 'пешка', 3, 3, 3, array['Воротила']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Веселый скелет Романа', 'пешка', 2, 4, 3, array['Переговоры']::text[], 'Ржавый и Пятая', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Всегда Двое', 'пешка', 5, 5, 0, array['Множественность']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Глаза Тени', 'пешка', 3, 3, 1, array['Расследование']::text[], 'Ратбургер и Зои; Ратбургер', 'Андеграунд; Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гуль-воробей (Воробей)', 'пешка', 1, 4, 1, array['Мобильность']::text[], 'Ратбургер', 'Storm Heist; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Дворник Крокодилового храма (Крокохрама)', 'пешка', 3, 5, 3, array['Разведка']::text[], 'Ратбургер и Беличий Хвост; Ратбургер; Ратбургер и Телеграфист; Ратбургер и Зои; Смысловский', 'Шрам; Метро; Золотое кольцо; Андеграунд; Монстры; Storm Heist; До тла; Снова горит; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Зои', 'Ратбургер', 'Смысловский', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Дети под присмотром денарийца', 'пешка', 3, 3, 3, array['Мобильность']::text[], 'Принцесса Сотис', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Дин Эмброус', 'пешка', 3, 4, 1, array['Штурм']::text[], 'Ржавый и Пятая', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Желтое & свежее', 'пешка', 2, 4, 2, array['Расследование']::text[], 'Ирэн Голицына; Ирэн Голицына и Майорский; Парадокс и Ирэн Голицына', 'Метро; Золотое кольцо; Storm Heist; Мы пламя');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Майорский', 'Парадокс');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Женщина рабари', 'пешка', 3, 3, 3, array['Осведомленность']::text[], 'Зои', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Зоркие ученики деда', 'пешка', 3, 3, 3, array['Разведка']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Иволга Человечьего Жилья', 'пешка', 3, 3, 3, array['Шпионаж']::text[], 'Ирэн Голицына и Майорский', 'Золотое кольцо');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Майорский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Капрал ЧереЧпок', 'пешка', 2, 2, 2, array['Плен']::text[], 'Ратбургер и Зои; Ратбургер', 'Андеграунд; Storm Heist; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Катя Орлова?', 'пешка', 1, 3, 4, array['Разведка']::text[], 'Сэр Малеагант', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Квинкана Машенька', 'пешка', 3, 3, 0, array['Плен', 'Добивание']::text[], 'Ратбургер', 'Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Коллега госплжи Венеры', 'пешка', 2, 4, 2, array['Плен']::text[], 'Всем друг и Андромеда', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Всем друг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Лола', 'пешка', 3, 3, 2, array['Приключения ждут!']::text[], 'Винсент Фламбо и Андромеда', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Люцифер', 'пешка', 2, 4, 4, array['Воротила']::text[], 'Ирэн Голицына', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мертвая девушка в веригах', 'пешка', 3, 3, 2, array['Мобильность']::text[], 'Нимур; Зои', 'Метро; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мертвые добытчики', 'пешка', 2, 3, 2, array['Плен']::text[], 'Зои', 'Метро; 182/8; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мертвый коммивояжер', 'пешка', 3, 3, 3, array['Воротила']::text[], 'Зои и Четвёртый; Ржавый и Пятая; Ратбургер и Зои', 'Шрам; 182/8; Андеграунд; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Пятая', 'Ратбургер', 'Ржавый', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Наемник А, верный Лиле Черной и вовсе не ОД-шник', 'пешка', 4, 3, 3, array['Штурм']::text[], 'Ржавый и Пятая', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Немертвый дварф', 'пешка', 2, 3, 0, array['Воротила']::text[], 'Ратбургер и Беличий Хвост', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Непреметный черный фургон', 'пешка', 2, 4, 5, array['Осведомленность']::text[], 'Самум', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Самум');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Обречённая на гибель Звёздная ворона', 'пешка', 0, 5, 1, array['Мобильность']::text[], 'Принцесса Сотис', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Огромный питон Каа', 'пешка', 3, 4, 0, array['Штурм']::text[], 'Ратбургер', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Одержимая бесами', 'пешка', 3, 3, 1, array['Множественность']::text[], 'Всем друг и Андромеда', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Всем друг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Орда Зомби', 'пешка', 3, 3, 0, array['Множественность']::text[], 'Нимур', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Осьминог(иня) Крокохрама', 'пешка', 4, 2, 5, array['Воротила']::text[], 'Ратбургер и Беличий Хвост; Ратбургер', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Последняя Тень', 'пешка', 2, 3, 2, array['Расследование']::text[], 'Ратбургер и Беличий Хвост; Ратбургер', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Призрак из АНБУ', 'пешка', 3, 3, 4, array['Контрразведка']::text[], 'Сэр Малеагант', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Профессор Черрел', 'пешка', 2, 3, 3, array['Воротила']::text[], 'Ржавый и Пятая', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пятая (Агент Пятая)', 'пешка', 3, 3, 3, array['Мобильность']::text[], 'Пятая; Пятая', 'Метро; Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Расторопные и ушлые аколиты', 'пешка', 3, 3, 3, array['Воротила']::text[], 'Нимур', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Родич Сидор', 'пешка', 3, 4, 3, array['Разведка']::text[], 'Пятая и Любомир', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Рязанский Драгдиллер', 'пешка', 1, 2, 3, array['Мобильность']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Санни', 'пешка', 3, 3, 0, array['Добивание']::text[], 'Зои и Четвёртый', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сашенька Воронцова', 'пешка', 1, 4, 4, array['Воротила']::text[], 'Нимур и Лале', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Лале', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Снежана', 'пешка', 3, 4, 4, array['Подкуп']::text[], 'Ирэн Голицына', 'Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Созвездие Голубя', 'пешка', 2, 3, 3, array['Переговоры']::text[], 'Принцесса Сотис', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Созвездие Райской Птицы', 'пешка', 3, 3, 3, array['Расследование']::text[], 'Принцесса Сотис', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сомик-малыш ver. 2', 'пешка', 3, 3, 3, array['Добивание']::text[], 'Элли', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сомик-мусороед', 'пешка', 2, 2, 2, array['Добивание']::text[], 'Элли и Принцесса Сотис', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сотис', 'пешка', 4, 3, 3, array['Разведка']::text[], 'Элли и Принцесса Сотис; Принцесса Сотис', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Стая призванных крыс', 'пешка', 3, 3, 3, array['Множественность']::text[], 'Элли и Принцесса Сотис', 'Шрам; Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сын пингвина Джека', 'пешка', 2, 3, 0, array['Контрразведка']::text[], 'Ратбургер и Телеграфист; Ратбургер и Зои; Ратбургер', 'Золотое кольцо; Андеграунд; Storm Heist; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Тётя Валя', 'пешка', 1, 4, 2, array['Контрразведка']::text[], 'Ратбургер и Телеграфист; Ратбургер и Зои; Ратбургер', 'Золотое кольцо; Андеграунд; Storm Heist; Снова горит; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Толпа расторопных автоматонов', 'пешка', 3, 3, 3, array['Мобильность']::text[], 'Принцесса Сотис', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Торговец краденым', 'пешка', 3, 1, 0, array['Воротила']::text[], 'Ратбургер и Телеграфист', 'Золотое кольцо');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Тюльпа-викинг', 'пешка', 4, 4, 0, array['Штурм']::text[], 'Пятая', 'Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Устричная Малышка', 'пешка', 3, 3, 2, array['Мобильность']::text[], 'Ратбургер и Беличий Хвост; Ратбургер', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Четвёртый Наследник', 'пешка', 3, 4, 2, array['Мобильность']::text[], 'Четвёртый', 'Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('ЧОП Гриша', 'пешка', 3, 1, 0, array['Плен']::text[], 'Ратбургер и Телеграфист', 'Золотое кольцо');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Шепот', 'пешка', 3, 3, 3, array['Расследование']::text[], 'Самум', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Самум');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Stallion A-16-52', 'конь', 3, 3, 4, array['Замри!']::text[], 'Тара и Мэт', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Мэт', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Агулшап-бабник из Крокохрама', 'конь', 4, 4, 4, array['Плен']::text[], 'Ратбургер и Беличий Хвост', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Аладар', 'конь', 4, 2, 4, array['Расследование']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Бухгалтер Орловых', 'конь', 2, 3, 4, array['Воротила']::text[], 'Смысловский', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Смысловский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Верный бармен Фантин', 'конь', 2, 5, 2, array['Замри!']::text[], 'Ирэн Голицына', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Взвод ОМОНа', 'конь', 5, 4, 3, array['Штурм']::text[], 'Ирэн Голицына и Майорский; Ирэн Голицына; Парадокс и Ирэн Голицына', 'Золотое кольцо; Storm Heist; Мы пламя');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Майорский', 'Парадокс');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Винсент Ван Гог, лично?', 'конь', 4, 3, 4, array['Добивание']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Дворник-таджик', 'конь', 4, 3, 1, array['Мобильность']::text[], 'Ирэн Голицына и Майорский; Ирэн Голицына', 'Золотое кольцо; Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Майорский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Жеребенок Белогривой', 'конь', 8, 6, 1, array['Мобильность']::text[], 'Зои и Четвёртый', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Звездный какаду', 'конь', 4, 4, 2, array['Замри!']::text[], 'Принцесса Сотис', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Зомби-МЧС', 'конь', 4, 5, 4, array['Лечение']::text[], 'Зои', 'Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Клоп из первого отряда', 'конь', 4, 3, 3, array['Переговоры']::text[], 'Винсент Фламбо и Тара', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Конь-огонь', 'конь', 3, 4, 4, array['Оно пришло из-под земли']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Кубикирэ-ума', 'конь', 5, 6, 0, array['Оно пришло из-под земли']::text[], 'Сэр Малеагант', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Кысь-брысь', 'конь', 4, 4, 2, array['Укрепление']::text[], 'Элли', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ледяной зуб', 'конь', 9, 3, 3, array['Плен']::text[], 'Ратбургер и Беличий Хвост; Ратбургер; Ратбургер и Телеграфист; Ратбургер и Зои', 'Шрам; Метро; Золотое кольцо; Андеграунд; Монстры; Storm Heist; До тла; Снова горит; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мертвая лошадка Матуби Джанго', 'конь', 4, 3, 3, array['Замри!']::text[], 'Зои', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мертвая незуми', 'конь', 5, 4, 0, array['Мобильность']::text[], 'Зои', '182/8; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Механический сенбернар', 'конь', 4, 4, 4, array['Плен']::text[], 'Ржавый и Пятая', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Милый поняш', 'конь', 5, 5, 5, array['Оно пришло из-под земли']::text[], 'Ратбургер', 'Снова горит');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Молодая фурия Дарья Бирон', 'конь', 4, 5, 1, array['Добивание']::text[], 'Нимур и Лале', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Лале', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мори Асахи', 'конь', 2, 4, 5, array['Воротила']::text[], 'Винсент Фламбо и Андромеда', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Морячок', 'конь', 4, 3, 4, array['Оно пришло из-под земли']::text[], 'Нимур', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Нафаня Правый', 'конь', 9, 9, 9, array['Мобильность']::text[], 'Ратбургер', 'До тла');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Немертвый Гонец', 'конь', 5, 4, 4, array['Оно пришло из-под земли']::text[], 'Нимур и Лале', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Лале', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Непередаваемый бегун', 'конь', 1, 4, 5, array['Мобильность']::text[], 'Зои', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Непередаваемый надзиратель', 'конь', 2, 3, 4, array['Осведомленность']::text[], 'Смысловский', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Смысловский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Норовистый (черноглазый и златогривый) жеребец', 'конь', 5, 4, 4, array['Замри!']::text[], 'Сэр Малеагант', 'Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ночной гастролёр', 'конь', 5, 3, 1, array['Разведка']::text[], 'Ратбургер и Телеграфист', 'Золотое кольцо');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Понаехал', 'конь', 4, 4, 4, array['Мобильность', 'Воротила']::text[], 'Ирэн Голицына', 'Метро; Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пустышка "Квазимодо"', 'конь', 5, 3, 1, array['Плен']::text[], 'Зои', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Рыцарь Черен Гвидион', 'конь', 4, 3, 6, array['Плен']::text[], 'Ратбургер и Беличий Хвост; Ратбургер', 'Шрам; Метро; Снова горит');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Самум Саббат', 'конь', 3, 5, 5, array['Мобильность']::text[], 'Пятая', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сержант крокохрама', 'конь', 5, 3, 2, array['Осведомленность']::text[], 'Ратбургер', 'Монстры; Storm Heist; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Созвездие Козерога', 'конь', 3, 2, 3, array['Лечение']::text[], 'Принцесса Сотис', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Стриптизерша Аурика', 'конь', 2, 4, 4, array['Замри!']::text[], 'Зои и Четвёртый', 'Шрам; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Студенты-сторонники Консенсуса', 'конь', 3, 3, 6, array['Контрразведка']::text[], 'Пятая; Пятая', 'Метро; Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Тень-Милашка', 'конь', 4, 3, 4, array['Оно пришло из-под земли']::text[], 'Элли', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Цитотаксис (отряд Зои Элкси)', 'конь', 3, 3, 0, array['Множественность']::text[], 'Зои', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Юная элаим', 'конь', 1, 4, 4, array['Мобильность']::text[], 'Самум', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Самум');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Assault Unit C-1-56-O', 'офицер', 6, 4, 1, array['Закон Талиона']::text[], 'Ратбургер и Беличий Хвост', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Адский мытарь', 'офицер', 5, 4, 6, array['Закон и честь']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Альберт Переговорщик', 'офицер', 2, 2, 6, array['СуперПодкуп']::text[], 'Зои и Четвёртый', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Астер', 'офицер', 3, 4, 3, array['Будьте здоровы']::text[], 'Винсент Фламбо и Андромеда', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Бледный извозчик', 'офицер', 5, 4, 0, array['Дураки и дороги']::text[], 'Смысловский', 'Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Смысловский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Борзая-гончая', 'офицер', 5, 6, 2, array['Мобильность']::text[], 'Ратбургер', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('"Дальнобой"', 'офицер', 5, 5, 5, array['Дураки и дороги']::text[], 'Зои', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Зомби Командующий', 'офицер', 5, 2, 3, array['Плен']::text[], 'Сэр Малеагант', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Зомби-Эксбиционист', 'офицер', 1, 4, 5, array['Оно пришло из-под земли']::text[], 'Ратбургер и Беличий Хвост; Ратбургер', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Изможденный пси-целитель', 'офицер', 3, 4, 5, array['Будьте здоровы']::text[], 'Зои', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Капитан первого ранга Наливай-да-Пей', 'офицер', 6, 5, 5, array['Регенерация']::text[], 'Ратбургер', 'Монстры; Storm Heist; До тла');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Кибер-шлюха на высоких шпильках', 'офицер', 4, 4, 4, array['Закон Талиона']::text[], 'Зои', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Корабль-призрак', 'офицер', 1, 4, 5, array['Дураки и дороги']::text[], 'Самум', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Самум');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Крокодил Ряженка', 'офицер', 6, 7, 3, array['Мобильность']::text[], 'Ратбургер и Беличий Хвост; Ратбургер; Ратбургер и Телеграфист; Ратбургер и Зои', 'Шрам; Метро; Золотое кольцо; Андеграунд; Storm Heist; До тла; Снова горит; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Лев из тёмных вод', 'офицер', 3, 5, 6, array['Мобильность']::text[], 'Ратбургер и Беличий Хвост', 'Шрам; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Лечерито из Лос Паяцос', 'офицер', 5, 4, 5, array['Закон Талиона']::text[], 'Ирэн Голицына', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Малый Танатос Ур Бат', 'офицер', 9, 7, 4, array['Добивание']::text[], 'Зои и Четвёртый; Нимур', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Нимур', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Марионетка заводной змей', 'офицер', 1, 4, 6, array['Профессионал']::text[], 'Ратбургер и Телеграфист; Ратбургер', 'Золотое кольцо; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мертвая стая Вирмоборцев', 'офицер', 7, 4, 1, array['Профессионал']::text[], 'Ратбургер и Зои; Зои', 'Андеграунд; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Милослав (Мирослав)', 'офицер', 5, 5, 5, array['Плен']::text[], 'Пятая; Парадокс и Ирэн Голицына', 'Метро; Мы пламя');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Парадокс', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мутировавший зомби', 'офицер', 5, 4, 0, array['Множественность']::text[], 'Четвёртый', 'Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Одинадцатый Брат', 'офицер', 3, 3, 6, array['Будьте здоровы']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Офицер эскадры Тысячи Парусов', 'офицер', 8, 5, 0, array['Мобильность']::text[], 'Винсент Фламбо и Андромеда', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Очень быстрый зомби', 'офицер', 5, 4, 0, array['Мобильность']::text[], 'Нимур и Лале', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Лале', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Прянчесса', 'офицер', 5, 3, 0, array['Мобильность']::text[], 'Элли и Принцесса Сотис', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Птица', 'офицер', 4, 4, 5, array['Дураки и дороги']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Расторопный зомби-адъютант', 'офицер', 5, 4, 2, array['Мобильность']::text[], 'Элли', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Расторопный часовщик', 'офицер', 3, 4, 4, array['Мобильность']::text[], 'Всем друг и Андромеда', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Всем друг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ртуть', 'офицер', 3, 3, 6, array['Дураки и дороги']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Рыжий', 'офицер', 5, 5, 4, array['Всем друг']::text[], 'Зои', 'Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сладкоголосая Лан', 'офицер', 5, 5, 5, array['Плен', 'Дураки и дороги']::text[], 'Тара и Мэт; Винсент Фламбо и Тара', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо', 'Мэт', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сорока-Ворона', 'офицер', 4, 4, 5, array['Всем друг']::text[], 'Ржавый и Пятая', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ст. научный сотрудник Крюков', 'офицер', 3, 3, 6, array['Будьте здоровы']::text[], 'Винсент Фламбо и Тара', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Толстый Хомяк', 'офицер', 3, 6, 6, array['Всем друг']::text[], 'Пятая и Любомир; Пятая', 'Шрам; Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Цесаревич Петр', 'офицер', 1, 5, 7, array['Переговоры']::text[], 'Всем друг и Андромеда', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Всем друг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Частный извозчик', 'офицер', 5, 8, 5, array['Я — лист на ветру']::text[], 'Элли и Принцесса Сотис', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Hitman', 'ладья', 7, 5, 2, array['Добивание']::text[], 'Парадокс и Ирэн Голицына', 'Мы пламя');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына', 'Парадокс');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Археологический арт-проект "Арабика"', 'ладья', 4, 6, 4, array['Приключения ждут!']::text[], 'Зои и Четвёртый; Самум; Зои', 'Шрам; Метро; 182/8; Золотое кольцо; Андеграунд; Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Самум', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Бастующие дальнобойщики', 'ладья', 6, 4, 4, array['Шлагбаум', 'Я — лист на ветру']::text[], 'Самум; Ржавый и Пятая', 'Метро; 182/8; Золотое кольцо; Андеграунд; Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая', 'Ржавый', 'Самум');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Васек', 'ладья', 6, 5, 7, array['Всем друг']::text[], 'Ирэн Голицына', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ирэн Голицына');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Вождь', 'ладья', 9, 5, 1, array['Только ты и я']::text[], 'Нимур и Лале', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Лале', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Вуджанки Ржавой Дороги', 'ладья', 11, 5, 1, array['Я — лист на ветру']::text[], 'Ратбургер и Беличий Хвост; Ратбургер', 'Шрам; Метро; Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('ГАРМ', 'ладья', 4, 7, 2, array['Я — лист на ветру']::text[], 'Сэр Малеагант', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гнус', 'ладья', 11, 4, 2, array['Плен']::text[], 'Ратбургер; Ратбургер и Телеграфист; Ратбургер и Зои', 'Метро; Золотое кольцо; Андеграунд; Монстры; Storm Heist; До тла; Снова горит; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гомункулус Можжевельник', 'ладья', 7, 7, 1, array['Только ты и я', 'Я — лист на ветру']::text[], 'Тара и Мэт; Винсент Фламбо и Тара', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо', 'Мэт', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гули из котерии "трое сбоку"', 'ладья', 9, 5, 2, array['Только ты и я']::text[], 'Ратбургер и Беличий Хвост; Ратбургер и Телеграфист; Ратбургер и Зои; Ратбургер', 'Шрам; Золотое кольцо; Андеграунд; Storm Heist; До тла; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гуль Гомеш', 'ладья', 6, 4, 1, array['Мобильность']::text[], 'Смысловский; Ратбургер', 'Монстры; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер', 'Смысловский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Зверь', 'ладья', 6, 6, 6, array['Только ты и я']::text[], 'Принцесса Сотис', 'Метро; Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Зомби-Часовой', 'ладья', 18, 10, 6, array['Контрразведка']::text[], 'Ратбургер и Зои', 'Андеграунд');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Каменный Щит', 'ладья', 10, 10, 8, array['Совершенная оборона']::text[], 'Ратбургер', 'Снова горит');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Крысоогр', 'ладья', 7, 3, 2, array['Только ты и я']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Лекса', 'ладья', 5, 5, 7, array['Перезагрузка']::text[], 'Пятая', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ликид', 'ладья', 6, 4, 1, array['Провокация']::text[], 'Смысловский', 'Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Смысловский');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Любвеобильная самка-гнолл Вонючая Ляжка', 'ладья', 9, 5, 1, array['Только ты и я']::text[], 'Ратбургер и Беличий Хвост', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Меркурий', 'ладья', 7, 4, 1, array['Совершенная оборона']::text[], 'Винсент Фламбо и Андромеда', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мирида', 'ладья', 6, 8, 1, array['Приключения ждут!']::text[], 'Элли и Принцесса Сотис', 'Шрам; Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мудрый ворон', 'ладья', 3, 5, 6, array['Приключения ждут!']::text[], 'Дед Егор и Аврора', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Аврора', 'Дед Егор');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Очень таинственный друг', 'ладья', 6, 3, 3, array['Совершенная оборона']::text[], 'Винсент Фламбо и Андромеда; Всем друг и Андромеда', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Винсент Фламбо', 'Всем друг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Поветрие', 'ладья', 6, 4, 4, array['Приключения ждут!']::text[], 'Пятая и Любомир', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Любомир', 'Пятая');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Подозрительный боинг (Boeing C-17)', 'ладья', 4, 3, 6, array['Я — лист на ветру']::text[], 'Тара и Мэт', 'Шрам; Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Мэт', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Рыжий снайпер', 'ладья', 8, 5, 6, array['Всем друг']::text[], 'Зои', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Синьор Джузеппе', 'ладья', 7, 5, 1, array['Только ты и я']::text[], 'Элли и Принцесса Сотис; Смысловский', 'Шрам; Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис', 'Смысловский', 'Элли');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Тварь Бьянки', 'ладья', 7, 4, 1, array['Провокация']::text[], 'Нимур и Лале; Нимур', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Лале', 'Нимур');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Транспортная компания "Селерити-логистикс"', 'ладья', 7, 4, 4, array['Я — лист на ветру']::text[], 'Ратбургер и Беличий Хвост; Зои; Ратбургер', 'Шрам; Метро; Монстры; Storm Heist; Снова горит');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Труповозка', 'ладья', 6, 6, 6, array['Я — лист на ветру']::text[], 'Зои и Четвёртый; Зои', 'Шрам; Метро; 182/8; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Черный цитотаксис', 'ладья', 8, 4, 8, array['Провокация']::text[], 'Сэр Малеагант', 'Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Сэр Малеагант');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Шестой', 'ладья', 7, 7, 3, array['Оно пришло из-под земли']::text[], 'Принцесса Сотис', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Принцесса Сотис');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Щенок варгуля', 'ладья', 8, 4, 1, array['Только ты и я']::text[], 'Четвёртый', 'Андеграунд; Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Четвёртый');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('[Заяц Олег] ладья (совершенная оборона)', 'ладья', 7, 4, 1, array['Совершенная оборона']::text[], 'Зои', 'Storm Heist');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('[Мал Клоп да Вонюч] ладья (шлагбаум)', 'ладья', 5, 5, 6, array['Шлагбаум']::text[], 'Ратбургер и Зои', 'Андеграунд');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('[Слёзы маленьких крокодильчиков] ладья (только ты и я)', 'ладья', 7, 5, 2, array['Только ты и я']::text[], 'Ратбургер и Зои', 'Андеграунд');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Буньип Крокодилового Храма', 'ферзь', 9, 8, 2, array['Один в поле воин']::text[], 'Ратбургер и Беличий Хвост; Ратбургер; Ратбургер и Телеграфист; Ратбургер и Зои', 'Шрам; Метро; Золотое кольцо; Андеграунд; Монстры; Storm Heist; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Беличий Хвост', 'Зои', 'Ратбургер', 'Телеграфист');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гадюка-рысь (ГодюкаРыся)', 'ферзь', 11, 8, 0, array['Фаталити']::text[], 'Ратбургер и Беличий Хвост; Всем друг и Андромеда', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Андромеда', 'Беличий Хвост', 'Всем друг', 'Ратбургер');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Голем из проволоки', 'ферзь', 8, 5, 2, array['Регенерация']::text[], 'Зои', 'Шрам; Монстры');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Камилл', 'ферзь', 10, 6, 1, array['Один в поле воин']::text[], 'Зои', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Нефритовая Башня', 'ферзь', 9, 4, 0, array['Совершенная оборона']::text[], 'Тара и Мэт', 'Шрам; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Мэт', 'Тара');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Чучело Твари', 'ферзь', 6, 6, 8, array['Перспективы']::text[], 'Смысловский; Зои; Ратбургер', 'Монстры; Storm Heist; До тла');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Зои', 'Ратбургер', 'Смысловский');

insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('KIROV', 'ладья', 6, 4, 4, array['Только ты и я']::text[], 'Винсент Фламбо', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гончая-автоматон из кафедры да Винчи одиличесской анимации «bar-BOSS»', 'ладья', 7, 5, 1, array['Провокация']::text[], 'Винсент Фламбо', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Немертвый-оккультист', 'конь', 2, 3, 5, array['Шпионаж']::text[], 'Винсент Фламбо', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Группа восторженных студентов с Виктории', 'пешка', 3, 3, 3, array['Разведка']::text[], 'Винсент Фламбо', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Бродяги с Пятницкого Шоссе', 'пешка', 3, 3, 3, array['Плен']::text[], 'Винсент Фламбо', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Полиночка', 'пешка', 3, 3, 1, array['Добивание']::text[], 'Винсент Фламбо', 'Пять цветов одной Луны');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Винсент Фламбо');
-- миграция 009: фигуры возвращённых владельцев
insert into players (name, characters, is_admin) values
  ('Регент Гильгамеш', array['Регент Гильгамеш']::text[], false),
  ('Маяк', array['Маяк']::text[], false),
  ('Эрик', array['Эрик']::text[], false),
  ('Королевна Эгле', array['Королевна Эгле', 'Эгле']::text[], false),
  ('Неро', array['Неро', 'Роланд']::text[], false),
  ('СМС', array['СМС', 'Гнойный']::text[], false),
  ('Анна Смит', array['Анна Смит']::text[], false),
  ('Царевна-Лягушка', array['Царевна-Лягушка']::text[], false),
  ('Анна Фэнг', array['Анна Фэнг']::text[], false)
on conflict (name) do nothing;
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Captivity script', 'пешка', 3, 3, 0, array['Плен']::text[], 'Неро и Дикси', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Illusory script', 'пешка', 0, 4, 5, array['Контрразведка']::text[], 'Неро и Дикси', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Веселый скелет Сиерры', 'пешка', 3, 3, 0, array['Штурм']::text[], 'Неро', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Влада', 'пешка', 4, 4, 1, array['Добивание']::text[], 'Влада и Эрик', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Эрик');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Воин Пути', 'пешка', 3, 3, 3, array['Штурм']::text[], 'Влада и Эрик', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Эрик');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Гектарина', 'пешка', 3, 2, 1, array['Расследование']::text[], 'Анна Фэнг', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Фэнг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Джем Курадоберри', 'пешка', 4, 4, 2, array['Мобильность']::text[], 'Дюран маркиз дю Бек-Креспен и СМС', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('ДРУГАЯ толпа туповатых влюбленных девиц при бабле', 'пешка', 3, 4, 5, array['Воротила']::text[], 'Маяк', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Маяк');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Жабогадюка Васька', 'пешка', 3, 3, 3, array['Множественность']::text[], 'СМС и Царевна-Лягушка', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС', 'Царевна-Лягушка');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('"Желтое Уёбище" или славный воин Эгле', 'пешка', 5, 6, 0, array['Штурм']::text[], 'Королевна Эгле', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Игрок в "Кальмара"', 'пешка', 3, 3, 3, array['Множественность']::text[], 'Влада и Эрик', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Эрик');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Корабли Airhaven', 'пешка', 4, 3, 3, array['Мобильность']::text[], 'Анна Фэнг', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Фэнг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Кто-то смотрит через камеры', 'пешка', 0, 4, 4, array['Расследование']::text[], 'Неро и Дикси', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Лешенька', 'пешка', 3, 3, 3, array['Добивание']::text[], 'Влада и Эрик', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Эрик');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Первый в истории волк Ро', 'пешка', 4, 4, 4, array['Оно пришло из-под земли']::text[], 'Людвиг Красивый и Королевна Эгле', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пехотинец по найму', 'пешка', 4, 0, 0, array['Мобильность']::text[], 'Королевна Эгле', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пустельга', 'пешка', 3, 3, 0, array['Мобильность']::text[], 'Анна Смит', '182/8; Свобода');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Смит');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Расторопные аколитки в мокрых майках', 'пешка', 3, 4, 3, array['Мобильность']::text[], 'Маяк', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Маяк');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Слетевший с катушек психик (под транквилизаторами)', 'пешка', 5, 4, 4, array['Натиск']::text[], 'Дюран маркиз дю Бек-Креспен и СМС', 'Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Сон о Натали Яхонтовой', 'пешка', 3, 3, 3, array['Штурм']::text[], 'СМС', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Том Нэтсуорти', 'пешка', 3, 5, 3, array['Разведка']::text[], 'Анна Фэнг', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Фэнг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ушная ящерица', 'пешка', 1, 3, 2, array['Разведка']::text[], 'Регент Гильгамеш', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Регент Гильгамеш');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ф.Я.Соколов', 'пешка', 3, 9, 3, array['Перезагрузка']::text[], 'Анна Фэнг', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Фэнг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Цитотаксис', 'пешка', 3, 2, 2, array['Плен']::text[], 'Регент Гильгамеш', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Регент Гильгамеш');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Элитная гейша', 'пешка', 4, 5, 4, array['Подкуп']::text[], 'Дюран маркиз дю Бек-Креспен и СМС', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Corday 2.1', 'конь', 3, 4, 4, array['Осведомленность']::text[], 'Маяк', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Маяк');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Dobbin B-16-53', 'конь', 2, 4, 4, array['Лечение']::text[], 'Влада и Эрик', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Эрик');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Nightmare Moon', 'конь', 4, 4, 1, array['Плен']::text[], 'Анна Смит', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Смит');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Дорея, шустрая посыльная Людвига', 'конь', 5, 4, 3, array['Мобильность']::text[], 'Людвиг Красивый и Королевна Эгле', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Маленький, но зловещий соменок', 'конь', 6, 6, 5, array['Плен']::text[], 'СМС', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Нечто...', 'конь', 4, 4, 0, array['Оно пришло из-под земли']::text[], 'СМС и Царевна-Лягушка', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС', 'Царевна-Лягушка');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пони черный "для дочери" по кличке Злой', 'конь', 3, 3, 0, array['Мобильность']::text[], 'Королевна Эгле', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Простенький IMP', 'конь', 2, 3, 3, array['Разведка']::text[], 'Неро и Дикси', 'Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пылающий Байкер', 'конь', 5, 3, 1, array['Натиск']::text[], 'Влада и Эрик', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Эрик');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Рабочая лошадка Wayne', 'конь', 0, 0, 6, array['Разведка']::text[], 'Дюран маркиз дю Бек-Креспен и СМС', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Скакун-Призер', 'конь', 3, 4, 4, array['Замри!']::text[], 'СМС', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Улайри Черный Ветер', 'конь', 4, 4, 0, array['Мобильность']::text[], 'Анна Фэнг', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Фэнг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Анна Фэнг Цветок Ветра', 'офицер', 6, 6, 4, array['Дураки и дороги']::text[], 'Анна Фэнг', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Фэнг');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Белый вороненок', 'офицер', 5, 5, 2, array['Всем друг']::text[], 'Людвиг Красивый и Королевна Эгле', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Жаннет, врач с ЛВ', 'офицер', 3, 3, 4, array['Будьте здоровы']::text[], 'Людвиг Красивый и Королевна Эгле', 'Шрам; Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Захватывающий землерой', 'офицер', 4, 5, 4, array['Плен']::text[], 'Регент Гильгамеш', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Регент Гильгамеш');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Капитан Маяк', 'офицер', 5, 5, 5, array['Переговоры']::text[], 'Маяк', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Маяк');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Колокольчик', 'офицер', 8, 5, 4, array['Закон Талиона']::text[], 'СМС и Царевна-Лягушка; Дюран маркиз дю Бек-Креспен и СМС', 'Шрам; Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС', 'Царевна-Лягушка');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Младший ученик Марк Ковалевский', 'офицер', 5, 5, 5, array['Всем друг']::text[], 'Маяк', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Маяк');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Наемница и конрабандистка', 'офицер', 5, 5, 5, array['Дураки и дороги']::text[], 'Людвиг Красивый и Королевна Эгле', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Охотник', 'офицер', 5, 4, 1, array['Мобильность']::text[], 'Регент Гильгамеш', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Регент Гильгамеш');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('План', 'офицер', 5, 3, 1, array['Закон Талиона']::text[], 'Анна Смит', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Смит');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Призрачный пегас', 'офицер', 1, 4, 4, array['Дураки и дороги']::text[], 'Анна Смит', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Смит');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ридель Ру', 'офицер', 5, 3, 5, array['Осведомленность']::text[], 'СМС и Царевна-Лягушка', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС', 'Царевна-Лягушка');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Роланд', 'офицер', 9, 4, 2, array['Мобильность']::text[], 'Неро и Дикси', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Верные акробаты Ламек', 'ладья', 4, 5, 6, array['Я — лист на ветру']::text[], 'Неро и Дикси', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Диггер Счастливчик', 'ладья', 10, 8, 5, array['Оно пришло из-под земли']::text[], 'Анна Смит', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Смит');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Кукла первого наследника', 'ладья', 5, 5, 6, array['Шлагбаум']::text[], 'Регент Гильгамеш', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Регент Гильгамеш');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Лелит Гесперак', 'ладья', 7, 4, 1, array['Провокация']::text[], 'Людвиг Красивый и Королевна Эгле', 'Шрам');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Но', 'ладья', 11, 10, 0, array['Плен']::text[], 'Анна Смит', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Анна Смит');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Ода Аои', 'ладья', 8, 4, 0, array['Мобильность']::text[], 'Неро', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Охотники на моколе', 'ладья', 9, 4, 1, array['Плен']::text[], 'Неро', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Неро');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Пес Нюх', 'ладья', 6, 5, 1, array['Приключения ждут!']::text[], 'Маяк', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Маяк');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Стая без названия', 'ладья', 6, 4, 7, array['Всем друг']::text[], 'Королевна Эгле', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Тачила Генерала Ли', 'ладья', 6, 4, 6, array['Я — лист на ветру']::text[], 'СМС и Царевна-Лягушка; Дюран маркиз дю Бек-Креспен и СМС', 'Шрам; Метро; 182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('СМС', 'Царевна-Лягушка');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Хабба п-б №13-2514', 'ладья', 8, 2, 0, array['Провокация']::text[], 'Королевна Эгле', '182/8');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Королевна Эгле');
insert into figures (name, nominal, s, l, v, properties, owner_label, sources) values ('Мирный советский трактор', 'ферзь', 6, 4, 1, array['Перезагрузка']::text[], 'Регент Гильгамеш', 'Метро');
insert into figure_owners select currval('figures_id_seq'), id from players where name in ('Регент Гильгамеш');
update figures set owner_label = 'Пятая и Любомир; СМС' where name = 'Родич Сидор';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Родич Сидор' and p.name in ('СМС') on conflict do nothing;
update figures set owner_label = 'Пятая; Королевна Эгле' where name = 'Тюльпа-викинг';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Тюльпа-викинг' and p.name in ('Королевна Эгле') on conflict do nothing;
update figures set owner_label = 'Сэр Малеагант; Дюран маркиз дю Бек-Креспен и СМС' where name = 'Норовистый (черноглазый и златогривый) жеребец';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Норовистый (черноглазый и златогривый) жеребец' and p.name in ('СМС') on conflict do nothing;
update figures set owner_label = 'Пятая; Людвиг Красивый и Королевна Эгле' where name = 'Самум Саббат';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Самум Саббат' and p.name in ('Королевна Эгле') on conflict do nothing;
update figures set owner_label = 'Зои и Четвёртый; Анна Смит' where name = 'Стриптизерша Аурика';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Стриптизерша Аурика' and p.name in ('Анна Смит') on conflict do nothing;
update figures set owner_label = 'Винсент Фламбо и Андромеда; Людвиг Красивый и Королевна Эгле' where name = 'Меркурий';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Меркурий' and p.name in ('Королевна Эгле') on conflict do nothing;
update figures set owner_label = 'Зои; СМС и Царевна-Лягушка' where name = 'Голем из проволоки';
insert into figure_owners select f.id, p.id from figures f, players p where f.name = 'Голем из проволоки' and p.name in ('СМС', 'Царевна-Лягушка') on conflict do nothing;

-- миграция 010: новые стратеги, Сэр Малеагант = Александр Смит
insert into players (name, characters, is_admin) values
  ('Стужа', array['Стужа']::text[], false),
  ('Вилена', array['Вилена']::text[], false),
  ('Фифи', array['Фифи']::text[], false)
on conflict (name) do nothing;
update players set characters = characters || array['Александр Смит']
where name = 'Сэр Малеагант' and not ('Александр Смит' = any(characters));

insert into events (kind, data, comment) values ('import', jsonb_build_object('figures', 175, 'players', 25), 'Перенос из дашборда «Фигуры тактички»');
commit;
