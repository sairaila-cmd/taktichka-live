// Фигуры: таблица как в дашборде + карточка фигуры, история и правки по коду.
import { rows, cache, session } from '../api.js?v=202610142332';
import { h, clear, btn, NOM_GLYPH, plural } from '../ui.js?v=202610142332';
import { openFigure, addFigure } from './figure-card.js?v=202610142332';

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
    clear(tbody, list.map((f) => h('tr', { class: 'click' + (f.status === 'dead' ? ' dead' : ''), onclick: () => openFigure(f.id) },
      h('td', {}, f.name), h('td', { style: 'white-space: nowrap' }, NOM_GLYPH[f.nominal] + ' ' + f.nominal),
      h('td', { class: 'num' }, f.s), h('td', { class: 'num' }, f.l), h('td', { class: 'num' }, f.v), h('td', { class: 'num' }, f.sum),
      h('td', {}, f.props), h('td', { class: 'wide-only' }, f.owner_label), h('td', { class: 'wide-only muted' }, f.sources))));
  }
  draw();

  if (openId) {
    // прямая ссылка #/figure/ID: окно поверх раздела, после закрытия адрес возвращается к «Фигурам»
    setTimeout(() => openFigure(Number(openId)).then(() => {
      document.getElementById('dialog').addEventListener('close', () => {
        if (location.hash === '#/figure/' + openId) history.replaceState(null, '', '#/');
      }, { once: true });
    }), 0);
  }
}
