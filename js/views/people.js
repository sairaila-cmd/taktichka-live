// Персонажи: стратеги выбранной игры (напарники — одной строкой) с Ресурсами, отрядами и фигурами;
// ниже, свёрнуто, — персонажи, не участвующие в этой игре. Передача Ресурсов, кнопки ведущего.
import { rowsAll, call, cache, session, isAdmin, loadPlayers } from '../api.js?v=202610161733';
import { h, btn, modal, form, act, refresh, STATUS_RU } from '../ui.js?v=202610161733';
import { res, pname } from './common.js?v=202610161733';

export default async function peopleView(root, gameParam) {
  await loadPlayers(true);
  const games = await rowsAll('games', (q) => q.neq('status', 'closed').order('id', { ascending: false }));
  // По умолчанию — последняя идущая игра, если её нет — последняя в сборе отрядов.
  const game = games.find((g) => g.id === Number(gameParam)) || games.find((g) => g.status === 'running') || games[0] || null;
  const people = cache.players.filter((p) => !p.is_admin);

  const [owners, activeFigs, strategists, members, squads, sfs, gifts] = await Promise.all([
    rowsAll('figure_owners', (q) => q.order('figure_id').order('player_id')),
    rowsAll('figures', (q) => q.eq('status', 'active').order('id'), 'id'),
    game ? rowsAll('strategists', (q) => q.eq('game_id', game.id).order('id')) : [],
    game ? rowsAll('strategist_members', (q) => q.eq('game_id', game.id).order('strategist_id').order('player_id')) : [],
    game ? rowsAll('squads', (q) => q.eq('game_id', game.id).order('id'), 'id, strategist_id') : [],
    game ? rowsAll('squad_figures', (q) => q.eq('game_id', game.id).order('squad_id').order('figure_id'), 'squad_id, strategist_id') : [],
    game ? rowsAll('game_gifts', (q) => q.eq('game_id', game.id).order('game_id').order('gift')) : [],
  ]);
  const membersOf = (sid) => members.filter((m) => m.strategist_id === sid).map((m) => m.player_id);
  const label = (sid) => membersOf(sid).map(pname).join(' и ');
  const nSquads = (sid) => squads.filter((s) => s.strategist_id === sid).length;
  const nFigs = (sid) => sfs.filter((x) => x.strategist_id === sid).length;
  const money = (s) => (s.wallet != null ? s.wallet : ((cache.playerById[membersOf(s.id)[0]] || {}).resources ?? 0));
  const bonusOf = (sid) => Math.max(0, ...membersOf(sid).map((m) => (cache.playerById[m] || {}).bonus_squads || 0));

  // Порядок хода как на странице игры: по инициативе; при Чёрной луне места 1–3 — стратегам с 1–2 отрядами.
  const byInit = strategists.slice().sort((a, b) => ((b.initiative ?? -1e9) - (a.initiative ?? -1e9)) || a.id - b.id);
  let order = byInit;
  if (gifts.some((g) => g.gift === 'chernaya')) {
    const top = byInit.filter((s) => nSquads(s.id) < 3).slice(0, 3);
    order = top.concat(byInit.filter((s) => !top.includes(s)));
  }

  const inGame = new Set(members.map((m) => m.player_id));
  const others = people.filter((p) => !inGame.has(p.id));
  const activeIds = new Set(activeFigs.map((f) => f.id));
  const owned = {};
  owners.forEach((o) => { if (activeIds.has(o.figure_id)) owned[o.player_id] = (owned[o.player_id] || 0) + 1; });
  const myStrategist = session.me ? strategists.find((s) => membersOf(s.id).includes(session.me.id)) : null;

  const actions = [];
  if (session.me && !session.me.is_admin) actions.push(btn('Передать Ресурсы', () => transfer(), 'primary'));
  const picker = games.length > 1 ? h('select', { 'aria-label': 'Игра', onchange: (e) => { location.hash = '#/people/' + e.target.value; } },
    games.map((g) => h('option', { value: g.id, selected: game && g.id === game.id }, g.title + ' — ' + STATUS_RU[g.status]))) : null;

  // root.append выводит null как текст «null» — пустые части отбрасываем.
  root.append(...[
    h('h1', { class: 'page-title' }, 'Персонажи'),
    h('p', { class: 'lede' }, game
      ? h('span', {}, 'Стратеги игры ', h('a', { href: '#/game/' + game.id }, '«' + game.title + '»'), '. Ресурсы видны всем; у напарников они общие.')
      : 'Сейчас игр нет.'),
    picker ? h('div', { class: 'row', style: 'justify-content:center' }, h('label', { class: 'inline' }, 'Игра:', picker)) : null,
    game ? h('section', { class: 'card' },
      h('header', {}, h('h2', {}, 'Стратеги и Ресурсы'), h('div', { class: 'row' }, actions)),
      order.length ? h('div', { class: 'tablewrap' }, h('table', {},
        h('thead', {}, h('tr', {},
          h('th', { class: 'plain' }, 'Стратег'), h('th', { class: 'plain num' }, 'Ресурсы'),
          h('th', { class: 'plain num' }, 'Отрядов'), h('th', { class: 'plain num' }, 'Фигур в отрядах'),
          h('th', { class: 'plain num', title: 'за каждые 3 точки Влияния; у пары — по большему' }, 'Доп. отряды'),
          isAdmin() ? h('th', { class: 'plain' }, '') : null)),
        h('tbody', {}, order.map((s) => h('tr', { class: myStrategist && myStrategist.id === s.id ? 'mine-row' : '' },
          h('td', {}, h('a', { href: '#/game/' + game.id }, label(s.id)),
            membersOf(s.id).length > 1 ? h('span', { class: 'badge', style: 'margin-left:6px' }, 'напарники') : null),
          h('td', { class: 'num' }, money(s), s.wallet != null ? h('span', { class: 'muted small' }, ' общий кошелёк') : null),
          h('td', { class: 'num' }, nSquads(s.id)),
          h('td', { class: 'num' }, nFigs(s.id)),
          h('td', { class: 'num' }, bonusOf(s.id)),
          isAdmin() ? h('td', {}, h('div', { class: 'row' },
            btn('± Ресурсы', () => grant(membersOf(s.id), s), 'small'),
            btn('Доп. отряды', () => bonus(membersOf(s.id)), 'small'))) : null)))))
        : h('p', { class: 'empty' }, 'В этой игре пока нет стратегов.')) : null,
    h('section', { class: 'card' },
      h('details', { open: game ? null : true },
        h('summary', {}, (game ? 'Не участвуют в этой игре' : 'Все персонажи') + ' (' + (game ? others : people).length + ')'),
        h('div', { class: 'tablewrap', style: 'margin-top: 10px' }, h('table', {},
          h('thead', {}, h('tr', {},
            h('th', { class: 'plain' }, 'Персонаж'), h('th', { class: 'plain num' }, 'Ресурсы'),
            h('th', { class: 'plain num' }, 'Фигур во владении'), h('th', { class: 'plain num' }, 'Доп. отряды'),
            isAdmin() ? h('th', { class: 'plain' }, '') : null)),
          h('tbody', {}, (game ? others : people).map((p) => h('tr', {},
            h('td', {}, p.name), h('td', { class: 'num' }, p.resources), h('td', { class: 'num' }, owned[p.id] || 0),
            h('td', { class: 'num' }, p.bonus_squads || 0),
            isAdmin() ? h('td', {}, h('div', { class: 'row' },
              btn('± Ресурсы', () => grant([p.id], null), 'small'), btn('Доп. отряды', () => bonus([p.id]), 'small'))) : null)))))))].filter(Boolean));

  function transfer() {
    const have = myStrategist ? money(myStrategist) : (cache.playerById[session.me.id] || {}).resources;
    const mates = myStrategist ? membersOf(myStrategist.id) : [session.me.id];
    modal('Передать Ресурсы', (close) => form([
      { name: 'to', label: 'Кому', type: 'select', required: true,
        options: people.filter((p) => !mates.includes(p.id)).map((p) => [p.id, p.name]) },
      { name: 'amount', label: 'Сколько (у вас ' + have + (myStrategist && myStrategist.wallet != null ? ', общий кошелёк пары' : '') + ')', type: 'number', value: 1, min: 1 },
      { name: 'comment', label: 'За что' },
    ], 'Передать', (v) => act(() => call('api_resources_transfer', { p_to: Number(v.to), p_amount: v.amount, p_comment: v.comment, p_game: game ? game.id : null }),
      'Передано', () => { close(); refresh(); })));
  }
  // Начисление: у пары Ресурсы всё равно уходят в общий кошелёк, поэтому начисляем первому из пары.
  // Стратегу — в выбранную игру (кошелёк пары именно этой игры); не участвующему — на личный баланс.
  function grant(ids, s) {
    const who = ids.map(pname).join(' и ');
    const now = s ? money(s) : (cache.playerById[ids[0]] || {}).resources;
    modal('Ресурсы: ' + who + (s ? ' · «' + game.title + '»' : ''), (close) => form([
      { name: 'amount', label: 'Сколько начислить (минус — списать); сейчас ' + res(now), type: 'number', value: 1,
        hint: s && s.wallet != null ? 'Пара — Ресурсы пойдут в общий кошелёк этой игры.' : null },
      { name: 'comment', label: 'Основание' },
    ], 'Сохранить', (v) => act(() => call('api_admin_resources', { p_player: ids[0], p_amount: v.amount, p_comment: v.comment, p_game: s ? game.id : null }),
      'Готово', () => { close(); refresh(); })));
  }
  // Доп. отряды — личные (у пары в игре считается больший из двух).
  function bonus(ids) {
    modal('Доп. отряды', (close) => form([
      ids.length > 1 ? { name: 'p', label: 'Кому', type: 'select', options: ids.map((id) => [id, pname(id) + ' (сейчас ' + ((cache.playerById[id] || {}).bonus_squads || 0) + ')']) } : null,
      { name: 'bonus', label: 'Сколько доп. отрядов (1 за каждые 3 точки Влияния)', type: 'number', min: 0,
        value: ids.length === 1 ? ((cache.playerById[ids[0]] || {}).bonus_squads || 0) : 0 },
      { name: 'comment', label: 'Основание' },
    ].filter(Boolean), 'Сохранить', (v) => act(() => call('api_admin_bonus', { p_player: Number(v.p || ids[0]), p_bonus: v.bonus ?? 0, p_comment: v.comment }),
      'Готово', () => { close(); refresh(); })));
  }
}
