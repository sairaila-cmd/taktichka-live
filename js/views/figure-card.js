// Окно фигуры: свойства, владельцы, история и правки по коду. Открывается поверх любой
// страницы (раздел «Фигуры», страница игры, бой) — без перехода.
import { rows, call, cache, session, isAdmin } from '../api.js?v=202610152342';
import { h, btn, modal, form, act, refresh, NOM_GLYPH } from '../ui.js?v=202610152342';
import { logList, pname } from './common.js?v=202610152342';

export async function openFigure(id) {
  const [figs, owners, events] = await Promise.all([
    rows('figures', (q) => q.eq('id', id)),
    rows('figure_owners', (q) => q.eq('figure_id', id)),
    rows('events', (q) => q.eq('figure_id', id).order('at', { ascending: false }).limit(100)),
  ]);
  const f = figs[0];
  if (!f) return;
  f.owners = owners.map((o) => o.player_id);
  f.sum = f.s + f.l + f.v;
  // названия отрядов для подписей в истории («в отряде «Волки»», а не «отряд #2»)
  const squadIds = [...new Set(events.flatMap((e) => [e.squad_id, e.data && e.data.to, e.data && e.data.from, e.data && e.data.a, e.data && e.data.b])
    .filter((x) => Number.isInteger(x)))];
  const squads = squadIds.length ? await rows('squads', (q) => q.in('id', squadIds), 'id, name') : [];
  const games = session.me ? await rows('games', (q) => q.order('id', { ascending: false }).limit(30)) : [];
  // названия игр для меток в истории
  const gameIds = [...new Set(events.map((e) => e.game_id).filter((x) => x != null))];
  const evGames = gameIds.length ? await rows('games', (q) => q.in('id', gameIds), 'id, title') : [];
  const mine = session.me && (f.owners.includes(session.me.id) || isAdmin());
  const p = (name) => cache.propByName[name];
  modal(NOM_GLYPH[f.nominal] + ' ' + f.name, (closeFn) => h('div', { class: 'stack' },
    h('div', { class: 'row' },
      h('span', { class: 'badge moon' }, f.nominal),
      h('span', { class: 'badge' }, 'Сила ' + f.s), h('span', { class: 'badge' }, 'Лояльность ' + f.l),
      h('span', { class: 'badge' }, 'Влияние ' + f.v), h('span', { class: 'badge' }, 'Σ ' + f.sum),
      f.status === 'dead' ? h('span', { class: 'badge bad' }, 'погибла') : null),
    (f.properties || []).map((name) => h('div', {}, h('b', {}, name),
      p(name) ? h('span', { class: 'muted small' }, ' · ' + p(name).phase +
        (p(name).cost ? ' · ' + p(name).cost + ' Р.' : (p(name).cost_note ? ' · ' + p(name).cost_note + ' Р.' : ''))) : null,
      p(name) ? h('div', { class: 'prop-desc' }, p(name).description) : null)),
    h('div', { class: 'small' }, 'Владельцы: ', f.owners.length ? f.owners.map(pname).join(', ') : '—',
      f.owner_label && [...new Set(f.owner_label.split(/; | и /))].sort().join() !== f.owners.map(pname).sort().join()
        ? h('span', { class: 'muted' }, ' (в дашборде: ' + f.owner_label + ')') : null),
    f.sources ? h('div', { class: 'small muted' }, 'Источники: ' + f.sources) : null,
    mine && f.status === 'active' ? h('div', { class: 'row' },
      btn('Править', () => { closeFn(); editFigure(f); }),
      btn('Передать', () => { closeFn(); transferFigure(f); }),
      btn('Отметить применение', () => { closeFn(); useFigure(f, games); })) : null,
    h('h3', {}, 'История'),
    logList(events, { figures: { [f.id]: f }, squads: Object.fromEntries(squads.map((s) => [s.id, s])),
      games: Object.fromEntries(evGames.map((g) => [g.id, g])) })));
}

