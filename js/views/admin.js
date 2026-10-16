// Раздел ведущего: игры, конфликты совладения, отмена записей журнала, памятка.
import { rows, rowsAll, call, isAdmin } from '../api.js?v=202610161643';
import { h, card, btn, act, refresh, fmtTime, STATUS_RU } from '../ui.js?v=202610161643';
import { describe, gameBadge } from './common.js?v=202610161643';

export default async function adminView(root) {
  if (!isAdmin()) {
    root.append(card('Только для ведущего', h('p', { class: 'muted', style: 'margin:0' }, 'Войдите кодом ведущего.')));
    return;
  }
  const [games, conflicts, events, figures, squads] = await Promise.all([
    rowsAll('games', (q) => q.order('id', { ascending: false })),
    rowsAll('figure_conflicts', (q) => q.order('game_id').order('figure_id')),
    rows('events', (q) => q.order('at', { ascending: false }).order('id', { ascending: false }).limit(60)),
    rowsAll('figures', (q) => q.order('id'), 'id, name'),
    rowsAll('squads', (q) => q.order('id'), 'id, name'),
  ]);
  const maps = { figures: Object.fromEntries(figures.map((f) => [f.id, f])), squads: Object.fromEntries(squads.map((s) => [s.id, s])),
    games: Object.fromEntries(games.map((g) => [g.id, g])) };
  root.append(
    h('h1', { class: 'page-title' }, 'Ведущему'),
    h('p', { class: 'lede' }, h('a', { href: '#/help/admin' }, 'Инструкция для ведущего')),
    h('div', { class: 'grid' },
      card('Игры', games.length ? h('ul', { class: 'small', style: 'margin:0; padding-left:1.2em' }, games.map((g) =>
        h('li', {}, h('a', { href: '#/game/' + g.id }, g.title), ' — ' + STATUS_RU[g.status]))) : h('p', { class: 'empty' }, 'Игр нет.'),
        h('p', { class: 'muted small', style: 'margin:0' }, 'Создать игру — в разделе «Игры». Дары лун, инициатива, Эхо, напарники и итоги — на странице игры, в блоке «Ведущему».')),
      card('Конфликты совладения', conflicts.length ? conflicts.map((c) => h('div', { class: 'small' },
        '◆ «' + c.name + '» в игре ', h('a', { href: '#/game/' + c.game_id }, '#' + c.game_id), ': ' + c.squads.length + ' отряда')) :
        h('p', { class: 'empty' }, 'Нет: ни одна фигура не стоит у двух стратегов сразу.')),
      card('Личные коды',
        h('p', { class: 'small', style: 'margin:0' }, 'Коды персонажей лежат только у вас на компьютере: ', h('code', {}, '~/.config/taktichka/codes.csv'),
          '. Раздавайте их в личку. В базе хранятся лишь отпечатки кодов, сами коды восстановить из неё нельзя.'),
        h('p', { class: 'muted small', style: 'margin:0' }, 'Новый персонаж или смена кода — попросите Claude: он добавит персонажа и выдаст файл для SQL Editor.'))),
    card('Последние записи журнала',
      h('p', { class: 'muted small', style: 'margin:0' }, '«Отменить» только помечает запись отменённой. Само исправление — обычным действием (передать обратно, начислить, отменить шаг боя).'),
      h('ul', { class: 'log' }, events.map((ev) => h('li', { class: ev.reverted ? 'reverted' : '' },
        h('time', {}, fmtTime(ev.at)),
        h('div', { class: 'row' }, h('span', { style: 'flex:1' }, gameBadge(ev, maps), describe(ev, maps), ev.comment ? h('span', { class: 'muted' }, ' — ' + ev.comment) : null),
          ev.reverted || ev.kind === 'revert' ? null : btn('Отменить', () => act(() => call('api_admin_revert', { p_event: ev.id, p_comment: null }), 'Запись помечена', refresh), 'small')))))));
}
