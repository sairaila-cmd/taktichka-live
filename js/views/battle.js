// Помощник боя: очередь фигур, свойства по фазам, Сила, броски, исход; вживую у обоих игроков.
import { rows, rowsAll, call, cache, session, isAdmin, watch } from '../api.js?v=202610151535';
import { h, clear, btn, badge, act, toast, STATE_RU, GIFT_RU } from '../ui.js?v=202610151535';
import { glyph, pname, figLink } from './common.js?v=202610151535';

const SIDE_RU = { attacker: 'нападает', defender: 'защищается' };
const HINTS = {
  'Добивание': 'Противник убирает одну свою повреждённую фигуру в отбой (выбирает хозяин отряда).',
  'Пожирание': 'Противник убирает повреждённую фигуру в отбой; если ушла — восстановите любые свои повреждённые фигуры.',
  'Лечение': 'Отметьте восстановленные фигуры отряда как «цела».',
  'Подкуп': 'Ведущий переносит выбранную пешку или коня противника в этот отряд (кнопка «Фигуру в другой отряд» на странице игры), подкупивший — в резерв.',
  'СуперПодкуп': 'Ведущий переносит выбранную фигуру противника (до ладьи) в этот отряд, подкупивший — в резерв.',
  'Фаталити': 'Противник убирает выбранную фигуру на свалку.',
  'Множественность': 'Если на кубике чёт — фигура выжила и остаётся в отряде.',
  'Quid pro quo': 'Замените повреждённую фигуру: Обмен с другим отрядом или ведущий — из Резерва/Боевой Колоды.',
};

