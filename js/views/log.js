// Общий журнал: кто, когда и что менял. Порциями по 300, «Показать ещё» и выгрузка всего журнала в CSV.
import { rows } from '../api.js?v=202610151204';
import { h, btn, toast, plural } from '../ui.js?v=202610151204';
import { logItem, describe, gameTitle, pname } from './common.js?v=202610151204';

const PAGE = 300;
const CHUNK = 1000; // Supabase отдаёт не больше 1000 строк за запрос
const newest = (q) => q.order('at', { ascending: false }).order('id', { ascending: false });

export default async function logView(root) {
  const [events, figures, squads, games] = await Promise.all([
    rows('events', (q) => newest(q).range(0, PAGE - 1)),
    rows('figures', (q) => q, 'id, name'), rows('squads', (q) => q, 'id, name'), rows('games', (q) => q, 'id, title'),
  ]);
  const maps = { figures: Object.fromEntries(figures.map((f) => [f.id, f])), squads: Object.fromEntries(squads.map((s) => [s.id, s])),
    games: Object.fromEntries(games.map((g) => [g.id, g])) };
  let shown = 0;
  const list = h('ul', { class: 'log' });
  const lede = h('p', { class: 'lede' });
  const more = btn('Показать ещё ' + PAGE, () => loadMore());
  const done = h('p', { class: 'muted small' }, 'Это все записи.');
  const download = btn('Скачать весь журнал (CSV)', () => saveAll());
  const add = (batch) => {
    batch.forEach((ev) => list.append(logItem(ev, maps)));
    shown += batch.length;
    lede.textContent = 'Показано ' + plural(shown, 'запись', 'записи', 'записей') +
      ', новые сверху. Отменённые ведущим записи зачёркнуты; у записей игры — метка с названием игры.';
    const end = batch.length < PAGE;
    more.hidden = end; done.hidden = !end;
  };

  root.append(
    h('h1', { class: 'page-title' }, 'Журнал'),
    lede,
    h('section', { class: 'card' },
      h('header', {}, h('h2', {}, 'Записи'), h('div', { class: 'row' }, download)),
      events.length ? list : h('p', { class: 'empty' }, 'Записей пока нет.'),
      h('div', { class: 'row' }, more, done)));
  add(events);

  async function loadMore() {
    more.disabled = true;
    try { add(await rows('events', (q) => newest(q).range(shown, shown + PAGE - 1))); }
    catch (e) { toast(e.message, true); }
    finally { more.disabled = false; }
  }

  async function saveAll() {
    download.disabled = true;
    const all = [];
    try {
      for (;;) {
        download.textContent = 'Загрузка… ' + all.length;
        const batch = await rows('events', (q) => newest(q).range(all.length, all.length + CHUNK - 1));
        all.push(...batch);
        if (batch.length < CHUNK) break;
      }
      const cell = (v) => { const s = v == null ? '' : String(v); return /[";\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
      const time = (ts) => { const d = new Date(ts); const p = (n) => String(n).padStart(2, '0');
        return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()); };
      const lines = [['№', 'Время', 'Игра', 'Кто', 'Событие', 'Комментарий', 'Отменено']].concat(all.map((ev) => [
        ev.id, time(ev.at), gameTitle(ev, maps), ev.actor ? pname(ev.actor) : '', describe(ev, maps), ev.comment || '', ev.reverted ? 'да' : '']));
      const csv = '﻿' + lines.map((r) => r.map(cell).join(';')).join('\r\n') + '\r\n';
      const a = h('a', { href: URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })),
        download: 'taktichka-журнал-' + new Date().toISOString().slice(0, 10) + '.csv' });
      document.body.append(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 10000);
      toast('Скачано записей: ' + all.length);
    } catch (e) { toast(e.message, true); }
    finally { download.disabled = false; download.textContent = 'Скачать весь журнал (CSV)'; }
  }
}
