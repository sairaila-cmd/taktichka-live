// Общее для разделов: подписи событий журнала, карточка отряда, имена.
import { cache, session } from '../api.js';
import { h, fmtTime, NOM_GLYPH, STATE_RU, GIFT_RU, plural } from '../ui.js';

export const pname = (id) => (cache.playerById && cache.playerById[id] ? cache.playerById[id].name : (id == null ? '—' : '#' + id));
export const res = (n) => plural(Math.abs(n), 'Ресурс', 'Ресурса', 'Ресурсов');

// maps: { figures: {id: fig}, squads: {id: squad}, strategists: {id: label}, games: {id: game} }
export function describe(ev, maps = {}) {
  const d = ev.data || {};
  const fig = (id) => '«' + ((maps.figures && maps.figures[id] && maps.figures[id].name) || ('фигура #' + id)) + '»';
  const sq = (id) => '«' + ((maps.squads && maps.squads[id] && maps.squads[id].name) || ('отряд #' + id)) + '»';
  const st = (id) => (maps.strategists && maps.strategists[id]) || d.label || ('стратег #' + id);
  const F = fig(ev.figure_id);
  switch (ev.kind) {
    case 'import': return 'Перенос данных из дашборда «Фигуры тактички» (' + (d.figures || '?') + ' фигур)';
    case 'figure_add': return 'Новая фигура ' + F + (d.source ? ' (' + d.source + ')' : '');
    case 'figure_edit': return 'Правка фигуры ' + F;
    case 'figure_transfer': return 'Передача фигуры ' + F + ': ' + pname(d.from) + ' → ' + pname(d.to);
    case 'figure_use': return 'Применение фигуры ' + F + (d.where ? ' — ' + d.where : '');
    case 'figure_state': return 'Фигура ' + F + ' в отряде ' + sq(ev.squad_id) + ': ' + (STATE_RU[d.from] || d.from) + ' → ' + (STATE_RU[d.to] || d.to);
    case 'figure_move': return 'Фигура ' + F + ' перешла в отряд ' + sq(d.to);
    case 'figure_death': return 'Гибель фигуры ' + F + ' (' + (d.how || '') + ')';
    case 'resources_transfer': return 'Передача ' + res(ev.amount) + ': ' + pname(d.from) + ' → ' + pname(d.to);
    case 'resources_grant': return (ev.amount >= 0 ? 'Начислено ' : 'Списано ') + res(ev.amount) + ' — ' + pname(ev.player_id) + (d.wallet ? ' (в общий кошелёк пары)' : '');
    case 'resources_spend': return 'Потрачено ' + res(ev.amount) + (ev.squad_id ? ' (отряд ' + sq(ev.squad_id) + ')' : '');
    case 'resources_gain': return 'Получено ' + res(ev.amount) + (ev.squad_id ? ' (отряд ' + sq(ev.squad_id) + ')' : '');
    case 'bonus_squads': return 'Доп. отряды за Влияние: ' + pname(ev.player_id) + ' — ' + ev.amount;
    case 'game_draft': return 'Игра «' + (d.title || '') + '»: сбор отрядов';
    case 'game_running': return 'Игра «' + (d.title || '') + '» началась';
    case 'game_closed': return 'Игра «' + (d.title || '') + '» закончена';
    case 'join_game': return pname(ev.player_id) + ' участвует в игре';
    case 'partner_invite': return 'Приглашение в напарники: ' + pname(ev.player_id);
    case 'pair': return (ev.actor ? 'Напарники: ' : 'В общий кошелёк перенесено (починка): ') + (d.players || []).map(pname).join(' и ') + ' — ' + res(ev.amount);
    case 'wallet_split': return 'Раздел общего кошелька: ' + Object.entries(d).map(([p, n]) => pname(Number(p)) + ' ' + n).join(', ');
    case 'squad_save': return 'Отряд «' + (d.name || '') + '» собран (' + plural((d.figures || []).length, 'фигура', 'фигуры', 'фигур') + ')';
    case 'squad_delete': return 'Отряд «' + (d.name || '') + '» распущен';
    case 'exchange': return 'Обмен между отрядами ' + sq(d.a) + ' и ' + sq(d.b);
    case 'roll': return 'Бросок d10: ' + ev.amount + (d.manual ? ' (введён ведущим)' : '') + (ev.squad_id ? ' — ' + sq(ev.squad_id) : '');
    case 'property_use': return 'Свойство «' + d.property + '» у ' + F + (ev.amount ? ' (−' + res(ev.amount) + ')' : '') +
      (d.roll ? ', бросок ' + d.roll : '') + (d.gain ? ', +1 Ресурс' : '');
    case 'battle_open': return 'Бой: ' + sq(d.attacker) + ' нападает на ' + sq(d.defender);
    case 'battle_close': return 'Бой окончен: ' + (d.winner ? 'победил ' + sq(d.winner) : 'ничья') + (d.reason ? ' (' + d.reason + ')' : '');
    case 'battle_undo': return 'Ведущий отменил шаг боя';
    case 'trophy_give': return 'Трофей «' + d.name + '» выдан отряду ' + sq(ev.squad_id);
    case 'trophy_equip': return 'Сохранённый трофей взят в отряд ' + sq(ev.squad_id);
    case 'trophy_drop': return 'Трофей «' + d.name + '» выброшен';
    case 'trophy_take': return 'Трофей «' + d.name + '» забран у отряда ' + sq(d.from) + ' отрядом ' + sq(ev.squad_id);
    case 'trophy_end': return 'Трофей «' + d.name + '» ' + (d.kept ? 'остаётся у ' + pname(ev.player_id) : 'исчезает');
    case 'revert': return 'Ведущий отменил запись журнала #' + d.event;
    case 'gift_on': return 'Включён дар: ' + (GIFT_RU[d.gift] || d.gift);
    case 'gift_off': return 'Выключен дар: ' + (GIFT_RU[d.gift] || d.gift);
    case 'initiative': return 'Инициатива ' + st(d.strategist) + ': ' + ev.amount;
    case 'turn_start': return 'Начался ход ' + ev.amount + ' — интриги';
    case 'turn_actions': return 'Ход ' + ev.amount + ': действия по инициативе';
    case 'turn_set': return 'Ведущий передвинул указатель хода';
    case 'turn_pass': return 'Ход передан дальше';
    case 'intrigue': return 'Интрига (' + st(d.strategist) + ')';
    case 'squad_move': return 'Отряд ' + sq(ev.squad_id) + ': ' + (d.action || 'ход') + (d.finished ? ' — ход закончен' : '') + (d.tact > 1 ? ' (такт ' + d.tact + ')' : '');
    case 'squad_echo': return 'Отряд ' + sq(ev.squad_id) + ': ' + ({ passed: 'прошёл через', stopped: 'остановился в', left: 'вышел из' }[d.mode] || d.mode) +
      (d.name ? ' Эхо «' + d.name + '»' : ' Эхо') + (ev.amount ? ' (−' + res(ev.amount) + ')' : '');
    case 'rage_spend': return 'Ярость отряда ' + sq(ev.squad_id) + ': ' + ({ move: '+1 к перемещению', power: '+5 к Силе', remote: 'фишка издалека' }[d.use] || d.use);
    case 'rage_set': return 'Ярость отряда ' + sq(ev.squad_id) + ' = ' + ev.amount;
    case 'echo': return d.name ? 'Эхо «' + d.name + '»: ' + ({ open: 'открыто', active: 'действует', ended: 'закончилось' }[d.status] || d.status) : 'Ведущий изменил скрытое Эхо';
    default: return ev.kind;
  }
}

