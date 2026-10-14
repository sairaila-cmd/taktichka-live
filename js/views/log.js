// Общий журнал: кто, когда и что менял.
import { rows } from '../api.js';
import { h } from '../ui.js';
import { logList } from './common.js';

export default async function logView(root) {
  const [events, figures, squads] = await Promise.all([
    rows('events', (q) => q.order('at', { ascending: false }).limit(300)),
    rows('figures', (q) => q, 'id, name'), rows('squads', (q) => q, 'id, name'),
  ]);
  const maps = { figures: Object.fromEntries(figures.map((f) => [f.id, f])), squads: Object.fromEntries(squads.map((s) => [s.id, s])) };
  root.append(
    h('h1', { class: 'page-title' }, 'Журнал'),
    h('p', { class: 'lede' }, 'Последние 300 изменений. Отменённые ведущим записи зачёркнуты.'),
    h('section', { class: 'card' }, logList(events, maps)));
}
