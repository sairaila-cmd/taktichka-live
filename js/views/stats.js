// Статистика игры: плитки, состояния фигур и графики (как в дашборде «Фигуры тактички»),
// по фигурам в отрядах этой игры. Графики — простое SVG, цвета дашборда: Сила — луна,
// Лояльность — камень, Влияние — лунный свет.
import { cache } from '../api.js';
import { h, NOM_GLYPH, STATE_RU, plural } from '../ui.js';

const SVGNS = 'http://www.w3.org/2000/svg';
const P = [['s', 'Сила', '#e7e07c'], ['l', 'Лояльность', '#9a9a96'], ['v', 'Влияние', '#f6f2de']];
// Состояния: порядок и цвет (состояние всегда подписано словом — цвет не единственный признак).
const STATES = [
  ['ok', 'цела', 'var(--ok)'], ['damaged', 'повреждена', 'var(--warn)'], ['discard', 'в отбое', '#9a9a96'],
  ['reserve', 'в резерве', '#6f7080'], ['dump', 'на свалке', '#4a4c5a'], ['dead', 'погибла', 'var(--bad)'],
  ['left', 'выбыла из отряда', '#b7b4a0'],
];

function svg(tag, attrs = {}, ...kids) {
  const el = document.createElementNS(SVGNS, tag);
  Object.entries(attrs).forEach(([k, v]) => { if (v != null) el.setAttribute(k, v); });
  kids.flat().forEach((k) => k != null && el.append(k instanceof Node ? k : document.createTextNode(String(k))));
  return el;
}

// Подсказка при наведении: одна на график.
function tipFor(box) {
  const t = h('div', { class: 'chart-tip', hidden: true });
  box.append(t);
  return {
    show(ev, title, lines) {
      t.replaceChildren(h('div', { class: 't' }, title), ...lines.map(([c, label, v]) =>
        h('div', { class: 'r' }, c ? h('i', { style: 'background:' + c }) : null, label + ': ', h('b', {}, v))));
      t.hidden = false;
      const r = box.getBoundingClientRect();
      const x = ev.clientX - r.left, y = ev.clientY - r.top;
      t.style.left = Math.max(0, Math.min(r.width - t.offsetWidth, x + 12)) + 'px';
      t.style.top = Math.max(0, y - t.offsetHeight - 8) + 'px';
    },
    hide() { t.hidden = true; },
  };
}

// Горизонтальные полосы: rows [{label, value, color?, title?, parts?: [[color,label,value]]}]
function hbars(rows, unit) {
  const box = h('div', { class: 'chart' });
  if (!rows.length) { box.append(h('p', { class: 'empty' }, 'Нет данных.')); return box; }
  const W = 520, bh = 22, gap = 8, lw = 190, vw = 34;
  const H = rows.length * (bh + gap);
  const max = Math.max(...rows.map((r) => r.value), 1);
  const scale = (v) => (W - lw - vw) * v / max;
  const tip = tipFor(box);
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': unit });
  rows.forEach((r, i) => {
    const y = i * (bh + gap);
    const g = svg('g', { transform: `translate(0,${y})` });
    const label = r.label.length > 26 ? r.label.slice(0, 25) + '…' : r.label;
    g.append(svg('text', { x: lw - 10, y: bh / 2, dy: '0.35em', 'text-anchor': 'end', class: 'strong' }, label));
    if (r.parts) {
      let acc = 0;
      r.parts.forEach(([c, , v], k) => {
        const w = scale(v);
        g.append(svg('rect', { x: lw + scale(acc) + (k ? 1 : 0), y: 2, width: Math.max(0, w - (k ? 1 : 0)), height: bh - 4,
          rx: k === r.parts.length - 1 ? 4 : 0, fill: c }));
        acc += v;
      });
    } else {
      g.append(svg('rect', { x: lw, y: 2, width: Math.max(2, scale(r.value)), height: bh - 4, rx: 4, fill: r.color || '#e7e07c' }));
    }
    g.append(svg('text', { x: lw + scale(r.value) + 6, y: bh / 2, dy: '0.35em' }, r.value));
    const hit = svg('rect', { x: 0, y: 0, width: W, height: bh, fill: 'transparent' });
    hit.addEventListener('mousemove', (ev) => tip.show(ev, r.title || r.label, r.parts || [[null, unit, r.value]]));
    hit.addEventListener('mouseleave', () => tip.hide());
    g.append(hit);
    s.append(g);
  });
  box.prepend(s);
  return box;
}