export default async function battleView(root, battleId) {
  battleId = Number(battleId);
  let d = await load(battleId);
  draw();
  let timer = null;
  const schedule = () => { clearTimeout(timer); timer = setTimeout(async () => { try { d = await load(battleId); draw(); } catch (e) { toast(e.message, true); } }, 300); };
  const unwatch = d.battle ? watch('battle' + battleId, [
    ['battle_actions', 'battle_id=eq.' + battleId], ['battles', 'id=eq.' + battleId],
    ['squad_figures', 'squad_id=eq.' + d.battle.attacker], ['squad_figures', 'squad_id=eq.' + d.battle.defender],
    ['squads', 'id=eq.' + d.battle.attacker], ['squads', 'id=eq.' + d.battle.defender], ['trophies'],
  ], schedule) : () => {};
  return () => { unwatch(); clearTimeout(timer); };

  async function done() { d = await load(battleId); draw(); }

  function draw() {
    if (!d.battle) { clear(root, h('section', { class: 'card' }, h('h2', {}, 'Бой не найден'))); return; }
    const b = d.battle;
    const r = d.result;
    const open = b.status === 'open';
    clear(root,
      h('p', { class: 'small', style: 'margin:0' }, h('a', { href: '#/game/' + b.game_id }, '← ' + (d.game ? d.game.title : 'к игре'))),
      h('h1', { class: 'page-title' }, '«' + d.sq.attacker.name + '» нападает на «' + d.sq.defender.name + '»'),
      h('div', { class: 'row', style: 'justify-content:center' },
        open ? badge('бой идёт · фаза: ' + r.phase, 'ok') : badge('бой окончен'),
        [...d.gifts].map((g) => badge('☾ ' + GIFT_RU[g].split(' — ')[0], 'moon')),
        ['attacker', 'defender'].map((s) => d.echoOf(s) ? badge('«' + d.sq[s].name + '» в Эхо «' + d.echoOf(s).name + '»' +
          ((d.echoOf(s).blocked_properties || []).length ? ': не работают ' + d.echoOf(s).blocked_properties.join(', ') : ''), 'bad') : null)),
      h('div', { class: 'versus' }, sidePanel('attacker'), h('div', { class: 'vs' }, '⚔'), sidePanel('defender')),
      open ? needCard() : resultCard(),
      queueCard(),
      hintsCard(),
      isAdmin() ? adminCard() : null);
  }

  function canAct(side) {
    if (!session.me) return false;
    return isAdmin() || d.members[side].includes(session.me.id);
  }

  function sidePanel(side) {
    const sq = d.sq[side];
    const st = d.result.strength[side];
    const roll = d.result.rolls[side];
    const rageUsed = d.actions.some((a) => a.kind === 'rage' && a.squad_id === sq.id && (a.params || {}).use === 'power');
    const open = d.battle.status === 'open';
    return h('div', { class: 'side ' + side },
      h('div', { class: 'row', style: 'justify-content: space-between' },
        h('b', {}, sq.name), h('span', { class: 'small muted' }, SIDE_RU[side] + ' · ' + d.label[side])),
      h('div', { class: 'row', style: 'align-items: baseline' },
        h('span', { class: 'power' }, st ? st.total : '—'), h('span', { class: 'muted small' }, 'Сила'),
        roll ? h('span', { class: 'row', style: 'margin-left:auto' }, h('span', { class: 'die', title: roll.manual ? 'введено ведущим' : 'бросок базы' }, roll.final),
          roll.reroll != null ? h('span', { class: 'muted small' }, 'было ' + roll.value + ', переброс ' + roll.reroll) : null) : null),
      st ? h('ul', { class: 'parts' }, st.parts.map((p) => h('li', {}, h('span', {}, p.label), h('span', { class: 'num' }, (p.value > 0 ? '+' : '') + p.value)))) : h('p', { class: 'muted small', style: 'margin:0' }, 'Сила считается в фазе Силы.'),
      d.gifts.has('alaya') ? h('div', { class: 'row small' }, badge('Ярость ' + (sq.rage || 0), sq.rage ? 'bad' : ''),
        open && canAct(side) && sq.rage > 0 && !rageUsed && !d.result.outcome ? btn('Потратить Ярость: +5 к Силе', () =>
          act(() => call('api_rage_spend', { p_squad: sq.id, p_use: 'power', p_battle: battleId, p_comment: null }), 'Ярость: +5 к Силе', done), 'small') : null,
        rageUsed ? badge('+5 от Ярости взято', 'moon') : null) : null,
      h('ul', { class: 'figs' }, d.figs[side].map((f) => h('li', { class: 'st-' + f.state },
        h('span', {}, glyph(f.nominal) + ' ', figLink(f)), h('span', { class: 'muted num' }, f.s + '/' + f.l + '/' + f.v),
        h('span', { class: 'muted' }, (f.properties || []).join(' / ')),
        f.state !== 'ok' ? badge(STATE_RU[f.state], 'warn') : null,
        canAct(side) ? stateSelect(sq.id, f) : null))),
      d.trophies[side].length ? h('div', { class: 'small muted' }, 'Трофеи: ' + d.trophies[side].map((t) => '«' + t.name + '»').join(', ')) : null);
  }

  function stateSelect(squadId, f) {
    const sel = h('select', { class: 'small', 'aria-label': 'Состояние ' + f.name, style: 'padding: 1px 4px' },
      Object.entries(STATE_RU).map(([k, t]) => h('option', { value: k, selected: k === f.state }, t)));
    sel.addEventListener('change', () => act(() => call('api_figure_state', { p_squad: squadId, p_figure: f.id, p_state: sel.value, p_comment: 'Бой #' + battleId }),
      'Состояние: ' + STATE_RU[sel.value], done));
    return sel;
  }

  function needCard() {
    const r = d.result;
    const n = r.need;
    const items = [];
    if (n && n.type === 'decide') {
      const e = r.entries.find((x) => x.key === n.key);
      items.push(h('p', { style: 'margin:0' }, 'Ход фигуры ', h('b', {}, glyph(e.figure.nominal) + ' ' + e.figure.name),
        ' (' + d.sq[e.side].name + ', фаза ' + e.phase + ').'));
      if (canAct(e.side)) {
        e.options.forEach((o) => items.push(optionRow(e, o)));
        items.push(h('div', { class: 'row' }, btn('Пропустить ход фигуры', () => act(() => call('api_battle_step', {
          p_battle: battleId, p_kind: 'skip', p_squad: d.sq[e.side].id, p_figure: e.figure.id, p_params: { phase: e.phase } }), 'Пропущено', done))));
      } else items.push(h('p', { class: 'muted' }, 'Решает ' + d.label[e.side] + '.'));
    } else if (n && n.type === 'roll') {
      items.push(h('p', { style: 'margin:0' }, 'Фаза Риска: каждый бросает d10 и прибавляет к Силе. «10» — автопобеда.'));
      n.sides.forEach((side) => {
        const row = [h('span', { style: 'min-width: 10rem' }, d.sq[side].name + ':')];
        if (canAct(side)) {
          row.push(btn('Бросить d10', () => act(() => call('api_roll', { p_game: d.battle.game_id, p_battle: battleId, p_squad: d.sq[side].id, p_purpose: 'risk', p_manual: null }),
            (v) => 'Выпало ' + v, done), 'primary'));
        } else row.push(h('span', { class: 'muted' }, 'ждём броска'));
        if (isAdmin()) row.push(manualRoll((v) => call('api_roll', { p_game: d.battle.game_id, p_battle: battleId, p_squad: d.sq[side].id, p_purpose: 'risk', p_manual: v })));
        items.push(h('div', { class: 'row' }, row));
      });
    } else if (n && n.type === 'damage') {
      items.push(h('p', { style: 'margin:0' }, outcomeText(r.outcome) + ' Проигравший выбирает, какую фигуру повредить.'));
      if (canAct(n.side)) {
        items.push(h('div', { class: 'row' }, n.candidates.map((f) => btn('Повредить ' + glyph(f.nominal) + ' ' + f.name, () => act(() => call('api_battle_step', {
          p_battle: battleId, p_kind: 'damage', p_squad: d.sq[n.side].id, p_figure: f.id, p_params: {} }), 'Фигура повреждена', done)))));
      } else items.push(h('p', { class: 'muted' }, 'Выбирает ' + d.label[n.side] + '.'));
    } else {
      items.push(h('div', { class: 'outcome' }, outcomeText(r.outcome)));
      if (r.outcome && r.outcome.totals) items.push(h('p', { class: 'muted small', style: 'margin:0; text-align:center' },
        'Итог: ' + r.outcome.totals.attacker + ' против ' + r.outcome.totals.defender));
      if (canAct('attacker') || isAdmin()) {
        items.push(h('div', { class: 'row', style: 'justify-content:center' }, btn('Завершить бой и записать итог', () => {
          const w = r.outcome ? r.outcome.winner : null;
          return act(() => call('api_battle_close', { p_battle: battleId, p_winner: w ? d.sq[w].id : null, p_result: {
            reason: r.outcome && r.outcome.reason, totals: r.outcome && r.outcome.totals,
            strength: { attacker: r.strength.attacker && r.strength.attacker.total, defender: r.strength.defender && r.strength.defender.total },
            rolls: { attacker: r.rolls.attacker && r.rolls.attacker.final, defender: r.rolls.defender && r.rolls.defender.final } } }),
          'Бой записан', done);
        }, 'primary')));
      } else items.push(h('p', { class: 'muted small', style: 'text-align:center; margin:0' }, 'Записать итог может нападающий или ведущий.'));
    }
    return h('section', { class: 'card', style: 'border-color: var(--moon)' }, h('h2', {}, n ? 'Сейчас' : 'Исход'), items);
  }

  function optionRow(e, o) {
    if (!o.available) return h('div', { class: 'row small muted' }, '✕ ' + o.property + ': ' + o.reason);
    const extras = [];
    let amount = null, target = null, manual = null;
    if (o.amount) { amount = h('select', {}, o.amount.map((n) => h('option', { value: n }, n + ' Р. → +' + 4 * n))); extras.push(amount); }
    if (o.targets) {
      target = h('select', {}, o.targets.map((t) => h('option', { value: t.id }, glyph(t.nominal) + ' ' + t.name + ' (С ' + t.s + ')')));
      extras.push(o.targets.length ? target : h('span', { class: 'muted' }, 'нет целей'));
    }
    if (isAdmin() && ['Шпионаж', 'Множественность'].includes(o.property)) {
      manual = h('input', { type: 'number', min: 1, max: 10, placeholder: 'кубик', title: 'Живой кубик (только ведущий); пусто — бросит сайт', style: 'width: 5rem' });
      extras.push(manual);
    }
    const cost = o.cost === null ? '' : o.cost ? ' (' + o.cost + ' Р.)' : '';
    const desc = cache.propByName[o.property] ? cache.propByName[o.property].description : '';
    return h('div', { class: 'stack' },
      h('div', { class: 'row' }, btn('Применить «' + o.property + '»' + cost, () => {
        const params = { phase: e.phase };
        if (target && target.value) params.target = Number(target.value);
        if (manual && manual.value) params.manual_roll = Number(manual.value);
        return act(() => call('api_property_use', { p_squad: d.sq[e.side].id, p_figure: e.figure.id, p_property: o.property,
          p_cost: amount ? Number(amount.value) : null, p_battle: battleId, p_params: params, p_comment: null }),
        (res) => 'Применено' + (res && res.cost ? ', −' + res.cost + ' Р.' : '') + (res && res.roll ? ', бросок ' + res.roll : ''), done);
      }, 'primary'), extras),
      desc ? h('div', { class: 'prop-desc' }, desc) : null);
  }

  function manualRoll(fn) {
    const inp = h('input', { type: 'number', min: 1, max: 10, placeholder: '1–10', style: 'width: 5rem', 'aria-label': 'Бросок вручную' });
    return h('span', { class: 'row' }, inp, btn('Ввести (ведущий)', () => act(() => fn(Number(inp.value)), 'Бросок записан', done), 'small'));
  }

  function outcomeText(o) {
    if (!o) return '';
    if (!o.winner) return 'Ничья — ' + o.reason + '.';
    return 'Победил «' + d.sq[o.winner].name + '» — ' + o.reason + '.';
  }

  function resultCard() {
    const b = d.battle;
    const res = b.result || {};
    const winSide = b.winner === d.sq.attacker.id ? 'attacker' : b.winner === d.sq.defender.id ? 'defender' : null;
    const items = [h('div', { class: 'outcome' }, winSide ? 'Победил «' + d.sq[winSide].name + '»' : 'Ничья'),
      res.reason ? h('p', { class: 'muted small', style: 'text-align:center; margin:0' }, res.reason + (res.totals ? ' · ' + res.totals.attacker + ' против ' + res.totals.defender : '')) : null];
    if (winSide) {
      const lose = winSide === 'attacker' ? 'defender' : 'attacker';
      const taken = d.actionsTook;
      const room = d.trophies[winSide].length < 3;
      if (d.trophies[lose].length && canAct(winSide) && !taken) {
        items.push(h('p', { class: 'small', style: 'margin:0' }, room ? 'Можно забрать у побеждённого один трофей:' : 'Забрать трофей нельзя: у отряда уже 3 трофея.'));
        if (room) items.push(h('div', { class: 'row' }, d.trophies[lose].map((t) => btn('Забрать «' + t.name + '»', () =>
          act(() => call('api_trophy_take', { p_battle: battleId, p_trophy: t.id }), 'Трофей забран', done)))));
      }
      if (taken) items.push(h('p', { class: 'muted small', style: 'margin:0; text-align:center' }, 'Трофей за этот бой уже забран.'));
      if (d.gifts.has('alaya')) items.push(h('p', { class: 'muted small', style: 'margin:0; text-align:center' }, 'Алая луна: проигравший получил +1 Ярость, победитель потерял накопленную.'));
    }
    items.push(h('div', { class: 'row', style: 'justify-content:center' },
      btn('Вернуться к игре', () => { location.hash = '#/game/' + b.game_id; }, 'primary')));
    return h('section', { class: 'card' }, h('h2', {}, 'Итог боя'), items);
  }

  function queueCard() {
    const r = d.result;
    const groups = ['Условие', 'Сила', 'Риск', 'Ущерб'].map((ph) => {
      const list = r.entries.filter((e) => e.phase === ph);
      return h('div', { class: 'stack' }, h('div', { class: 'phase-head' }, ph),
        list.length ? h('ol', { class: 'queue' }, list.map((e) => h('li', { class: e.status },
          h('div', { class: 'row' }, h('span', { class: 'who-side ' + e.side }, d.sq[e.side].name),
            h('b', {}, glyph(e.figure.nominal) + ' ', figLink(e.figure)), h('span', { class: 'muted small' }, 'Л ' + e.figure.l),
            h('span', { class: 'small' }, e.properties.join(' / ')),
            e.status === 'done' ? badge('применено' + (e.action && e.action.cost ? ' · ' + e.action.cost + ' Р.' : '') + (e.action && e.action.roll ? ' · бросок ' + e.action.roll : ''), 'ok') :
            e.status === 'current' ? badge('ходит сейчас', 'moon') : e.status === 'skipped' ? badge('пропуск') :
            e.status === 'waiting' ? badge('ждёт') : badge('недоступно')),
          e.status === 'unavailable' && e.reason ? h('div', { class: 'muted small' }, e.reason) : null))) : h('p', { class: 'empty' }, 'В этой фазе никто не действует.'));
    });
    return h('section', { class: 'card' }, h('h2', {}, 'Очередь фигур'),
      h('p', { class: 'muted small', style: 'margin:0' }, 'По фазам; внутри фазы — по номиналу, затем по Лояльности, затем нападающий. Каждая фигура действует не больше одного раза за бой.'),
      groups,
      r.log.length ? h('details', {}, h('summary', {}, 'Ход боя'), h('ul', { class: 'small' }, r.log.map((l) => h('li', {}, l)))) : null);
  }

  function hintsCard() {
    const done = d.result.entries.filter((e) => e.status === 'done' && HINTS[e.action.property]);
    if (!done.length || d.battle.status !== 'open') return null;
    return h('section', { class: 'card' }, h('h2', {}, 'Что отметить вручную'),
      done.map((e) => h('div', { class: 'small' }, h('b', {}, e.action.property + ' (' + d.sq[e.side].name + '): '), HINTS[e.action.property],
        e.action.roll ? ' Бросок: ' + e.action.roll + (e.action.roll % 2 === 0 ? ' (чёт).' : ' (нечет).') : '')),
      h('p', { class: 'muted small', style: 'margin:0' }, 'Состояние фигур меняется списками у фигур отряда выше.'));
  }

  function adminCard() {
    return h('section', { class: 'card' }, h('h2', {}, 'Шаги боя (ведущему)'),
      d.actions.length ? h('ul', { class: 'log' }, d.actions.map((a) => h('li', {},
        h('span', { class: 'muted' }, '#' + a.id),
        h('div', { class: 'row' }, h('span', { style: 'flex:1' }, describeAction(a)),
          btn('Отменить', () => act(() => call('api_admin_battle_undo', { p_action: a.id }), 'Шаг отменён (Ресурсы возвращены)', done), 'small danger'))))) :
        h('p', { class: 'empty' }, 'Шагов пока нет.'));
  }

  function describeAction(a) {
    const side = a.squad_id === d.sq.attacker.id ? 'attacker' : 'defender';
    const fig = d.figById[a.figure_id];
    const who = d.sq[side].name + (fig ? ': ' + fig.name : '');
    switch (a.kind) {
      case 'property': return who + ' — «' + a.property + '»' + (a.cost ? ', ' + a.cost + ' Р.' : '') + (a.roll ? ', бросок ' + a.roll : '');
      case 'skip': return who + ' — пропуск (' + ((a.params || {}).phase || '') + ')';
      case 'roll': return d.sq[side].name + ' — бросок ' + a.roll + (a.manual ? ' (вручную)' : '');
      case 'damage': return who + ' — повреждена';
      case 'rage': return d.sq[side].name + ' — Ярость: +5 к Силе';
      default: return who + ' — ' + a.kind;
    }
  }
}

