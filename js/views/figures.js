// Фигуры: таблица как в дашборде + карточка фигуры, история и правки по коду.
// Сверху — фигуры в отрядах выбранной игры (как в «Персонажах»), ниже, свёрнуто, — остальные.
import { rows, rowsAll, cache, session } from '../api.js?v=202610161643';
import { h, clear, btn, NOM_GLYPH, plural, STATUS_RU } from '../ui.js?v=202610161643';
import { openFigure, addFigure } from './figure-card.js?v=202610161643';

const COLS = [
  ['name', 'Фигура'], ['nominal', 'Номинал'], ['s', 'С', 'num'], ['l', 'Л', 'num'], ['v', 'В', 'num'],
  ['sum', 'Σ', 'num'], ['props', 'Свойство'], ['owner_label', 'Владелец', 'wide-only'], ['sources', 'Источники', 'wide-only'],
];

export default async function figuresView(root, openId, gameParam) {
  const [figures, owners, games] = await Promise.all([
    rowsAll('figures', (q) => q.order('name')),
    rowsAll('figure_owners', (q) => q.order('figure_id').order('player_id')),
    rowsAll('games', (q) => q.neq('status', 'closed').order('id', { ascending: false })),
  ]);
  // По умолчанию — последняя идущая игра, если её нет — последняя в сборе отрядов.
  const game = games.find((g) => g.id === Number(gameParam)) || games.find((g) => g.status === 'running') || games[0] || null;
  const inGame = new Set(game ? (await rowsAll('squad_figures', (q) => q.eq('game_id', game.id).order('squad_id').order('figure_id'), 'figure_id')).map((x) => x.figure_id) : []);
  const ownersOf = {};
  owners.forEach((o) => { (ownersOf[o.figure_id] = ownersOf[o.figure_id] || []).push(o.player_id); });
  figures.forEach((f) => {
    f.sum = f.s + f.l + f.v; f.props = (f.properties || []).join(' / '); f.owners = ownersOf[f.id] || [];
    f.srcList = (f.sources || '').split(';').map((s) => s.trim()).filter(Boolean);
  });
  const sources = [...new Set(figures.flatMap((f) => f.srcList))].sort((a, b) => a.localeCompare(b, 'ru'));
  const rank = Object.fromEntries(cache.nominals.map((n) => [n.name, n.rank]));
  const active = figures.filter((f) => f.status === 'active');

  const st = { q: '', nominal: null, owner: '', source: '', dead: false, sort: 'name', dir: 1 };

  const picker = games.length > 1 ? h('select', { 'aria-label': 'Игра', onchange: (e) => { location.hash = '#/figures/' + e.target.value; } },
    games.map((g) => h('option', { value: g.id, selected: game && g.id === game.id }, g.title + ' — ' + STATUS_RU[g.status]))) : null;

  // root.append выводит null как текст «null» — пустые части отбрасываем.
  root.append(...[
    h('h1', { class: 'page-title' }, 'Фигуры тактички'),
    h('p', { class: 'lede' }, plural(active.length, 'фигура', 'фигуры', 'фигур') + ' в строю' +
      (figures.length > active.length ? ', ' + plural(figures.length - active.length, 'погибла', 'погибли', 'погибли') : '') +
      '. Смотреть может каждый; править свои фигуры — по личному коду.'),
    h('div', { class: 'tiles' }, cache.nominals.map((n) => {
      const c = active.filter((f) => f.nominal === n.name).length;
      return c ? h('div', { class: 'tile' }, h('b', {}, NOM_GLYPH[n.name] + ' ' + c), h('span', {}, n.name)) : null;
    })),
    picker ? h('div', { class: 'row', style: 'justify-content:center' }, h('label', { class: 'inline' }, 'Игра:', picker)) : null,
  ].filter(Boolean));

  const search = h('input', { type: 'search', placeholder: 'Найти фигуру, владельца или свойство', 'aria-label': 'Поиск', style: 'flex: 1 1 14rem' });
  const ownerSel = h('select', { 'aria-label': 'Владелец' }, h('option', { value: '' }, 'Все владельцы'),
    cache.players.filter((p) => !p.is_admin).map((p) => h('option', { value: p.id }, p.name)));
  const sourceSel = h('select', { 'aria-label': 'Источник' }, h('option', { value: '' }, 'Все источники'),
    sources.map((s) => h('option', { value: s }, s)));
  const deadBox = h('input', { type: 'checkbox' });
  const count = h('span', { class: 'muted small num' });
  const chips = h('div', { class: 'chips', role: 'group', 'aria-label': 'Номинал' },
    [null, ...cache.nominals.map((n) => n.name)].map((n) => h('button', { class: 'chip', type: 'button', 'aria-pressed': String(n === null),
      onclick: (e) => { st.nominal = n; chips.querySelectorAll('.chip').forEach((c) => c.setAttribute('aria-pressed', String(c === e.currentTarget))); draw(); } },
      n ? NOM_GLYPH[n] + ' ' + n : 'Все')));
  // Заголовок таблицы; сортировка общая для обеих таблиц.
  const thead = () => h('thead', {}, h('tr', {}, COLS.map(([k, t, cls]) => h('th', { class: cls || '' },
    h('button', { type: 'button', onclick: () => { st.dir = st.sort === k ? -st.dir : (['s', 'l', 'v', 'sum'].includes(k) ? -1 : 1); st.sort = k; draw(); } }, t)))));
  const gameBody = h('tbody');
  const restBody = h('tbody');
  const gameEmpty = h('p', { class: 'empty' });
  const restSummary = h('summary');

  const tools = [];
  if (session.me) tools.push(btn('+ Добавить фигуру', () => addFigure(), 'primary'));
  root.append(h('section', { class: 'card' }, ...[
    h('header', {}, h('h2', {}, 'Все фигуры'), h('div', { class: 'row' }, tools)),
    h('div', { class: 'row' }, search, ownerSel, sourceSel, h('label', { class: 'inline' }, deadBox, 'погибшие'), count),
    chips,
    game ? h('p', { class: 'muted small' }, 'Сверху — фигуры в отрядах игры ', h('a', { href: '#/game/' + game.id }, '«' + game.title + '»'),
      '; остальные — в свёрнутом списке ниже.') : null,
    h('div', { class: 'tablewrap' }, h('table', { id: game ? 'figs-game' : 'figs-all' }, thead(), gameBody)),
    game ? gameEmpty : null,
  ].filter(Boolean)));
  if (game) {
    root.append(h('section', { class: 'card' },
      h('details', {}, restSummary,
        h('div', { class: 'tablewrap', style: 'margin-top: 10px' }, h('table', { id: 'figs-rest' }, thead(), restBody)))));
  }

  search.addEventListener('input', () => { st.q = search.value.trim().toLowerCase(); draw(); });
  ownerSel.addEventListener('change', () => { st.owner = ownerSel.value; draw(); });
  sourceSel.addEventListener('change', () => { st.source = sourceSel.value; draw(); });
  deadBox.addEventListener('change', () => { st.dead = deadBox.checked; draw(); });

  const row = (f) => h('tr', { class: 'click' + (f.status === 'dead' ? ' dead' : ''), onclick: () => openFigure(f.id) },
    h('td', {}, f.name), h('td', { style: 'white-space: nowrap' }, NOM_GLYPH[f.nominal] + ' ' + f.nominal),
    h('td', { class: 'num' }, f.s), h('td', { class: 'num' }, f.l), h('td', { class: 'num' }, f.v), h('td', { class: 'num' }, f.sum),
    h('td', {}, f.props), h('td', { class: 'wide-only' }, f.owner_label), h('td', { class: 'wide-only muted' }, f.sources));

  function draw() {
    const list = figures.filter((f) =>
      (st.dead || f.status === 'active') &&
      (!st.nominal || f.nominal === st.nominal) &&
      (!st.owner || f.owners.includes(Number(st.owner))) &&
      (!st.source || f.srcList.includes(st.source)) &&
      (!st.q || [f.name, f.props, f.owner_label, f.nominal, f.sources].join(' ').toLowerCase().includes(st.q)));
    list.sort((a, b) => {
      const k = st.sort;
      const va = k === 'nominal' ? rank[a.nominal] : a[k];
      const vb = k === 'nominal' ? rank[b.nominal] : b[k];
      return (typeof va === 'number' ? va - vb : String(va).localeCompare(String(vb), 'ru')) * st.dir;
    });
    count.textContent = 'показано ' + list.length;
    if (!game) { clear(gameBody, list.map(row)); return; }
    const mine = list.filter((f) => inGame.has(f.id));
    const rest = list.filter((f) => !inGame.has(f.id));
    clear(gameBody, mine.map(row));
    gameEmpty.textContent = inGame.size ? 'Под фильтр не попала ни одна фигура этой игры.' : 'В отрядах этой игры пока нет фигур.';
    gameEmpty.hidden = mine.length > 0;
    clear(restBody, rest.map(row));
    restSummary.textContent = 'Остальные фигуры (' + rest.length + ')';
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