// Средние С/Л/В по номиналу: сгруппированные столбики.
function avgBars(groups) {
  const box = h('div', { class: 'chart' });
  if (!groups.length) { box.append(h('p', { class: 'empty' }, 'Нет данных.')); return box; }
  const W = 520, H = 230, m = { t: 8, r: 4, b: 40, l: 28 };
  const max = Math.ceil(Math.max(...groups.flatMap((g) => P.map(([k]) => g[k])), 1));
  const y = (v) => H - m.b - (H - m.b - m.t) * v / max;
  const bw = (W - m.l - m.r) / groups.length;
  const inner = bw * 0.75, pw = inner / 3;
  const tip = tipFor(box);
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': 'Средние параметры по номиналу' });
  const ticks = [0, Math.round(max / 2), max];
  ticks.forEach((tv) => {
    s.append(svg('line', { x1: m.l, x2: W - m.r, y1: y(tv), y2: y(tv), class: 'grid' }));
    s.append(svg('text', { x: m.l - 6, y: y(tv), dy: '0.35em', 'text-anchor': 'end' }, tv));
  });
  groups.forEach((g, i) => {
    const x0 = m.l + i * bw + (bw - inner) / 2;
    P.forEach(([k, , c], j) => {
      const top = y(g[k]);
      s.append(svg('rect', { x: x0 + j * pw + 1, y: top, width: pw - 2, height: Math.max(0, y(0) - top), rx: 3, fill: c }));
    });
    s.append(svg('text', { x: x0 + inner / 2, y: H - m.b + 16, 'text-anchor': 'middle', class: 'strong' }, NOM_GLYPH[g.nominal] || ''));
    s.append(svg('text', { x: x0 + inner / 2, y: H - m.b + 32, 'text-anchor': 'middle' }, g.nominal));
    const hit = svg('rect', { x: m.l + i * bw, y: 0, width: bw, height: H - m.b, fill: 'transparent' });
    hit.addEventListener('mousemove', (ev) => tip.show(ev, g.nominal + ' · ' + plural(g.n, 'фигура', 'фигуры', 'фигур'),
      P.map(([k, label, c]) => [c, label, g[k].toLocaleString('ru-RU', { maximumFractionDigits: 1 })])));
    hit.addEventListener('mouseleave', () => tip.hide());
    s.append(hit);
  });
  s.append(svg('line', { x1: m.l, x2: W - m.r, y1: y(0), y2: y(0), class: 'axis' }));
  box.prepend(s);
  return box;
}

// Полоса долей состояний (одна строка, подписи — в легенде под ней).
function statesStrip(counts, total) {
  const box = h('div', { class: 'chart' });
  const W = 520, H = 26;
  const tip = tipFor(box);
  const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: '100%', role: 'img', 'aria-label': 'Состояния фигур' });
  let x = 0;
  STATES.forEach(([k, label, c]) => {
    const n = counts[k] || 0;
    if (!n) return;
    const w = W * n / total;
    const r = svg('rect', { x: x + 1, y: 2, width: Math.max(1, w - 2), height: H - 4, rx: 4, fill: c });
    r.addEventListener('mousemove', (ev) => tip.show(ev, label, [[c, 'фигур', n + ' из ' + total]]));
    r.addEventListener('mouseleave', () => tip.hide());
    s.append(r);
    x += w;
  });
  box.prepend(s);
  return box;
}

const legend = (items) => h('div', { class: 'chart-legend' }, items.map(([c, label]) => h('span', {}, h('i', { style: 'background:' + c }), label)));

