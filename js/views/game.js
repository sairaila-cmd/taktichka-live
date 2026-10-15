// Страница игры: ход и инициатива, стратеги и отряды, действия по коду, блок ведущего.
import { rows, rowsAll, call, cache, session, isAdmin, watch, loadPlayers } from '../api.js?v=202610160048';
import { h, clear, btn, badge, modal, form, act, toast, fmtTime, NOM_GLYPH, STATE_RU, GIFT_RU, STATUS_RU, plural } from '../ui.js?v=202610160048';
import { logList, squadCard, pname, glyph, res } from './common.js?v=202610160048';
import { statsCard } from './stats.js?v=202610160048';


export default async function gameView(root, gameId) {
  gameId = Number(gameId);
  const box = h('div', { class: 'stack', style: 'gap: var(--gap)' });
  root.append(box);
  let data = await load(gameId);
  draw();

  // Живые обновления: перерисовка с задержкой; пока открыто окно — после его закрытия.
  let timer = null, dirty = false;
  const dlg = document.getElementById('dialog');
  const onClose = () => { if (dirty) { dirty = false; reload(); } };
  dlg.addEventListener('close', onClose);
  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(() => { if (dlg.open) dirty = true; else reload(); }, 400);
  };
  const f = 'game_id=eq.' + gameId;
  const unwatch = watch('game' + gameId, [['squads', f], ['squad_figures', f], ['strategists', f], ['turns', f],
    'squad_moves', ['battles', f], ['game_gifts', f], 'players'], schedule);
  return () => { unwatch(); clearTimeout(timer); dlg.removeEventListener('close', onClose); };

  async function reload() {
    try { data = await load(gameId); draw(); } catch (e) { toast(e.message, true); }
  }
  function done() { return reload(); }

  function draw() {
    const d = data;
    if (!d.game) { clear(box, h('section', { class: 'card' }, h('h2', {}, 'Игра не найдена'))); return; }
    clear(box,
      header(d), turnCard(d), myCard(d),
      d.conflicts.length ? conflictsCard(d) : null,
      strategistsCard(d), battlesCard(d),
      d.gifts.has('gorkaya') || d.echoes.length ? echoesCard(d) : null,
      isAdmin() ? adminCard(d) : null,
      statsCard(d, gameId),
      h('section', { class: 'card' }, h('h2', {}, 'Журнал игры'), logList(d.events, d.maps)));
  }

  // ───────── шапка ─────────
  function header(d) {
    const g = d.game;
    return h('div', { class: 'stack' },
      h('h1', { class: 'page-title' }, g.title),
      h('div', { class: 'row', style: 'justify-content: center' },
        badge(STATUS_RU[g.status], g.status === 'running' ? 'ok' : g.status === 'draft' ? 'moon' : ''),
        g.starts_at ? badge('начало ' + fmtTime(g.starts_at)) : null,
        [...d.gifts].map((x) => badge('☾ ' + GIFT_RU[x], 'moon'))),
      d.gifts.has('chernaya') ? h('p', { class: 'lede small' }, 'Чёрная луна: движение 4 гекса, Мобильность и Замри — тоже 4; ход идёт тактами — за такт одним отрядом.') : null);
  }

  // ───────── ход ─────────
  function turnCard(d) {
    if (d.game.status === 'draft') {
      return h('section', { class: 'card' }, h('h2', {}, 'Подготовка'),
        h('p', { class: 'muted small', style: 'margin:0' }, 'Идёт сбор отрядов. Составы видны всем сразу; после начала игры состав меняется только Обменом и свойствами.'),
        orderList(d, null));
    }
    const t = d.turn;
    const me = d.myStrategist;
    const actions = [];
    if (t && t.phase === 'intrigues' && (me || isAdmin())) actions.push(btn('Активировать интригу', () => intrigue(d), 'primary'));
    if (t && t.phase === 'actions' && me && t.current_strategist === me.id) {
      actions.push(btn(d.gifts.has('chernaya') ? 'Пропустить такт' : 'Закончить ход', () =>
        act(() => call('api_pass_turn', { p_game: gameId }), 'Ход передан', done)));
    }
    if (isAdmin() && d.game.status === 'running') {
      actions.push(btn('Новый ход', () => newTurn(d)));
      if (t && t.phase === 'intrigues') actions.push(btn('Интриги закончены → действия', () => act(() => call('api_admin_turn_actions', { p_game: gameId }), 'Действия по инициативе', done)));
      if (t && t.phase === 'actions') actions.push(btn('Передать ход…', () => setTurn(d)));
    }
    const phaseText = !t ? 'ходов ещё не было' : t.phase === 'intrigues' ? 'интриги (до действий по инициативе)' :
      t.phase === 'actions' ? 'действия по инициативе' : 'ход закончен';
    const intrigues = t ? d.events.filter((e) => e.kind === 'intrigue' && e.amount === t.number) : [];
    return h('section', { class: 'card' },
      h('header', {}, h('h2', {}, t ? 'Ход ' + t.number : 'Ход'), h('div', { class: 'row' }, actions)),
      h('div', { class: 'row small' }, badge(phaseText, t && t.phase === 'actions' ? 'ok' : 'moon'),
        t && d.gifts.has('chernaya') ? badge('такт ' + t.tact + ' из ' + t.tacts, 'info') : null,
        t && t.current_strategist ? h('span', {}, 'Сейчас ходит: ', h('b', {}, d.label(t.current_strategist))) : null),
      orderList(d, t),
      h('div', { class: 'frame-legend small' }, h('span', { class: 'fl active' }, 'может действовать'), h('span', { class: 'fl waiting' }, 'ждёт череда'), h('span', { class: 'fl done' }, 'уже ходил в этом ходу'),
        h('span', { class: 'fl destroyed' }, 'уничтожен')),
      intrigues.length ? h('div', { class: 'stack small' }, h('b', {}, 'Интриги этого хода'),
        intrigues.map((e) => h('div', {}, '◆ ', (e.data && e.data.label) || '', e.comment ? ': ' + e.comment : ''))) : null);
  }

  function orderList(d, t) {
    if (!d.order.length) return h('p', { class: 'empty' }, 'Стратегов пока нет.');
    return h('div', { class: 'stack small' }, h('span', { class: 'muted' }, 'Порядок хода (инициатива, от большей к меньшей):'),
      h('ol', { class: 'order' }, d.order.map((s) => h('li', { class: t && t.current_strategist === s.id ? 'now' : '',
        title: d.shifted.has(s.id) ? 'Чёрная луна: у стратега 3 и больше отрядов — он ходит после первой тройки' : null },
        d.label(s.id), s.initiative != null ? ' · ' + s.initiative : ' · ?', d.shifted.has(s.id) ? ' · после тройки' : ''))));
  }

  // ───────── «Мой стратег» ─────────
  function myCard(d) {
    if (!session.me) return h('section', { class: 'card' }, h('p', { class: 'muted', style: 'margin:0' }, 'Войдите по личному коду (вверху справа), чтобы собирать отряды и действовать.'));
    if (session.me.is_admin && !d.myStrategist) return null;
    const me = d.myStrategist;
    const g = d.game;
    const items = [];
    const invites = d.strategists.filter((s) => s.invited === session.me.id);
    if (!me) {
      if (g.status === 'draft') {
        items.push(h('p', { class: 'muted small', style: 'margin:0' }, 'Вы ещё не участвуете в этой игре.'),
          h('div', { class: 'row' }, btn('Участвовать', () => act(() => call('api_join_game', { p_game: gameId }), 'Вы в игре', done), 'primary'),
            invites.map((s) => btn('Принять приглашение: ' + d.label(s.id), () => accept(d, s))),
            btn('+ Новый отряд', () => buildSquad(d, null))));
      } else items.push(h('p', { class: 'muted small', style: 'margin:0' }, 'Вы не участвуете в этой игре.'));
      return h('section', { class: 'card' }, h('h2', {}, 'Моё участие'), items);
    }
    const members = d.membersOf(me.id);
    const sq = d.squadsOf(me.id);
    const maxSquads = 2 + Math.max(0, ...members.map((m) => (cache.playerById[m] || {}).bonus_squads || 0));
    const used = {};
    sq.forEach((s) => d.figsOf(s.id).forEach(({ fig, sf }) => { if (!sf.borrowed) used[fig.nominal] = (used[fig.nominal] || 0) + 1; }));
    const actions = [];
    if (g.status === 'draft' || isAdmin()) actions.push(btn('+ Новый отряд', () => buildSquad(d, null), 'primary'));
    if (g.status === 'draft' && members.length === 1) {
      if (me.invited) actions.push(badge('ждём ответа: ' + pname(me.invited), 'warn'));
      else actions.push(btn('Пригласить напарника', () => invite(d)));
    }
    invites.forEach((s) => { if (g.status === 'draft' && members.length === 1) actions.push(btn('Принять приглашение: ' + d.label(s.id), () => accept(d, s))); });
    return h('section', { class: 'card' },
      h('header', {}, h('h2', {}, 'Моё участие: ' + d.label(me.id)), h('div', { class: 'row' }, actions)),
      h('div', { class: 'row small' },
        badge('Ресурсы: ' + d.money(me.id) + (me.wallet != null ? ' (общий кошелёк)' : ''), 'moon'),
        badge('отрядов ' + sq.length + ' из ' + maxSquads),
        cache.nominals.map((n) => (used[n.name] ? badge(NOM_GLYPH[n.name] + ' ' + used[n.name] + '/' + n.max_per_strategist,
          used[n.name] > n.max_per_strategist ? 'bad' : '') : null))),
      d.kept.length && (g.status === 'draft' || isAdmin()) ? h('div', { class: 'row small' }, 'Трофеи в запасе: ',
        d.kept.filter((t) => members.includes(t.holder)).map((t) => btn('«' + t.name + '» → в отряд', () => equip(d, t), 'small'))) : null,
      members.length > 1 ? h('p', { class: 'muted small', style: 'margin:0' }, 'Вы напарники: фигуры обоих идут в отряды вперемешку без передачи; ограничения общие; Ресурсы — общий кошелёк.') : null,
      h('div', { class: 'squads' }, sq.length ? sq.map((x) => squadView(d, x, me)) :
        h('p', { class: 'empty' }, g.status === 'draft' ? 'Отрядов пока нет — нажмите «+ Новый отряд».' : 'Отрядов нет.')));
  }

  // ───────── стратеги и отряды ─────────
  function strategistsCard(d) {
    if (!d.order.length) return h('section', { class: 'card' }, h('h2', {}, 'Отряды'), h('p', { class: 'empty' }, 'Пока никто не собрал отряд.'));
    return h('section', { class: 'card' }, h('h2', {}, 'Отряды'),
      d.order.map((s) => h('div', { class: 'stack' },
        h('div', { class: 'row' }, h('h3', { style: 'margin:0' }, d.label(s.id)),
          s.initiative != null ? badge('инициатива ' + s.initiative, 'info') : null,
          d.shifted.has(s.id) ? badge('после первой тройки (3+ отряда)', 'warn') : null,
          badge('Ресурсы ' + d.money(s.id) + (s.wallet != null ? ' (общие)' : '')),
          isAdmin() && d.game.status !== 'closed' ? btn('+ Отряд', () => buildSquad(d, null, s.id), 'small') : null),
        h('div', { class: 'squads' }, d.squadsOf(s.id).length ? d.squadsOf(s.id).map((sq) => squadView(d, sq, s)) : h('p', { class: 'empty' }, 'Отрядов нет.')))));
  }

  function squadView(d, sq, s) {
    const mine = (d.myStrategist && d.myStrategist.id === s.id) || isAdmin();
    const running = d.game.status === 'running';
    const acts = [];
    if ((mine && d.game.status === 'draft') || (isAdmin() && d.game.status !== 'closed')) {
      acts.push(btn('Изменить', () => buildSquad(d, sq), 'small'),
        btn('Распустить', () => confirmDo('Распустить отряд «' + sq.name + '»?', () => call('api_squad_delete', { p_squad: sq.id }), 'Отряд распущен'), 'small danger'));
    }
    // Игрок действует отрядом только в свой черёд; ведущему кнопки доступны всегда.
    const notNow = isAdmin() ? null : whyNotNow(d, sq, s);
    const off = (b, why) => { if (why) { b.disabled = true; b.title = why; } return b; };
    if (mine && running && !sq.destroyed) {
      const tr = d.turnOf[sq.id] || {};
      const fin = tr.finished ? 'Ход отряда в этом ходу закончен' : null;
      acts.push(off(btn('Ход', () => move(d, sq), 'small'), notNow || fin), off(btn('Напасть', () => attack(d, sq), 'small'), notNow || fin),
        off(btn('Свойство', () => useProperty(d, sq), 'small'), notNow), off(btn('Обмен', () => exchange(d, sq), 'small'), notNow || fin),
        off(btn('Оплатить', () => pay(d, sq), 'small'), notNow), off(btn('Эхо', () => echoMark(d, sq), 'small'), notNow));
      if (d.gifts.has('alaya') && sq.rage > 0) acts.push(off(btn('Ярость', () => rage(d, sq), 'small'), notNow));
    }
    if (mine && running) acts.push(btn('Состояние фигур', () => states(d, sq), 'small'));
    if (mine && d.trophiesOf(sq.id).length) acts.push(off(btn('Трофеи', () => trophies(d, sq), 'small'), running ? notNow : null));
    if (mine && sq.destroyed && !sq.dead_figure) acts.push(btn('Кто погиб?', () => death(d, sq), 'small primary'));
    if (isAdmin() && d.game.status !== 'closed') {
      acts.push(btn('+ Трофей', () => giveTrophy(sq), 'small'));
      if (d.gifts.has('alaya')) acts.push(btn('Ярость =', () => setRage(sq), 'small'));
      if (running) acts.push(btn('Фигуру в другой отряд', () => moveFigure(d, sq), 'small'));
    }
    return squadCard(sq, {
      figs: d.figsOf(sq.id), trophies: d.trophiesOf(sq.id), totals: d.totals[sq.id], moon: d.moon[sq.id],
      moved: d.moves[sq.id], mine: d.myStrategist && d.myStrategist.id === s.id, gifts: d.gifts, figById: d.figById,
      echo: sq.echo_id ? (d.echoById[sq.echo_id] ? d.echoById[sq.echo_id].name : (isAdmin() ? 'скрытое Эхо #' + sq.echo_id : null)) : null,
      status: squadStatus(d, sq),
      inBattle: d.inBattle.has(sq.id),
    }, acts);
  }

  // Рамка отряда (видна всем одинаково): destroyed — уничтожен, done — в этом ходу уже ходил,
  // active — может действовать прямо сейчас, waiting — ещё не ходил и ждёт череда, null — вне фазы действий.
  function squadStatus(d, sq) {
    if (sq.destroyed) return 'destroyed';
    const tr = d.turnOf[sq.id];
    if (tr && tr.finished) return 'done';
    const t = d.turn;
    if (d.game.status !== 'running' || !t || t.phase !== 'actions') return null;
    if (tr && d.gifts.has('chernaya') && tr.tact < t.tact) return 'done';
    if (t.current_strategist !== sq.strategist_id) return 'waiting';
    if (d.gifts.has('chernaya') && d.movesList.some((m) => m.strategist_id === sq.strategist_id && m.tact === t.tact && m.squad_id !== sq.id)) return 'waiting';
    return 'active';
  }

  // Почему отряд игрока сейчас не может действовать (null — может).
  function whyNotNow(d, sq, s) {
    const t = d.turn;
    if (!t || t.phase !== 'actions') return 'Сейчас не фаза действий';
    if (t.current_strategist !== s.id) return 'Сейчас ходит ' + (t.current_strategist ? d.label(t.current_strategist) : 'другой стратег');
    if (d.gifts.has('chernaya')) {
      const other = d.movesList.find((m) => m.strategist_id === s.id && m.tact === t.tact && m.squad_id !== sq.id);
      if (other) return 'Чёрная луна: в этом такте ходит «' + d.squadName(other.squad_id) + '»';
    }
    return null;
  }

  function battlesCard(d) {
    if (!d.battles.length) return null;
    return h('section', { class: 'card' }, h('h2', {}, 'Бои'),
      h('ul', { class: 'log' }, d.battles.map((b) => h('li', {},
        h('time', {}, fmtTime(b.created_at)),
        h('div', {}, h('a', { href: '#/battle/' + b.id }, '«' + d.squadName(b.attacker) + '» → «' + d.squadName(b.defender) + '»'), ' ',
          b.status === 'open' ? badge('идёт', 'ok') : badge(b.winner ? 'победа «' + d.squadName(b.winner) + '»' : 'ничья'))))));
  }

  function echoesCard(d) {
    return h('section', { class: 'card' }, h('h2', {}, 'Эхо Расколотого мира'),
      d.echoes.length ? h('div', { class: 'grid narrow' }, d.echoes.map((e) => h('div', { class: 'squad' },
        h('div', { class: 'row' }, h('b', {}, e.name), badge({ open: 'открыто', active: 'действует', ended: 'закончилось' }[e.status],
          e.status === 'active' ? 'bad' : '')),
        e.description ? h('div', { class: 'small' }, e.description) : null,
        e.blocked_properties && e.blocked_properties.length ? h('div', { class: 'small muted' }, 'Не работают: ' + e.blocked_properties.join(', ')) : null,
        e.move_cost ? h('div', { class: 'small muted' }, 'Движение: +' + res(e.move_cost)) : null,
        e.end_condition ? h('div', { class: 'small muted' }, 'Пока: ' + e.end_condition) : null,
        (() => { const inside = d.squads.filter((s) => s.echo_id === e.id);
          return inside.length ? h('div', { class: 'small' }, 'Здесь стоят: ' + inside.map((s) => '«' + s.name + '»').join(', ')) : null; })())))
        : h('p', { class: 'empty' }, 'Эхо пока не обнаружены. Их 5, правила каждого становятся известны, когда его находят.'),
      h('p', { class: 'muted small', style: 'margin:0' }, 'Эхо занимает часть карты: его правила действуют на отряд, который прошёл через него или остановился в нём (кнопка «Эхо» у отряда или поле «Эхо по пути» в окне хода).'));
  }

  function conflictsCard(d) {
    return h('section', { class: 'card' }, h('h2', {}, 'Конфликты совладения'),
      h('p', { class: 'muted small', style: 'margin:0' }, 'Одна фигура стоит в отрядах разных стратегов — решает ведущий.'),
      d.conflicts.map((c) => h('div', { class: 'small' }, '◆ «' + c.name + '»: ' + c.squads.map((id) => '«' + d.squadName(id) + '»').join(', '))));
  }

  // ───────── блок ведущего ─────────
  function adminCard(d) {
    const g = d.game;
    const giftBoxes = Object.entries(GIFT_RU).map(([k, t]) => h('label', { class: 'inline' },
      h('input', { type: 'checkbox', checked: d.gifts.has(k), onchange: (e) => act(() => call('api_admin_gift', { p_game: gameId, p_gift: k, p_on: e.target.checked }),
        e.target.checked ? 'Дар включён' : 'Дар выключен', done).then((r) => { if (r === undefined) e.target.checked = !e.target.checked; }) }), t));
    const statusBtns = [];
    if (g.status === 'draft') statusBtns.push(btn('Начать игру', () => setStatus(d, 'running'), 'primary'));
    if (g.status === 'running') statusBtns.push(btn('Закончить игру', () => setStatus(d, 'closed'), 'danger'), btn('Вернуть в сбор отрядов', () => setStatus(d, 'draft')));
    if (g.status === 'closed') statusBtns.push(btn('Открыть снова', () => setStatus(d, 'running')));
    statusBtns.push(btn('Название и время', () => renameGame(d)));
    const pairs = d.strategists.filter((s) => s.wallet != null && s.wallet > 0);
    const activeTrophies = d.trophies.filter((t) => t.status === 'active');
    return h('section', { class: 'card', style: 'border-color: rgba(231,224,124,.5)' },
      h('h2', {}, 'Ведущему'),
      h('div', { class: 'row' }, statusBtns),
      h('div', { class: 'stack small' }, h('b', {}, 'Дары лун'), h('div', { class: 'row' }, giftBoxes)),
      h('div', { class: 'stack small' }, h('b', {}, 'Инициатива'),
        h('div', { class: 'row' }, d.strategists.map((s) => {
          const inp = h('input', { type: 'number', value: s.initiative ?? '', 'aria-label': 'Инициатива ' + d.label(s.id) });
          return h('label', { class: 'inline' }, d.label(s.id), inp,
            btn('✓', () => act(() => call('api_admin_initiative', { p_strategist: s.id, p_value: inp.value === '' ? null : Number(inp.value) }), 'Инициатива сохранена', done), 'small'));
        }))),
      h('div', { class: 'row' }, g.status !== 'closed' ? btn('Добавить стратега…', () => addStrategist(d)) : null,
        btn('Сделать напарниками…', () => pairAdmin(d)), btn('Эхо…', () => echoesAdmin(d)),
        pairs.map((s) => btn('Разделить кошелёк: ' + d.label(s.id) + ' (' + s.wallet + ')', () => splitWallet(d, s)))),
      activeTrophies.length && g.status !== 'draft' ? h('div', { class: 'stack small' }, h('b', {}, 'Трофеи после игры: остаются или исчезают'),
        activeTrophies.map((t) => {
          const sq = d.squadById[t.squad_id];
          const members = sq ? d.membersOf(sq.strategist_id) : [];
          const sel = h('select', {}, h('option', { value: '' }, 'исчезает'), members.map((m) => h('option', { value: m }, 'остаётся у ' + pname(m))));
          return h('div', { class: 'row' }, '«' + t.name + '» (' + (sq ? sq.name : '?') + ')', sel,
            btn('✓', () => act(() => call('api_admin_trophy_end', { p_trophy: t.id, p_holder: sel.value ? Number(sel.value) : null }), 'Готово', done), 'small'));
        })) : null);
  }

  // ───────── действия ─────────
  function confirmDo(text, fn, ok) {
    modal('Подтвердите', (close) => h('div', { class: 'stack' }, h('p', {}, text),
      h('div', { class: 'row end' }, btn('Отмена', close), btn('Да', () => act(fn, ok, () => { close(); done(); }), 'primary danger'))));
  }

  function intrigue() {
    modal('Интрига', (close) => form([
      { name: 'text', label: 'Что за интрига (видно всем)', type: 'textarea', required: true },
    ], 'Активировать', (v) => act(() => call('api_intrigue', { p_game: gameId, p_text: v.text }), 'Интрига записана', () => { close(); done(); })));
  }

  function newTurn(d) {
    const fields = d.gifts.has('chernaya') ? [{ name: 'tacts', label: 'Сколько тактов в ходе (Чёрная луна)', type: 'number', value: 2, min: 1 }] : [];
    modal('Новый ход', (close) => h('div', { class: 'stack' },
      h('p', { class: 'muted small', style: 'margin:0' }, 'Ход начнётся с фазы интриг; потом нажмите «Интриги закончены → действия».'),
      form(fields, 'Начать ход', (v) => act(() => call('api_admin_turn_start', { p_game: gameId, p_tacts: v.tacts ?? null }),
        (n) => 'Ход ' + n + ': интриги', () => { close(); done(); }))));
  }

  function setTurn(d) {
    modal('Передать ход', (close) => form([
      { name: 'st', label: 'Кто ходит', type: 'select', options: d.order.map((s) => [s.id, d.label(s.id)]), value: d.turn && d.turn.current_strategist },
      d.gifts.has('chernaya') ? { name: 'tact', label: 'Такт', type: 'number', value: d.turn ? d.turn.tact : 1, min: 1 } : null,
    ].filter(Boolean), 'Передать', (v) => act(() => call('api_admin_turn_set', { p_game: gameId, p_strategist: Number(v.st), p_tact: v.tact ?? null, p_phase: null }),
      'Указатель хода передвинут', () => { close(); done(); })));
  }

  function invite(d) {
    const taken = new Set(d.members.filter((m) => d.membersOf(m.strategist_id).length > 1).map((m) => m.player_id));
    const opts = cache.players.filter((p) => !p.is_admin && p.id !== session.me.id && !taken.has(p.id)).map((p) => [p.id, p.name]);
    modal('Пригласить напарника', (close) => h('div', { class: 'stack' },
      h('p', { class: 'muted small', style: 'margin:0' }, 'Напарник может быть только один. Ресурсы сложатся в общий кошелёк, ограничения на отряды станут общими. Приглашение надо подтвердить кодом напарника до начала игры.'),
      form([{ name: 'p', label: 'Кого', type: 'select', options: opts }], 'Пригласить',
        (v) => act(() => call('api_partner_invite', { p_game: gameId, p_partner: Number(v.p) }), 'Приглашение отправлено', () => { close(); done(); }))));
  }
  function accept(d, s) {
    confirmDo('Стать напарником: ' + d.label(s.id) + '? Ваши Ресурсы и Ресурсы напарника сольются в общий кошелёк на эту игру.',
      () => call('api_partner_accept', { p_game: gameId, p_inviter: d.membersOf(s.id)[0] }), 'Вы напарники');
  }

  // Окно сборки отряда. forSid — стратег, за которого собирает ведущий (иначе — свой).
  function buildSquad(d, sq, forSid) {
    const me = d.myStrategist;
    const sid = sq ? sq.strategist_id : (forSid || (me && me.id));
    const members = sid ? d.membersOf(sid) : [session.me.id];
    const inOther = new Set();
    if (sid) d.squadsOf(sid).forEach((x) => { if (!sq || x.id !== sq.id) d.figsOf(x.id).forEach(({ fig }) => inOther.add(fig.id)); });
    const current = new Set(sq ? d.figsOf(sq.id).map(({ fig }) => fig.id) : []);
    const rankOf = (f) => cache.nominals.find((n) => n.name === f.nominal).rank;
    const ownedByMembers = (f) => (d.ownersOf[f.id] || []).some((p) => members.includes(p));
    let showAll = false;   // ведущий может взять и чужие фигуры
    const eligibleNow = () => d.figures.filter((f) => f.status === 'active' && (current.has(f.id) ||
      (!inOther.has(f.id) && (showAll || ownedByMembers(f)))))
      .sort((a, b) => (rankOf(b) - rankOf(a)) || a.name.localeCompare(b.name, 'ru'));
    let eligible = eligibleNow();
    const usedOther = {};
    if (sid) d.squadsOf(sid).forEach((x) => { if (!sq || x.id !== sq.id) d.figsOf(x.id).forEach(({ fig, sf }) => { if (!sf.borrowed) usedOther[fig.nominal] = (usedOther[fig.nominal] || 0) + 1; }); });
    const name = h('input', { type: 'text', value: sq ? sq.name : '', required: true, placeholder: 'Уникальное в этой игре' });
    const filter = h('input', { type: 'search', placeholder: 'Найти фигуру' });
    const summary = h('div', { class: 'row small' });
    const listBox = h('div', { class: 'stack', style: 'max-height: 22rem; overflow: auto' });
    const chosen = new Set(current);
    const drawSummary = () => {
      const figs = eligible.filter((f) => chosen.has(f.id));
      const t = figs.reduce((a, f) => ({ s: a.s + f.s, l: a.l + f.l, v: a.v + f.v }), { s: 0, l: 0, v: 0 });
      const ranks = figs.map((f) => cache.nominals.find((n) => n.name === f.nominal).rank);
      const white = figs.length === 3 && new Set(ranks).size === 3 && Math.max(...ranks) - Math.min(...ranks) === 2;
      const over = cache.nominals.filter((n) => (usedOther[n.name] || 0) + figs.filter((f) => f.nominal === n.name).length > n.max_per_strategist);
      clear(summary, badge(figs.length + ' из 1–3', figs.length >= 1 && figs.length <= 3 ? 'ok' : 'bad'),
        badge('С ' + t.s + ' · Л ' + t.l + ' · В ' + t.v, 'moon'),
        d.gifts.has('belaya') && white ? badge('☾ три номинала подряд: +2 к Силе', 'moon') : null,
        over.map((n) => badge('слишком много: ' + n.name + ' (можно ' + n.max_per_strategist + ' на стратега)', 'bad')));
    };
    const drawList = () => {
      const q = filter.value.trim().toLowerCase();
      clear(listBox, eligible.filter((f) => !q || (f.name + ' ' + (f.properties || []).join(' ')).toLowerCase().includes(q)).map((f) =>
        h('label', { class: 'inline', style: 'color: var(--fg)' },
          h('input', { type: 'checkbox', checked: chosen.has(f.id), onchange: (e) => { e.target.checked ? chosen.add(f.id) : chosen.delete(f.id); drawSummary(); } }),
          glyph(f.nominal) + ' ' + f.name, h('span', { class: 'muted small' }, ' ' + f.s + '/' + f.l + '/' + f.v + ' · ' + (f.properties || []).join(' / ')),
          members.length > 1 ? h('span', { class: 'muted small' }, ' · ' + (d.ownersOf[f.id] || []).filter((p) => members.includes(p)).map(pname).join(', ')) : null)));
    };
    filter.addEventListener('input', drawList);
    drawList(); drawSummary();
    const allBox = isAdmin() ? h('label', { class: 'inline' }, h('input', { type: 'checkbox', onchange: (e) => {
      showAll = e.target.checked; eligible = eligibleNow(); drawList(); drawSummary(); } }), 'показать все фигуры (не только участников)') : null;
    const whose = sid ? d.label(sid) : session.me.name;
    modal((sq ? 'Отряд «' + sq.name + '»' : 'Новый отряд') + ' — ' + whose, (close) => h('div', { class: 'stack' },
      isAdmin() && d.game.status === 'running' && sq ? h('p', { class: 'muted small', style: 'margin:0' }, 'Игра идёт: фигуры, которые остаются в отряде, сохранят своё состояние; новые встанут целыми.') : null,
      h('label', {}, 'Название отряда', name), h('div', { class: 'row' }, filter, allBox), listBox, summary,
      eligible.length ? null : h('p', { class: 'empty' }, 'Нет свободных фигур.'),
      h('div', { class: 'row end' }, btn('Сохранить отряд', () => act(() => call('api_squad_save', {
        p_game: gameId, p_squad: sq ? sq.id : null, p_name: name.value, p_figures: [...chosen],
        p_strategist: sq ? null : (forSid || null),
      }), 'Отряд сохранён', () => { close(); done(); }), 'primary'))));
  }

  function equip(d, t) {
    const sq = d.squadsOf(d.myStrategist.id);
    modal('Трофей «' + t.name + '» в отряд', (close) => form([
      { name: 'sq', label: 'Отряд', type: 'select', options: sq.map((s) => [s.id, s.name]) },
    ], 'Взять', (v) => act(() => call('api_trophy_equip', { p_trophy: t.id, p_squad: Number(v.sq) }), 'Трофей в отряде', () => { close(); done(); })));
  }

  // Ход отряда: сначала движение (Перемещение / Стоит на месте), потом одно действие
  // (Нападение и Обмен — своими кнопками; здесь Активация фишки или «Стоит на месте» — закончить ход).
  function move(d, sq) {
    const t = d.turn;
    const tr = d.turnOf[sq.id] || {};
    const opts = tr.moved
      ? [['Активация фишки', 'Активация фишки — ход закончится'], ['Стоит на месте', 'Стоит на месте (без действия) — ход закончится']]
      : [['Перемещение', 'Перемещение — потом можно одно действие'], ['Стоит на месте', 'Стоит на месте (без движения) — потом можно одно действие'],
         ['Активация фишки', 'Активация фишки без движения — ход закончится']];
    const echoes = d.echoes.filter((e) => e.status === 'open' || e.status === 'active');
    const echoOpts = [['', 'не заходил в Эхо'], ...echoes.flatMap((e) => [['passed:' + e.id, 'прошёл через «' + e.name + '»' + (e.status === 'active' && e.move_cost ? ' (−' + e.move_cost + ' Р.)' : '')],
      ['stopped:' + e.id, 'остановился в «' + e.name + '»' + (e.status === 'active' && e.move_cost ? ' (−' + e.move_cost + ' Р.)' : '')]])];
    modal('Ход отряда «' + sq.name + '»', (close) => h('div', { class: 'stack' },
      !t || t.phase !== 'actions' ? h('p', { class: 'muted small', style: 'margin:0' }, 'Сейчас не фаза действий — ход не запишется.') : null,
      h('p', { class: 'muted small', style: 'margin:0' }, tr.moved ? 'Отряд уже ' + (tr.text || '').toLowerCase() + '. Осталось одно действие: Нападение, Обмен (своими кнопками) или Активация фишки.'
        : 'Сначала движение, потом одно действие: Нападение, Обмен или Активация фишки. После действия ход отряда заканчивается.'),
      d.gifts.has('chernaya') ? h('p', { class: 'muted small', style: 'margin:0' }, 'Чёрная луна: движение до 4 гексов; за такт — один отряд; когда его ход закончен, ход переходит к следующему.') : null,
      form([
        { name: 'action', label: 'Что делает', type: 'select', options: opts },
        echoes.length && !tr.moved ? { name: 'echo', label: 'Эхо по пути', type: 'select', options: echoOpts } : null,
        { name: 'comment', label: 'Подробности (куда, какая фишка)' },
      ].filter(Boolean), 'Записать', async (v) => {
        const r = await act(() => call('api_squad_move', { p_squad: sq.id, p_action: v.action, p_comment: v.comment }), 'Ход записан');
        if (r === undefined) return;
        if (v.echo) {
          const [mode, id] = v.echo.split(':');
          await act(() => call('api_squad_echo', { p_squad: sq.id, p_echo: Number(id), p_mode: mode }),
            mode === 'stopped' ? 'Отряд стоит в Эхо' : 'Отмечен проход через Эхо');
        }
        close(); done();
      })));
  }

  // Отметить, что отряд прошёл через Эхо / стоит в нём / вышел (игрок — открытые Эхо, ведущий — любые).
  async function echoMark(d, sq) {
    let list = d.echoes.filter((e) => e.status === 'open' || e.status === 'active');
    if (isAdmin()) { try { list = await call('api_admin_echoes', { p_game: gameId }); } catch (e) { toast(e.message, true); return; } }
    const cur = sq.echo_id ? (list.find((e) => e.id === sq.echo_id) || { name: '#' + sq.echo_id }) : null;
    modal('Эхо: «' + sq.name + '»', (close) => h('div', { class: 'stack' },
      h('p', { class: 'muted small', style: 'margin:0' }, 'Эхо занимает часть карты. Его правила действуют на отряд, который прошёл через него (цена движения) или остановился в нём (запреты свойств — пока не уйдёт).'),
      cur ? h('div', { class: 'row' }, 'Сейчас стоит в «' + cur.name + '»', btn('Вышел из Эхо', () => act(() => call('api_squad_echo', { p_squad: sq.id, p_echo: null, p_mode: 'left' }),
        'Отряд вышел из Эхо', () => { close(); done(); }), 'small')) : null,
      list.length ? form([
        { name: 'e', label: 'Эхо', type: 'select', options: list.map((e) => [e.id, e.name + (e.status === 'hidden' ? ' (скрыто)' : '')]) },
        { name: 'mode', label: 'Что произошло', type: 'select', options: [['stopped', 'остановился в нём'], ['passed', 'прошёл через него']] },
      ], 'Отметить', (v) => act(() => call('api_squad_echo', { p_squad: sq.id, p_echo: Number(v.e), p_mode: v.mode }), 'Отмечено', () => { close(); done(); }))
        : h('p', { class: 'empty' }, 'Обнаруженных Эхо пока нет.')));
  }

  function attack(d, sq) {
    const targets = d.squads.filter((x) => x.strategist_id !== sq.strategist_id && !x.destroyed);
    modal('«' + sq.name + '» нападает', (close) => form([
      { name: 't', label: 'На кого (противник должен стоять вплотную)', type: 'select', options: targets.map((x) => [x.id, x.name + ' — ' + d.label(x.strategist_id)]) },
    ], 'Начать бой', (v) => act(() => call('api_battle_open', { p_attacker: sq.id, p_defender: Number(v.t) }), 'Бой начался',
      (id) => { close(); location.hash = '#/battle/' + id; })));
  }

  function useProperty(d, sq) {
    const opts = [];
    d.figsOf(sq.id).forEach(({ fig, sf }) => {
      if (!['ok', 'damaged'].includes(sf.state)) return;
      (fig.properties || []).forEach((p) => {
        const pr = cache.propByName[p];
        if (pr && pr.phase === 'Перемещение') opts.push([fig.id + '|' + p, fig.name + ': ' + p + (pr.cost ? ' (' + pr.cost + ' Р.)' : pr.cost_note ? ' (' + pr.cost_note + ' Р.)' : '') +
          (d.usedThisTurn.has(fig.id) ? ' — уже в этом ходу' : '')]);
      });
    });
    if (!opts.length) { toast('У фигур отряда нет свойств фазы Перемещения (боевые свойства — в бою).', true); return; }
    const echo = d.echoes.filter((e) => e.status === 'active' && e.blocked_properties && e.blocked_properties.length);
    modal('Свойство (Перемещение)', (close) => h('div', { class: 'stack' },
      echo.length ? h('p', { class: 'muted small', style: 'margin:0' }, 'Действуют Эхо: ' + echo.map((e) => e.name + ' (не работают: ' + e.blocked_properties.join(', ') + ')').join('; ')) : null,
      form([
        { name: 'p', label: 'Фигура и свойство', type: 'select', options: opts },
        { name: 'cost', label: 'Сколько Ресурсов (только для свойств с переменной ценой, например Перспективы)', type: 'number', min: 0 },
        { name: 'comment', label: 'Что сделано (цель, куда)' },
      ], 'Применить', (v) => {
        const [fid, prop] = v.p.split('|');
        return act(() => call('api_property_use', { p_squad: sq.id, p_figure: Number(fid), p_property: prop, p_cost: v.cost,
          p_battle: null, p_params: {}, p_comment: v.comment }),
        (r) => 'Применено' + (r && r.cost ? ', −' + r.cost + ' Р.' : '') + (r && r.roll ? ', бросок ' + r.roll : '') + (r && r.gain ? ', +1 Ресурс!' : ''),
        () => { close(); done(); });
      })));
  }

  function exchange(d, sq) {
    const others = d.squadsOf(sq.strategist_id).filter((x) => x.id !== sq.id && !x.destroyed);
    if (!others.length) { toast('Нужен второй свой отряд рядом.', true); return; }
    const pick = h('select', {}, others.map((x) => h('option', { value: x.id }, x.name)));
    const body = h('div', { class: 'stack' });
    const drawBody = () => {
      const b = d.squadById[Number(pick.value)];
      const items = [...d.figsOf(sq.id).map(({ fig }) => ({ kind: 'f', id: fig.id, name: glyph(fig.nominal) + ' ' + fig.name, side: 'a' })),
        ...d.figsOf(b.id).map(({ fig }) => ({ kind: 'f', id: fig.id, name: glyph(fig.nominal) + ' ' + fig.name, side: 'b' })),
        ...d.trophiesOf(sq.id).map((t) => ({ kind: 't', id: t.id, name: 'трофей «' + t.name + '»', side: 'a' })),
        ...d.trophiesOf(b.id).map((t) => ({ kind: 't', id: t.id, name: 'трофей «' + t.name + '»', side: 'b' }))];
      clear(body, h('p', { class: 'muted small', style: 'margin:0' }, 'Распределите фигуры и трофеи. Обмен — действие «' + sq.name + '»: его ход на этом закончится, второй отряд ходит дальше. Обмен не восстанавливает повреждённые фигуры. Если во втором отряде ничего не останется, отряды сольются.'),
        h('table', {}, h('thead', {}, h('tr', {}, h('th', { class: 'plain' }, ''), h('th', { class: 'plain' }, sq.name), h('th', { class: 'plain' }, b.name))),
          h('tbody', {}, items.map((it) => h('tr', {}, h('td', {}, it.name),
            ['a', 'b'].map((s) => h('td', {}, h('input', { type: 'radio', name: it.kind + it.id, value: s, checked: it.side === s, 'data-kind': it.kind, 'data-id': it.id }))))))),
        h('div', { class: 'row end' }, btn('Обменяться', () => {
          const get = (kind, side) => [...body.querySelectorAll('input[type=radio]:checked')].filter((i) => i.dataset.kind === kind && i.value === side).map((i) => Number(i.dataset.id));
          act(() => call('api_exchange', { p_a: sq.id, p_b: b.id, p_a_figures: get('f', 'a'), p_b_figures: get('f', 'b'), p_a_trophies: get('t', 'a'), p_b_trophies: get('t', 'b') }),
            'Обмен сделан', () => { document.getElementById('dialog').close(); done(); });
        }, 'primary')));
    };
    pick.addEventListener('change', drawBody);
    drawBody();
    modal('Обмен: «' + sq.name + '»', () => h('div', { class: 'stack' }, h('label', {}, 'С каким своим отрядом', pick), body));
  }

  function pay(d, sq) {
    const echo = d.echoes.filter((e) => e.status === 'active' && e.move_cost);
    modal('Оплатить Ресурсами', (close) => form([
      { name: 'amount', label: 'Сколько (есть ' + d.money(sq.strategist_id) + ')', type: 'number', value: echo.length ? echo[0].move_cost : 1, min: 1 },
      { name: 'reason', label: 'За что', value: echo.length ? 'Эхо «' + echo[0].name + '»: движение' : '' },
    ], 'Оплатить', (v) => act(() => call('api_pay', { p_squad: sq.id, p_amount: v.amount, p_reason: v.reason }), 'Оплачено', () => { close(); done(); })));
  }

  function rage(d, sq) {
    modal('Ярость «' + sq.name + '» (' + sq.rage + ')', (close) => form([
      { name: 'use', label: 'На что потратить 1 Ярость', type: 'select', options: [['move', '+1 к перемещению на этот ход'], ['remote', 'Активировать фишку издалека (в пределах Влияния)']] },
      { name: 'comment', label: 'Подробности' },
    ], 'Потратить', (v) => act(() => call('api_rage_spend', { p_squad: sq.id, p_use: v.use, p_battle: null, p_comment: v.comment }),
      'Ярость потрачена', () => { close(); done(); })));
    // +5 к Силе — на странице боя.
  }

  function states(d, sq) {
    modal('Состояние фигур: «' + sq.name + '»', () => h('div', { class: 'stack' },
      d.figsOf(sq.id).map(({ fig, sf }) => {
        const sel = h('select', {}, Object.entries(STATE_RU).map(([k, t]) => h('option', { value: k, selected: k === sf.state }, t)));
        return h('div', { class: 'row' }, h('span', { style: 'flex:1' }, glyph(fig.nominal) + ' ' + fig.name), sel,
          btn('✓', () => act(() => call('api_figure_state', { p_squad: sq.id, p_figure: fig.id, p_state: sel.value, p_comment: null }), 'Сохранено', done), 'small'));
      }),
      h('p', { class: 'muted small', style: 'margin:0' }, 'Отряд считается уничтоженным, когда в строю не осталось ни одной целой фигуры.')));
  }

  function trophies(d, sq) {
    const fighting = d.inBattle.has(sq.id);
    modal('Трофеи «' + sq.name + '»', (close) => h('div', { class: 'stack' },
      fighting ? h('p', { class: 'muted small', style: 'margin:0' }, 'Отряд в бою: во время боя трофей выкинуть нельзя.') : null,
      d.trophiesOf(sq.id).map((t) => {
        const b = btn('Выкинуть', () => act(() => call('api_trophy_drop', { p_trophy: t.id }), 'Трофей выброшен', () => { close(); done(); }), 'small danger');
        if (fighting) { b.disabled = true; b.title = 'Во время боя трофей выкинуть нельзя'; }
        return h('div', { class: 'row' },
          h('div', { style: 'flex:1' }, h('b', {}, t.name), t.description ? h('div', { class: 'muted small' }, t.description) : null), b);
      })));
  }

  function death(d, sq) {
    const figs = d.figsOf(sq.id).filter(({ sf }) => !sf.borrowed);
    modal('Отряд «' + sq.name + '» уничтожен', (close) => h('div', { class: 'stack' },
      h('p', { class: 'small', style: 'margin:0' }, 'В конце игры одна фигура уничтоженного отряда погибает. Выбирает владелец отряда; если решить не удаётся — жребий.'),
      figs.map(({ fig }) => btn('Погибает ' + glyph(fig.nominal) + ' ' + fig.name, () => act(() => call('api_squad_death', { p_squad: sq.id, p_figure: fig.id }),
        'Записано', () => { close(); done(); }))),
      btn('Жребий', () => act(() => call('api_squad_death', { p_squad: sq.id, p_figure: null }),
        (id) => 'Жребий: погибает «' + (d.figById[id] || {}).name + '»', () => { close(); done(); }), 'primary')));
  }

  function giveTrophy(sq) {
    modal('Трофей для «' + sq.name + '»', (close) => form([
      { name: 'name', label: 'Название', required: true },
      { name: 'description', label: 'Эффект (текстом)', type: 'textarea' },
      { name: 's', label: '+ Сила отряду', type: 'number', value: 0 },
      { name: 'l', label: '+ Лояльность', type: 'number', value: 0 },
      { name: 'v', label: '+ Влияние', type: 'number', value: 0 },
    ], 'Выдать', (v) => act(() => call('api_admin_trophy_give', { p_squad: sq.id, p_name: v.name, p_description: v.description, p_s: v.s, p_l: v.l, p_v: v.v }),
      'Трофей выдан', () => { close(); done(); })));
  }

  function setRage(sq) {
    modal('Ярость «' + sq.name + '»', (close) => form([
      { name: 'rage', label: 'Сколько Ярости', type: 'number', value: sq.rage, min: 0 },
      { name: 'comment', label: 'Основание' },
    ], 'Сохранить', (v) => act(() => call('api_admin_rage', { p_squad: sq.id, p_rage: v.rage ?? 0, p_comment: v.comment }), 'Сохранено', () => { close(); done(); })));
  }

  function moveFigure(d, sq) {
    modal('Фигуру в другой отряд', (close) => form([
      { name: 'f', label: 'Фигура', type: 'select', options: d.figsOf(sq.id).map(({ fig }) => [fig.id, fig.name]) },
      { name: 'to', label: 'В отряд (Подкуп, Перспективы…)', type: 'select', options: d.squads.filter((x) => x.id !== sq.id).map((x) => [x.id, x.name + ' — ' + d.label(x.strategist_id)]) },
      { name: 'comment', label: 'Основание' },
    ], 'Переместить', (v) => act(() => call('api_admin_move_figure', { p_from: sq.id, p_to: Number(v.to), p_figure: Number(v.f), p_comment: v.comment }),
      'Фигура перемещена', () => { close(); done(); })));
  }

  function setStatus(d, status) {
    const text = { running: 'Начать игру? Составы отрядов зафиксируются.', closed: 'Закончить игру? Нужно, чтобы были выбраны погибшие фигуры, разделены общие кошельки и решена судьба трофеев.', draft: 'Вернуть игру в сбор отрядов?' }[status];
    confirmDo(text, () => call('api_admin_game', { p_id: gameId, p_title: d.game.title, p_starts_at: d.game.starts_at, p_status: status }), 'Готово');
  }
  function renameGame(d) {
    const local = d.game.starts_at ? new Date(new Date(d.game.starts_at).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : '';
    modal('Игра', (close) => form([
      { name: 'title', label: 'Название', required: true, value: d.game.title },
      { name: 'starts', label: 'Начало', type: 'datetime-local', value: local },
    ], 'Сохранить', (v) => act(() => call('api_admin_game', { p_id: gameId, p_title: v.title, p_starts_at: v.starts ? new Date(v.starts).toISOString() : null, p_status: d.game.status }),
      'Сохранено', () => { close(); done(); })));
  }
  function addStrategist(d) {
    const inGame = new Set(d.members.map((m) => m.player_id));
    const opts = cache.players.filter((p) => !p.is_admin && !inGame.has(p.id)).map((p) => [p.id, p.name]);
    if (!opts.length) { toast('Все персонажи уже в игре.', true); return; }
    modal('Добавить стратега', (close) => h('div', { class: 'stack' },
      h('p', { class: 'muted small', style: 'margin:0' }, 'Персонаж появится в игре; отряды за него можно собрать кнопкой «+ Отряд» у его имени.'),
      form([{ name: 'p', label: 'Персонаж', type: 'select', options: opts }], 'Добавить',
        (v) => act(() => call('api_admin_join', { p_game: gameId, p_player: Number(v.p) }), 'Стратег добавлен', () => { close(); done(); }))));
  }

  function pairAdmin(d) {
    const opts = cache.players.filter((p) => !p.is_admin).map((p) => [p.id, p.name]);
    modal('Напарники', (close) => form([
      { name: 'a', label: 'Первый', type: 'select', options: opts },
      { name: 'b', label: 'Второй', type: 'select', options: opts },
    ], 'Сделать напарниками', (v) => act(() => call('api_admin_pair', { p_game: gameId, p_a: Number(v.a), p_b: Number(v.b) }),
      'Пара оформлена, Ресурсы слиты', () => { close(); done(); })));
  }
  function splitWallet(d, s) {
    const members = d.membersOf(s.id);
    modal('Разделить кошелёк (' + s.wallet + ')', (close) => form(members.map((m, i) => ({
      name: 'p' + m, label: pname(m), type: 'number', min: 0, value: i === 0 ? Math.ceil(s.wallet / 2) : Math.floor(s.wallet / 2),
    })), 'Разделить', (v) => act(() => call('api_admin_split_wallet', { p_strategist: s.id,
      p_shares: Object.fromEntries(members.map((m) => [String(m), v['p' + m] ?? 0])) }), 'Разделено', () => { close(); done(); })));
  }
  async function echoesAdmin(d) {
    let all;
    try { all = await call('api_admin_echoes', { p_game: gameId }); } catch (e) { toast(e.message, true); return; }
    const STATUS = [['hidden', 'скрыто'], ['open', 'открыто (видно всем)'], ['active', 'действует'], ['ended', 'закончилось']];
    const edit = (e) => modal(e ? 'Эхо «' + e.name + '»' : 'Новое Эхо', (close) => form([
      { name: 'name', label: 'Название', required: true, value: e && e.name },
      { name: 'description', label: 'Правила (текстом)', type: 'textarea', value: e && e.description },
      { name: 'status', label: 'Состояние', type: 'select', options: STATUS, value: e ? e.status : 'hidden' },
      { name: 'end', label: 'Сколько длится / условие окончания', value: e && e.end_condition },
      { name: 'blocked', label: 'Какие свойства не работают (Ctrl — несколько)', type: 'select', multiple: true,
        options: cache.properties.map((p) => p.name), value: e ? e.blocked_properties : [] },
      { name: 'move', label: 'Движение стоит Ресурсов', type: 'number', min: 0, value: e ? e.move_cost : 0 },
    ], 'Сохранить', (v) => act(() => call('api_admin_echo', { p_id: e ? e.id : null, p_game: gameId, p_name: v.name, p_description: v.description,
      p_status: v.status, p_end_condition: v.end, p_blocked: v.blocked, p_move_cost: v.move ?? 0 }), 'Эхо сохранено', () => { close(); done(); })));
    modal('Эхо Расколотого мира (видит только ведущий)', () => h('div', { class: 'stack' },
      all.length ? all.map((e) => h('div', { class: 'row' }, h('b', { style: 'flex:1' }, e.name),
        badge(STATUS.find((s) => s[0] === e.status)[1], e.status === 'hidden' ? '' : e.status === 'active' ? 'bad' : 'ok'),
        btn('Изменить', () => edit(e), 'small'))) : h('p', { class: 'empty' }, 'Эхо ещё не заведены (по правилам их 5).'),
      h('div', { class: 'row end' }, btn('+ Эхо', () => edit(null), 'primary'))));
  }
}

