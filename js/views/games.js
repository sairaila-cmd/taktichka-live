// Список игр; ведущий создаёт новую.
import { rowsAll, call, isAdmin } from '../api.js?v=202610151523';
import { h, btn, modal, form, act, fmtTime, STATUS_RU, GIFT_RU, plural } from '../ui.js?v=202610151523';

export default async function gamesView(root) {
  const [games, strategists, gifts] = await Promise.all([
    rowsAll('games', (q) => q.order('id', { ascending: false })),
    rowsAll('strategists', (q) => q.order('id'), 'id, game_id'),
    rowsAll('game_gifts', (q) => q.order('game_id').order('gift')),
  ]);
  const actions = isAdmin() ? [btn('+ Новая игра', create, 'primary')] : [];
  root.append(
    h('h1', { class: 'page-title' }, 'Игры'),
    h('p', { class: 'lede' }, 'На каждую игру стратеги собирают отряды заново. Составы видны всем сразу.'),
    h('section', { class: 'card' },
      h('header', {}, h('h2', {}, 'Все игры'), h('div', { class: 'row' }, actions)),
      games.length ? h('div', { class: 'tablewrap' }, h('table', {},
        h('thead', {}, h('tr', {}, h('th', { class: 'plain' }, 'Игра'), h('th', { class: 'plain' }, 'Состояние'),
          h('th', { class: 'plain' }, 'Начало'), h('th', { class: 'plain num' }, 'Стратегов'), h('th', { class: 'plain wide-only' }, 'Дары лун'))),
        h('tbody', {}, games.map((g) => h('tr', { class: 'click', onclick: () => { location.hash = '#/game/' + g.id; } },
          h('td', {}, h('a', { href: '#/game/' + g.id }, g.title)),
          h('td', {}, h('span', { class: 'badge ' + (g.status === 'running' ? 'ok' : g.status === 'draft' ? 'moon' : '') }, STATUS_RU[g.status])),
          h('td', { class: 'muted' }, fmtTime(g.starts_at)),
          h('td', { class: 'num' }, strategists.filter((s) => s.game_id === g.id).length),
          h('td', { class: 'wide-only muted small' }, gifts.filter((x) => x.game_id === g.id).map((x) => GIFT_RU[x.gift].split(' — ')[0]).join(', ')))))))
        : h('p', { class: 'empty' }, 'Игр пока нет.' + (isAdmin() ? ' Создайте первую.' : ''))));

  function create() {
    modal('Новая игра', (close) => form([
      { name: 'title', label: 'Название', required: true },
      { name: 'starts', label: 'Начало (необязательно)', type: 'datetime-local' },
    ], 'Создать', (v) => act(() => call('api_admin_game', {
      p_id: null, p_title: v.title, p_starts_at: v.starts ? new Date(v.starts).toISOString() : null, p_status: 'draft',
    }), 'Игра создана', (id) => { close(); location.hash = '#/game/' + id; })));
  }
}