export function statsCard(d, gameId) {
  const all = d.squads.flatMap((sq) => d.figsOf(sq.id).map(({ fig, sf }) => ({ fig, sf, sq })));
  // Фигуры, которые раньше стояли в отрядах этой игры, а потом были убраны (правка, роспуск отряда).
  const nowIn = new Set((d.allSquadFigures || []).map((x) => x.figure_id));
  const lastSquad = {};
  (d.lineup || []).forEach((e) => {
    const ids = e.kind === 'squad_save' ? ((e.data && e.data.figures) || []) : [e.figure_id];
    ids.forEach((id) => { if (id != null) lastSquad[id] = e.squad_id; });
  });
  Object.entries(lastSquad).forEach(([id, sqid]) => {
    id = Number(id);
    const fig = d.figById[id];
    if (!fig || nowIn.has(id)) return;
    const sq = d.squadById[sqid] || { id: sqid, name: 'распущенный отряд', strategist_id: null };
    all.push({ fig, sf: { state: 'left', borrowed: false }, sq, left: true });
  });
  if (!all.length) return h('section', { class: 'card' }, h('h2', {}, 'Статистика игры'), h('p', { class: 'empty' }, 'Отряды ещё не собраны.'));
  const stateOf = (x) => (x.fig.status === 'dead' && x.fig.died_game === gameId ? 'dead' : x.sf.state);
  const count = (list) => { const c = {}; list.forEach((x) => { const k = stateOf(x); c[k] = (c[k] || 0) + 1; }); return c; };
  const states = count(all);
  const borrowed = all.filter((x) => x.sf.borrowed).length;
  const sum = (k) => all.reduce((n, x) => n + (Number(x.fig[k]) || 0), 0);
  const noms = cache.nominals.map((n) => n.name).filter((n) => all.some((x) => x.fig.nominal === n));

  // плитки
  const tiles = h('div', { class: 'tiles' },
    h('div', { class: 'tile big' }, h('b', {}, all.length), h('span', {}, 'фигур в отрядах (сейчас и раньше)')),
    noms.map((n) => h('div', { class: 'tile' }, h('b', {}, NOM_GLYPH[n] + ' ' + all.filter((x) => x.fig.nominal === n).length), h('span', {}, n))),
    h('div', { class: 'tile' }, h('b', {}, d.squads.length), h('span', {}, plural(d.squads.length, 'отряд', 'отряда', 'отрядов').replace(/^\d+ /, ''))),
    h('div', { class: 'tile' }, h('b', {}, d.strategists.length), h('span', {}, 'стратегов')),
    P.map(([k, label]) => h('div', { class: 'tile' }, h('b', {}, sum(k)), h('span', {}, label + ' всего'))));

  // состояния
  const stateTiles = h('div', { class: 'tiles' },
    STATES.map(([k, label, c]) => h('div', { class: 'tile state' }, h('b', {}, h('i', { style: 'background:' + c }), states[k] || 0), h('span', {}, label))),
    h('div', { class: 'tile state' }, h('b', {}, h('i', { style: 'background: var(--info)' }), borrowed), h('span', {}, 'взяты у противника')));
  const byStrategist = h('div', { class: 'tablewrap', style: 'max-height:none' }, h('table', {},
    h('thead', {}, h('tr', {}, h('th', { class: 'plain' }, 'Стратег'), STATES.map(([, label]) => h('th', { class: 'plain num' }, label)),
      h('th', { class: 'plain num' }, 'взяты'))),
    h('tbody', {}, [...d.order, ...(all.some((x) => x.sq.strategist_id == null) ? [{ id: null }] : [])].map((s) => {
      const list = all.filter((x) => x.sq.strategist_id === s.id);
      const c = count(list);
      return h('tr', {}, h('td', {}, s.id == null ? 'из распущенных отрядов' : d.label(s.id)), STATES.map(([k]) => h('td', { class: 'num' + (c[k] ? '' : ' muted') }, c[k] || 0)),
        h('td', { class: 'num' }, list.filter((x) => x.sf.borrowed).length));
    }))));

  // графики
  const rankRows = noms.map((n) => ({ label: NOM_GLYPH[n] + ' ' + n, value: all.filter((x) => x.fig.nominal === n).length }));
  const avg = noms.map((n) => {
    const g = all.filter((x) => x.fig.nominal === n);
    const a = (k) => Math.round(g.reduce((t, x) => t + x.fig[k], 0) / g.length * 10) / 10;
    return { nominal: n, n: g.length, s: a('s'), l: a('l'), v: a('v') };
  });
  const top = [...all].sort((a, b) => (b.fig.s + b.fig.l + b.fig.v) - (a.fig.s + a.fig.l + a.fig.v) || a.fig.name.localeCompare(b.fig.name, 'ru'))
    .slice(0, 10).map((x) => ({ label: (NOM_GLYPH[x.fig.nominal] || '') + ' ' + x.fig.name, title: x.fig.name + ' — «' + x.sq.name + '»' + (x.left ? ' (выбыла из отряда)' : ''),
      value: x.fig.s + x.fig.l + x.fig.v, parts: P.map(([k, label, c]) => [c, label, x.fig[k]]) }));
  const propCount = {};
  all.forEach((x) => (x.fig.properties || []).forEach((p) => { propCount[p] = (propCount[p] || 0) + 1; }));
  const props = Object.entries(propCount).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'ru')).slice(0, 10)
    .map(([p, n]) => ({ label: p, value: n }));

  return h('section', { class: 'card' }, h('h2', {}, 'Статистика игры'),
    h('p', { class: 'muted small', style: 'margin:0' }, 'По фигурам, которые стоят или стояли в отрядах этой игры. Наведите на график — появятся подробности.'),
    tiles,
    h('h3', {}, 'Состояния фигур'),
    stateTiles, statesStrip(states, all.length), legend(STATES.map(([, label, c]) => [c, label])), byStrategist,
    h('div', { class: 'grid' },
      h('div', { class: 'stack', style: 'align-content: start' }, h('h3', {}, 'Сколько фигур каждого номинала'), hbars(rankRows, 'Фигур')),
      h('div', { class: 'stack', style: 'align-content: start' }, h('h3', {}, 'Средние параметры по номиналу'), legend(P.map(([, label, c]) => [c, label])), avgBars(avg))),
    h('div', { class: 'grid' },
      h('div', { class: 'stack', style: 'align-content: start' }, h('h3', {}, 'Самые сильные фигуры'), h('p', { class: 'muted small', style: 'margin:0' }, 'Длина полосы — сумма Силы, Лояльности и Влияния.'),
        legend(P.map(([, label, c]) => [c, label])), hbars(top, 'Сумма')),
      h('div', { class: 'stack', style: 'align-content: start' }, h('h3', {}, 'Самые частые свойства'), hbars(props, 'Фигур'))));
}