// ───────── загрузка данных игры ─────────
async function load(gameId) {
  await loadPlayers(true);   // Ресурсы и бонусы игроков меняются по ходу игры
  const byGame = (t, cols, order = (q) => q.order('id')) =>
    rowsAll(t, (q) => order(q.eq('game_id', gameId)), cols);
  const [games, gifts, strategists, members, squads, sfs, totals, moon, turns, battles, echoes, events, figures, owners, conflicts, kept, lineup, propertyUses] = await Promise.all([
    rows('games', (q) => q.eq('id', gameId)),
    byGame('game_gifts', undefined, (q) => q.order('gift')),
    byGame('strategists'), byGame('strategist_members', undefined, (q) => q.order('strategist_id').order('player_id')),
    byGame('squads'), byGame('squad_figures', undefined, (q) => q.order('squad_id').order('figure_id')),
    byGame('squad_totals', undefined, (q) => q.order('squad_id')),
    byGame('squad_moon', undefined, (q) => q.order('squad_id')),
    rows('turns', (q) => q.eq('game_id', gameId).order('number', { ascending: false }).limit(1)),
    byGame('battles', undefined, (q) => q.order('id', { ascending: false })),
    byGame('echoes_public'),
    rows('events', (q) => q.eq('game_id', gameId).order('at', { ascending: false }).order('id', { ascending: false }).limit(200)),
    rowsAll('figures', (q) => q.order('name')),
    rowsAll('figure_owners', (q) => q.order('figure_id').order('player_id')),
    rowsAll('figure_conflicts', (q) => q.eq('game_id', gameId).order('figure_id')),
    rowsAll('trophies', (q) => q.eq('status', 'kept').order('id')),
    // история составов: какие фигуры когда-либо стояли в отрядах игры (для статистики)
    rowsAll('events', (q) => q.eq('game_id', gameId).in('kind', ['squad_save', 'figure_move']).order('at').order('id'),
      'kind, squad_id, figure_id, data, at, reverted'),
    rowsAll('events', (q) => q.eq('game_id', gameId).eq('kind', 'property_use').order('at').order('id'),
      'figure_id, data, reverted'),
  ]);
  const squadIds = squads.map((s) => s.id);
  const trophies = squadIds.length ? await rowsAll('trophies', (q) => q.in('squad_id', squadIds).order('id')) : [];
  const turn = turns[0] || null;
  const moves = turn ? await rowsAll('squad_moves', (q) => q.eq('turn_id', turn.id).order('squad_id')) : [];
  const figById = Object.fromEntries(figures.map((f) => [f.id, f]));
  const ownersOf = {};
  owners.forEach((o) => { (ownersOf[o.figure_id] = ownersOf[o.figure_id] || []).push(o.player_id); });
  const membersOf = (sid) => members.filter((m) => m.strategist_id === sid).map((m) => m.player_id);
  const label = (sid) => membersOf(sid).map(pname).join(' и ') || ('стратег #' + sid);
  // Порядок хода как в базе (turn_order): по инициативе; при Чёрной луне места 1–3 — только
  // стратегам с 1–2 отрядами, остальные — после них.
  const byInit = strategists.slice().sort((a, b) => ((b.initiative ?? -1e9) - (a.initiative ?? -1e9)) || a.id - b.id);
  const nSquads = (sid) => squads.filter((s) => s.strategist_id === sid).length;
  const giftSet = new Set(gifts.map((g) => g.gift));
  const shifted = new Set();
  let order = byInit;
  if (giftSet.has('chernaya')) {
    const top = byInit.filter((s) => nSquads(s.id) < 3).slice(0, 3);
    order = top.concat(byInit.filter((s) => !top.includes(s)));
    byInit.forEach((s, i) => { if (nSquads(s.id) >= 3 && order.indexOf(s) > i) shifted.add(s.id); });
  }
  const mine = session.me ? members.find((m) => m.player_id === session.me.id) : null;
  const squadById = Object.fromEntries(squads.map((s) => [s.id, s]));
  const d = {
    game: games[0] || null, gifts: giftSet, strategists, members, squads, turn, battles, echoes, events,
    figures, figById, ownersOf, conflicts, kept, trophies: trophies.filter((t) => t.status === 'active'), squadById,
    order, shifted, membersOf, label,
    echoById: Object.fromEntries(echoes.map((e) => [e.id, e])),
    inBattle: new Set(battles.filter((b) => b.status === 'open').flatMap((b) => [b.attacker, b.defender])),
    // ход отряда в текущем ходу: { text, moved, finished }
    turnOf: Object.fromEntries(moves.map((m) => [m.squad_id, { text: m.action + (giftSet.has('chernaya') ? ' (такт ' + m.tact + ')' : ''),
      moved: !!m.movement, finished: !!m.act, tact: m.tact }])),
    myStrategist: mine ? strategists.find((s) => s.id === mine.strategist_id) : null,
    squadsOf: (sid) => squads.filter((s) => s.strategist_id === sid),
    figsOf: (sqid) => sfs.filter((x) => x.squad_id === sqid).map((sf) => ({ sf, fig: figById[sf.figure_id] })).filter((x) => x.fig)
      .sort((a, b) => (cache.nominals.find((n) => n.name === b.fig.nominal).rank - cache.nominals.find((n) => n.name === a.fig.nominal).rank)),
    trophiesOf: (sqid) => trophies.filter((t) => t.squad_id === sqid && t.status === 'active'),
    totals: Object.fromEntries(totals.map((t) => [t.squad_id, t])),
    moon: Object.fromEntries(moon.map((m) => [m.squad_id, m])),
    moves: Object.fromEntries(moves.map((m) => [m.squad_id, m.action + (m.act ? '' : ' …') + (giftSet.has('chernaya') ? ' (такт ' + m.tact + ')' : '')])),
    movesList: moves,
    lineup: lineup.filter((e) => !e.reverted),
    allSquadFigures: sfs,
    // фигуры, уже применявшие свойство фазы Перемещения в этом ходу (раз в ход на фигуру)
    usedThisTurn: new Set(turn ? propertyUses.filter((e) => !e.reverted && e.data && e.data.phase === 'Перемещение'
      && Number(e.data.turn) === turn.number).map((e) => e.figure_id) : []),
    squadName: (id) => (squadById[id] ? squadById[id].name : '#' + id),
    money: (sid) => {
      const s = strategists.find((x) => x.id === sid);
      if (s && s.wallet != null) return s.wallet;
      const m = membersOf(sid);
      return m.length ? ((cache.playerById[m[0]] || {}).resources ?? 0) : 0;
    },
  };
  d.maps = { figures: figById, squads: squadById, strategists: Object.fromEntries(strategists.map((s) => [s.id, label(s.id)])) };
  return d;
}
