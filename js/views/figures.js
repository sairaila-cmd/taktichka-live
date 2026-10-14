// Фигуры: таблица как в дашборде + карточка фигуры, история и правки по коду.
import { rows, call, cache, session, isAdmin } from '../api.js';
import { h, clear, btn, modal, form, act, refresh, NOM_GLYPH, plural } from '../ui.js';
import { logList, pname } from './common.js';

const COLS = [
  ['name', 'Фигура'], ['nominal', 'Номинал'], ['s', 'С', 'num'], ['l', 'Л', 'num'], ['v', 'В', 'num'],
  ['sum', 'Σ', 'num'], ['props', 'Свойство'], ['owner_label', 'Владелец', 'wide-only'], ['sources', 'Источники', 'wide-only'],
];

export default async function figuresView(root, openId) {
  const [figures, owners] = await Promise.all([rows('figures', (q) => q.order('name')), rows('figure_owners')]);
  const ownersOf = {};
  owners.forEach((o) => { (ownersOf[o.figure_id] = ownersOf[o.figure_id] || []).push(o.player_id); });
  figures.forEach((f) => { f.sum = f.s + f.l + f.v; f.props = (f.properties || []).join(' / '); f.owners = ownersOf[f.id] || []; });
  const rank = Object.fromEntries(cache.nominals.map((n) => [n.name, n.rank]));
  const active = figures.filter((f) => f.status === 'active');

  const st = { q: '', nominal: null, owner: '', dead: false, sort: 'name', dir: 1 };

  root.append(
    h('h1', { class: 'page-title' }, 'Фигуры тактички'),
    h('p', { class: 'lede' }, plural(active.length, 'фигура', 'фигуры', 'фигур') + ' в строю' +
      (figures.length > active.length ? ', ' + plural(figures.length - active.length, 'погибла', 'погибли', 'погибли') : '') +
      '. Смотреть может каждый; править свои фигуры — по личному коду.'),
    h('div', { class: 'tiles' }, cache.nominals.map((n) => {
      const c = active.filter((f) => f.nominal === n.name).length;
      return c ? h('div', { class: 'tile' }, h('b', {}, NOM_GLYPH[n.name] + ' ' + c), h('span', {}, n.name)) : null;
    })));

  const search = h('input', { type: 'search', placeholder: 'Найти фигуру, владельца или свойство', 'aria-label': 'Поиск', style: 'flex: 1 1 14rem' });
  const ownerSel = h('select', { 'aria-label': 'Владелец' }, h('option', { value: '' }, 'Все владельцы'),
    cache.players.filter((p) => !p.is_admin).map((p) => h('option', { value: p.id }, p.name)));
  const deadBox = h('input', { type: 'checkbox' });
  const count = h('span', { class: 'muted small num' });
  const chips = h('div', { class: 'chips', role: 'group', 'aria-label': 'Номинал' },
    [null, ...cache.nominals.map((n) => n.name)].map((n) => h('button', { class: 'chip', type: 'button', 'aria-pressed': String(n === null),
      onclick: (e) => { st.nominal = n; chips.querySelectorAll('.chip').forEach((c) => c.setAttribute('aria-pressed', String(c === e.currentTarget))); draw(); } },
      n ? NOM_GLYPH[n] + ' ' + n : 'Все')));
  const tbody = h('tbody');
  const thead = h('thead', {}, h('tr', {}, COLS.map(([k, t, cls]) => h('th', { class: cls || '' },
    h('button', { type: 'button', onclick: () => { st.dir = st.sort === k ? -st.dir : (['s', 'l', 'v', 'sum'].includes(k) ? -1 : 1); st.sort = k; draw(); } }, t)))));

  const tools = [];
  if (session.me) tools.push(btn('+ Добавить фигуру', () => addFigure(), 'primary'));
  root.append(h('section', { class: 'card' },
    h('header', {}, h('h2', {}, 'Все фигуры'), h('div', { class: 'row' }, tools)),
    h('div', { class: 'row' }, search, ownerSel, h('label', { class: 'inline' }, deadBox, 'погибшие'), count),
    chips,
    h('div', { class: 'tablewrap' }, h('table', {}, thead, tbody))));

  search.addEventListener('input', () => { st.q = search.value.trim().toLowerCase(); draw(); });
  ownerSel.addEventListener('change', () => { st.owner = ownerSel.value; draw(); });
  deadBox.addEventListener('change', () => { st.dead = deadBox.checked; draw(); });

  function draw() {
    const list = figures.filter((f) =>
      (st.dead || f.status === 'active') &&
      (!st.nominal || f.nominal === st.nominal) &&
      (!st.owner || f.owners.includes(Number(st.owner))) &&
      (!st.q || [f.name, f.props, f.owner_label, f.nominal, f.sources].join(' ').toLowerCase().includes(st.q)));
    list.sort((a, b) => {
      const k = st.sort;
      const va = k === 'nominal' ? rank[a.nominal] : a[k];
      const vb = k === 'nominal' ? rank[b.nominal] : b[k];
      return (typeof va === 'number' ? va - vb : String(va).localeCompare(String(vb), 'ru')) * st.dir;
    });
    count.textContent = 'показано ' + list.length;
    clear(tbody, list.map((f) => h('tr', { class: 'click' + (f.status === 'dead' ? ' dead' : ''), onclick: () => { location.hash = '#/figure/' + f.id; } },
      h('td', {}, f.name), h('td', { style: 'white-space: nowrap' }, NOM_GLYPH[f.nominal] + ' ' + f.nominal),
      h('td', { class: 'num' }, f.s), h('td', { class: 'num' }, f.l), h('td', { class: 'num' }, f.v), h('td', { class: 'num' }, f.sum),
      h('td', {}, f.props), h('td', { class: 'wide-only' }, f.owner_label), h('td', { class: 'wide-only muted' }, f.sources))));
  }
  draw();

  if (openId) {
    const f = figures.find((x) => x.id === Number(openId));
    if (f) setTimeout(() => showFigure(f), 0);
  }

  async function showFigure(f) {
    const events = await rows('events', (q) => q.eq('figure_id', f.id).order('at', { ascending: false }).limit(100));
    const mine = session.me && (f.owners.includes(session.me.id) || isAdmin());
    const games = session.me ? await rows('games', (q) => q.order('id', { ascending: false }).limit(30)) : [];
    const close = modal(NOM_GLYPH[f.nominal] + ' ' + f.name, (closeFn) => h('div', { class: 'stack' },
      h('div', { class: 'row' },
        h('span', { class: 'badge moon' }, f.nominal),
        h('span', { class: 'badge' }, 'Сила ' + f.s), h('span', { class: 'badge' }, 'Лояльность ' + f.l),
        h('span', { class: 'badge' }, 'Влияние ' + f.v), h('span', { class: 'badge' }, 'Σ ' + f.sum),
        f.status === 'dead' ? h('span', { class: 'badge bad' }, 'погибла') : null),
      (f.properties || []).map((p) => h('div', {}, h('b', {}, p),
        cache.propByName[p] ? h('span', { class: 'muted small' }, ' · ' + cache.propByName[p].phase +
          (cache.propByName[p].cost ? ' · ' + cache.propByName[p].cost + ' Р.' : (cache.propByName[p].cost_note ? ' · ' + cache.propByName[p].cost_note + ' Р.' : ''))) : null,
        cache.propByName[p] ? h('div', { class: 'prop-desc' }, cache.propByName[p].description) : null)),
      h('div', { class: 'small' }, 'Владельцы: ', f.owners.length ? f.owners.map(pname).join(', ') : '—',
        f.owner_label && f.owner_label.split(/; | и /).sort().join() !== f.owners.map(pname).sort().join() ? h('span', { class: 'muted' }, ' (в дашборде: ' + f.owner_label + ')') : null),
      f.sources ? h('div', { class: 'small muted' }, 'Источники: ' + f.sources) : null,
      mine && f.status === 'active' ? h('div', { class: 'row' },
        btn('Править', () => { closeFn(); editFigure(f); }),
        btn('Передать', () => { closeFn(); transferFigure(f); }),
        btn('Отметить применение', () => { closeFn(); useFigure(f, games); })) : null,
      h('h3', {}, 'История'),
      logList(events, { figures: { [f.id]: f } })));
    document.getElementById('dialog').addEventListener('close', () => {
      if (location.hash === '#/figure/' + f.id) history.replaceState(null, '', '#/');
    }, { once: true });
    return close;
  }

  const propOptions = () => cache.properties.map((p) => [p.name, p.name + ' (' + p.phase + ')']);
  const nomOptions = () => cache.nominals.map((n) => [n.name, NOM_GLYPH[n.name] + ' ' + n.name]);
  const reload = refresh;

  function addFigure() {
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
    }), 'Фигура добавлена', () => { close(); reload(); })));
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
    }), 'Сохранено', () => { close(); reload(); })));
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
    }), 'Фигура передана', () => { close(); reload(); })));
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
}
