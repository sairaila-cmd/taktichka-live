// Персонажи: Ресурсы (видны всем), доп. отряды за Влияние, число фигур; передача Ресурсов.
import { rows, call, cache, session, isAdmin, loadRefs } from '../api.js';
import { h, btn, modal, form, act, refresh } from '../ui.js';
import { res } from './common.js';

export default async function peopleView(root) {
  await loadRefs(true);
  const [owners, figures, wallets, members, games] = await Promise.all([
    rows('figure_owners'), rows('figures', (q) => q.eq('status', 'active'), 'id'),
    rows('strategists', (q) => q.not('wallet', 'is', null)),
    rows('strategist_members'), rows('games', (q) => q.neq('status', 'closed')),
  ]);
  const activeIds = new Set(figures.map((f) => f.id));
  const figCount = {};
  owners.forEach((o) => { if (activeIds.has(o.figure_id)) figCount[o.player_id] = (figCount[o.player_id] || 0) + 1; });
  const openGames = new Set(games.map((g) => g.id));
  const inWallet = {};   // игрок → общий кошелёк пары в незакрытой игре (его Ресурсы сейчас там)
  wallets.filter((w) => openGames.has(w.game_id)).forEach((w) => {
    members.filter((m) => m.strategist_id === w.id).forEach((m) => { inWallet[m.player_id] = w.wallet; });
  });

  const people = cache.players.filter((p) => !p.is_admin);
  const actions = [];
  if (session.me && !session.me.is_admin) actions.push(btn('Передать Ресурсы', () => transfer(), 'primary'));

  root.append(
    h('h1', { class: 'page-title' }, 'Персонажи'),
    h('p', { class: 'lede' }, 'Ресурсы каждого видны всем. Начисляет ведущий; передать свои Ресурсы другому можно по личному коду.'),
    h('section', { class: 'card' },
      h('header', {}, h('h2', {}, 'Ресурсы и фигуры'), h('div', { class: 'row' }, actions)),
      h('div', { class: 'tablewrap' }, h('table', {},
        h('thead', {}, h('tr', {},
          h('th', { class: 'plain' }, 'Персонаж'), h('th', { class: 'plain num' }, 'Ресурсы'),
          h('th', { class: 'plain num' }, 'Фигур'), h('th', { class: 'plain num', title: 'за каждые 3 точки Влияния' }, 'Доп. отряды'),
          isAdmin() ? h('th', { class: 'plain' }, '') : null)),
        h('tbody', {}, people.map((p) => h('tr', {},
          h('td', {}, p.name),
          h('td', { class: 'num' }, p.resources,
            inWallet[p.id] != null ? h('span', { class: 'muted small', title: 'пока пара играет, Ресурсы напарников лежат в общем кошельке' }, ' · общий кошелёк пары: ' + inWallet[p.id]) : null),
          h('td', { class: 'num' }, figCount[p.id] || 0),
          h('td', { class: 'num' }, p.bonus_squads || 0),
          isAdmin() ? h('td', {}, h('div', { class: 'row' },
            btn('± Ресурсы', () => grant(p), 'small'), btn('Доп. отряды', () => bonus(p), 'small'))) : null)))))));

  function transfer() {
    modal('Передать Ресурсы', (close) => form([
      { name: 'to', label: 'Кому', type: 'select', required: true, options: people.filter((p) => p.id !== session.me.id).map((p) => [p.id, p.name]) },
      { name: 'amount', label: 'Сколько (у вас ' + (inWallet[session.me.id] ?? (cache.playerById[session.me.id] || {}).resources) + (inWallet[session.me.id] != null ? ', общий кошелёк пары' : '') + ')', type: 'number', value: 1, min: 1 },
      { name: 'comment', label: 'За что' },
    ], 'Передать', (v) => act(() => call('api_resources_transfer', { p_to: Number(v.to), p_amount: v.amount, p_comment: v.comment }),
      'Передано', () => { close(); refresh(); })));
  }
  function grant(p) {
    modal('Ресурсы: ' + p.name, (close) => form([
      { name: 'amount', label: 'Сколько начислить (минус — списать); сейчас ' + res(inWallet[p.id] ?? p.resources), type: 'number', value: 1,
        hint: inWallet[p.id] != null ? 'Персонаж играет в паре — Ресурсы пойдут в общий кошелёк пары.' : null },
      { name: 'comment', label: 'Основание' },
    ], 'Сохранить', (v) => act(() => call('api_admin_resources', { p_player: p.id, p_amount: v.amount, p_comment: v.comment }),
      'Готово', () => { close(); refresh(); })));
  }
  function bonus(p) {
    modal('Доп. отряды: ' + p.name, (close) => form([
      { name: 'bonus', label: 'Сколько доп. отрядов (1 за каждые 3 точки Влияния)', type: 'number', value: p.bonus_squads || 0, min: 0 },
      { name: 'comment', label: 'Основание' },
    ], 'Сохранить', (v) => act(() => call('api_admin_bonus', { p_player: p.id, p_bonus: v.bonus ?? 0, p_comment: v.comment }),
      'Готово', () => { close(); refresh(); })));
  }
}