export function logList(events, maps) {
  if (!events.length) return h('p', { class: 'empty' }, 'Записей пока нет.');
  return h('ul', { class: 'log' }, events.map((ev) => h('li', { class: ev.reverted ? 'reverted' : '' },
    h('time', { datetime: ev.at }, fmtTime(ev.at)),
    h('div', {},
      describe(ev, maps),
      ev.comment ? h('span', { class: 'muted' }, ' — ' + ev.comment) : null,
      ev.actor ? h('span', { class: 'muted small' }, ' · ' + pname(ev.actor)) : null))));
}

export const glyph = (nom) => NOM_GLYPH[nom] || '';

export function figLine(f, extra) {
  return h('span', {}, h('span', { class: 'nom', title: f.nominal }, glyph(f.nominal) + ' '),
    h('a', { href: '#/figure/' + f.id }, f.name),
    h('span', { class: 'muted num' }, ' ' + f.s + '/' + f.l + '/' + f.v),
    f.properties && f.properties.length ? h('span', { class: 'muted' }, ' · ' + f.properties.join(' / ')) : null,
    extra || null);
}

// Отряд: squad + { figs: [{fig, sf}], trophies, totals:{s,l,v}, moon:{white_streak, duplicate_nominals}, moved, mine, gifts }
export function squadCard(sq, o, actions) {
  const gifts = o.gifts || new Set();
  const tags = [];
  if (sq.destroyed) tags.push(h('span', { class: 'badge bad' }, 'уничтожен'));
  if (o.inBattle) tags.push(h('span', { class: 'badge bad' }, 'в бою'));
  if (o.echo) tags.push(h('span', { class: 'badge warn', title: 'Отряд стоит в Эхо: его правила действуют на этот отряд' }, 'в Эхо «' + o.echo + '»'));
  if (o.moved) tags.push(h('span', { class: 'badge info' }, 'ход: ' + o.moved));
  if (gifts.has('alaya') && sq.rage) tags.push(h('span', { class: 'badge bad', title: 'Алая луна' }, 'Ярость ' + sq.rage));
  if (gifts.has('belaya') && o.moon && o.moon.white_streak) tags.push(h('span', { class: 'badge moon', title: 'Белая луна: +2 к Силе, +1 действие в событиях' }, '☾ три номинала подряд'));
  if (gifts.has('belaya') && o.moon && o.moon.duplicate_nominals > 0) tags.push(h('span', { class: 'badge warn', title: 'Белая луна: штраф к Лояльности при попытке переманить' }, 'повторы номиналов: ' + o.moon.duplicate_nominals));
  if (sq.dead_figure) tags.push(h('span', { class: 'badge' }, 'погибла: ' + ((o.figById && o.figById[sq.dead_figure]) ? o.figById[sq.dead_figure].name : '#' + sq.dead_figure)));
  const t = o.totals || { s: 0, l: 0, v: 0 };
  return h('article', { class: 'squad' + (o.mine ? ' mine' : '') + (sq.destroyed ? ' destroyed' : '') },
    h('div', { class: 'row', style: 'justify-content: space-between' },
      h('span', { class: 'name' }, sq.name),
      h('span', { class: 'stats small' }, 'С ', h('b', {}, t.s), ' Л ', h('b', {}, t.l), ' В ', h('b', {}, t.v))),
    tags.length ? h('div', { class: 'row' }, tags) : null,
    h('ul', { class: 'figs' }, o.figs.map(({ fig, sf }) => h('li', { class: 'st-' + sf.state },
      figLine(fig, h('span', {},
        sf.state !== 'ok' ? h('span', { class: 'badge warn' }, STATE_RU[sf.state]) : null,
        sf.borrowed ? h('span', { class: 'badge info' }, 'взята у противника') : null))))),
    o.trophies && o.trophies.length ? h('div', { class: 'small' }, 'Трофеи: ',
      o.trophies.map((tr, i) => h('span', { title: tr.description || '' }, i ? ', ' : '', '«' + tr.name + '»',
        (tr.bonus_s || tr.bonus_l || tr.bonus_v) ? h('span', { class: 'muted' }, ' (' + [tr.bonus_s && '+' + tr.bonus_s + 'С', tr.bonus_l && '+' + tr.bonus_l + 'Л', tr.bonus_v && '+' + tr.bonus_v + 'В'].filter(Boolean).join(' ') + ')') : null))) : null,
    actions && actions.length ? h('div', { class: 'row' }, actions) : null);
}

export const isMember = (members, strategistId) =>
  !!session.me && members.some((m) => m.strategist_id === strategistId && m.player_id === session.me.id);
