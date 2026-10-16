// Тактичка онлайн: маршруты (#/…), вход по коду, отрисовка разделов.
import { restore, login, logout, session, loadRefs, isAdmin } from './api.js?v=202610161008';
import { h, clear, toast } from './ui.js?v=202610161008';
import figuresView from './views/figures.js?v=202610161008';
import peopleView from './views/people.js?v=202610161008';
import gamesView from './views/games.js?v=202610161008';
import gameView from './views/game.js?v=202610161008';
import battleView from './views/battle.js?v=202610161008';
import rulesView from './views/rules.js?v=202610161008';
import logView from './views/log.js?v=202610161008';
import adminView from './views/admin.js?v=202610161008';
import helpView from './views/help.js?v=202610161008';

const ROUTES = [
  [/^#?\/?$/, 'figures', figuresView],
  [/^#\/figure\/(\d+)$/, 'figures', figuresView],
  [/^#\/figures\/(\d+)$/, 'figures', (root, game) => figuresView(root, null, game)],
  [/^#\/people$/, 'people', peopleView],
  [/^#\/people\/(\d+)$/, 'people', peopleView],
  [/^#\/games$/, 'games', gamesView],
  [/^#\/game\/(\d+)$/, 'games', gameView],
  [/^#\/battle\/(\d+)$/, 'games', battleView],
  [/^#\/rules$/, 'rules', rulesView],
  [/^#\/log$/, 'log', logView],
  [/^#\/admin$/, 'admin', adminView],
  [/^#\/help$/, 'help', helpView],
  [/^#\/help\/(admin)$/, 'help', helpView],
];

let cleanup = null;
let renderSeq = 0;

async function render() {
  const seq = ++renderSeq;
  if (cleanup) { try { cleanup(); } catch { /* уже отписаны */ } cleanup = null; }
  const view = document.getElementById('view');
  const hash = location.hash || '#/';
  const route = ROUTES.find(([re]) => re.test(hash)) || ROUTES[0];
  const params = (hash.match(route[0]) || []).slice(1);
  document.querySelectorAll('.nav a').forEach((a) => {
    if (a.dataset.route === route[1]) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  });
  clear(view, h('p', { class: 'loading' }, 'Загрузка…'));
  try {
    await loadRefs();
    const root = h('div', { class: 'stack', style: 'gap: var(--gap)' });
    const c = await route[2](root, ...params);
    if (seq !== renderSeq) { if (typeof c === 'function') c(); return; }
    clear(view, root);
    cleanup = typeof c === 'function' ? c : null;
  } catch (e) {
    if (seq !== renderSeq) return;
    clear(view, h('section', { class: 'card' }, h('h2', {}, 'Не удалось загрузить'),
      h('p', { class: 'muted' }, e.message || String(e)),
      h('p', { class: 'muted small' }, 'Если база долго не открывалась, её мог «усыпить» Supabase — ведущему нужно разбудить проект в панели.')));
  }
}

function renderWho() {
  const box = document.getElementById('who');
  document.getElementById('nav-admin').classList.toggle('hidden', !isAdmin());
  if (session.me) {
    clear(box, h('span', {}, 'Вы: ', h('span', { class: 'me' }, session.me.name), session.me.is_admin ? ' (ведущий)' : ''),
      h('button', { class: 'btn small', type: 'button', onclick: () => { logout(); toast('Вы вышли'); } }, 'Выйти'));
  } else {
    const input = h('input', { type: 'password', placeholder: 'Личный код', 'aria-label': 'Личный код', autocomplete: 'off' });
    const f = h('form', { class: 'row', onsubmit: async (e) => {
      e.preventDefault();
      try { const me = await login(input.value.trim()); toast('Здравствуйте, ' + me.name + '!'); }
      catch (err) { toast(err.message, true); }
    } }, input, h('button', { class: 'btn small primary', type: 'submit' }, 'Войти'));
    clear(box, f);
  }
}

session.listeners.add(() => { renderWho(); render(); });
window.addEventListener('hashchange', render);
window.addEventListener('taktichka:refresh', render);
renderWho();
restore()
  .catch((e) => toast('Не удалось восстановить вход: ' + (e.message || String(e)), true))
  .finally(() => { renderWho(); render(); });