const propOptions = () => cache.properties.map((p) => [p.name, p.name + ' (' + p.phase + ')']);
export const nomOptions = () => cache.nominals.map((n) => [n.name, NOM_GLYPH[n.name] + ' ' + n.name]);

export function addFigure() {
  modal('Новая фигура', (close) => form([
    { name: 'name', label: 'Название', required: true },
    { name: 'nominal', label: 'Номинал', type: 'select', options: nomOptions(), value: 'пешка' },
    { name: 's', label: 'Сила', type: 'number', value: 1, min: 0 },
    { name: 'l', label: 'Лояльность', type: 'number', value: 1, min: 0 },
    { name: 'v', label: 'Влияние', type: 'number', value: 1, min: 0 },
    { name: 'properties', label: 'Свойства (Ctrl — несколько)', type: 'select', multiple: true, options: propOptions() },
    { name: 'source', label: 'Где получена (игра)' },
    { name: 'comment', label: 'Комментарий' },
  ], 'Добавить', (v) => act(() => call('api_figure_add', {
    p_name: v.name, p_nominal: v.nominal, p_s: v.s ?? 0, p_l: v.l ?? 0, p_v: v.v ?? 0,
    p_properties: v.properties, p_source: v.source, p_comment: v.comment,
  }), 'Фигура добавлена', () => { close(); refresh(); })));
}

function editFigure(f) {
  modal('Править «' + f.name + '»', (close) => form([
    { name: 'name', label: 'Название', required: true, value: f.name },
    { name: 'nominal', label: 'Номинал', type: 'select', options: nomOptions(), value: f.nominal },
    { name: 's', label: 'Сила', type: 'number', value: f.s, min: 0 },
    { name: 'l', label: 'Лояльность', type: 'number', value: f.l, min: 0 },
    { name: 'v', label: 'Влияние', type: 'number', value: f.v, min: 0 },
    { name: 'properties', label: 'Свойства (Ctrl — несколько)', type: 'select', multiple: true, options: propOptions(), value: f.properties },
    { name: 'comment', label: 'Почему меняется (видно в истории)' },
  ], 'Сохранить', (v) => act(() => call('api_figure_edit', {
    p_figure: f.id, p_name: v.name, p_nominal: v.nominal, p_s: v.s ?? 0, p_l: v.l ?? 0, p_v: v.v ?? 0,
    p_properties: v.properties, p_comment: v.comment,
  }), 'Сохранено', () => { close(); refresh(); })));
}

function transferFigure(f) {
  const fromOpts = isAdmin() ? f.owners.map((id) => [id, pname(id)]) : [[session.me.id, session.me.name]];
  modal('Передать «' + f.name + '»', (close) => form([
    { name: 'from', label: 'Чья доля', type: 'select', options: fromOpts, value: fromOpts[0] && fromOpts[0][0] },
    { name: 'to', label: 'Кому', type: 'select', required: true,
      options: cache.players.filter((p) => !p.is_admin).map((p) => [p.id, p.name]) },
    { name: 'comment', label: 'Комментарий (игра, причина)' },
  ], 'Передать', (v) => act(() => call('api_figure_transfer', {
    p_figure: f.id, p_from: Number(v.from), p_to: Number(v.to), p_comment: v.comment,
  }), 'Фигура передана', () => { close(); refresh(); })));
}

function useFigure(f, games) {
  modal('Применение «' + f.name + '»', (close) => form([
    { name: 'game', label: 'Игра на сайте', type: 'select', options: [['', '— не на сайте —'], ...games.map((g) => [g.id, g.title])] },
    { name: 'where', label: 'Где применена (если игра не на сайте)' },
    { name: 'comment', label: 'Что произошло' },
  ], 'Отметить', (v) => act(() => call('api_figure_use', {
    p_figure: f.id, p_game: v.game ? Number(v.game) : null, p_where: v.where, p_comment: v.comment,
  }), 'Отмечено', () => { close(); })));
}