async function load(battleId) {
  const [battles] = await Promise.all([rows('battles', (q) => q.eq('id', battleId))]);
  const battle = battles[0];
  if (!battle) return { battle: null };
  const ids = [battle.attacker, battle.defender];
  const [squads, sfs, trophies, moon, actions, gifts, echoes, members, games, takes] = await Promise.all([
    rows('squads', (q) => q.in('id', ids)), rows('squad_figures', (q) => q.in('squad_id', ids)),
    rows('trophies', (q) => q.in('squad_id', ids).eq('status', 'active')), rows('squad_moon', (q) => q.in('squad_id', ids)),
    rowsAll('battle_actions', (q) => q.eq('battle_id', battleId).order('id')),
    rows('game_gifts', (q) => q.eq('game_id', battle.game_id)),
    rows('echoes_public', (q) => q.eq('game_id', battle.game_id).eq('status', 'active')),
    rows('strategist_members', (q) => q.eq('game_id', battle.game_id)),
    rows('games', (q) => q.eq('id', battle.game_id)),
    rowsAll('events', (q) => q.eq('kind', 'trophy_take').eq('game_id', battle.game_id).order('id'), 'data'),
  ]);
  const figures = sfs.length ? await rows('figures', (q) => q.in('id', sfs.map((s) => s.figure_id))) : [];
  const figById = Object.fromEntries(figures.map((f) => [f.id, f]));
  const sq = { attacker: squads.find((s) => s.id === battle.attacker), defender: squads.find((s) => s.id === battle.defender) };
  const gifts2 = new Set(gifts.map((g) => g.gift));
  // Эхо — зона: запреты действуют только на отряд, который стоит в действующем Эхо.
  const echoOf = (s) => echoes.find((e) => e.id === sq[s].echo_id) || null;
  const echoBlocked = [];
  const figs = {}, trophiesBy = {}, membersBy = {}, label = {};
  ['attacker', 'defender'].forEach((side) => {
    figs[side] = sfs.filter((x) => x.squad_id === sq[side].id && figById[x.figure_id])
      .map((x) => ({ ...figById[x.figure_id], state: x.state, borrowed: x.borrowed }));
    trophiesBy[side] = trophies.filter((t) => t.squad_id === sq[side].id);
    membersBy[side] = members.filter((m) => m.strategist_id === sq[side].strategist_id).map((m) => m.player_id);
    label[side] = membersBy[side].map(pname).join(' и ');
  });
  const moonBy = Object.fromEntries(moon.map((m) => [m.squad_id, m]));
  const side = (s) => ({
    squad_id: sq[s].id, name: sq[s].name, rage: sq[s].rage, figures: figs[s],
    echoBlocked: echoOf(s) ? echoOf(s).blocked_properties || [] : [], echoName: echoOf(s) ? echoOf(s).name : null,
    trophies_s: trophiesBy[s].reduce((n, t) => n + (t.bonus_s || 0), 0),
    white_streak: !!(moonBy[sq[s].id] && moonBy[sq[s].id].white_streak),
  });
  const properties = Object.fromEntries(cache.properties.map((p) => [p.name, { phase: p.phase, cost: p.cost }]));
  const result = window.Battle.compute({ attacker: side('attacker'), defender: side('defender'), actions, gifts: [...gifts2], echoBlocked, properties });
  return {
    battle, game: games[0], sq, figs, figById, actions, gifts: gifts2, echoOf, result,
    trophies: trophiesBy, members: membersBy, label,
    actionsTook: takes.some((e) => e.data && Number(e.data.battle) === battleId && !e.reverted),
  };
}
