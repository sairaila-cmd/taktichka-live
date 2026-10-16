// Тактичка онлайн: маршруты (#/…), вход по коду, отрисовка разделов.
import { restore, login, logout, session, loadRefs, isAdmin } from './api.js?v=202610161643';
import { h, clear, toast } from './ui.js?v=202610161643';
import figuresView from './views/figures.js?v=202610161643';
import { startAlerts } from './alerts.js?v=202610161643';

// Главная (фигуры) грузится сразу, остальные разделы — когда их впервые открыли.
// Номер ?v= у import() — тот же, что у статических импортов (иначе два экземпляра модулей и теряется вход).
// view.load() — начать загрузку заранее (render зовёт её параллельно со справочниками из базы).
const lazy = (load) => Object.assign(async (...args) => (await load()).default(...args), { load });
const peopleView = lazy(() => import('./views/people.js?v=202610161643'));
const gamesView = lazy(() => import('./views/games.js?v=202610161643'));
const gameView = lazy(() => import('./views/game.js?v=202610161643'));
const battleView = lazy(() => import('./views/battle.js?v=202610161643'));
const rulesView = lazy(() => import('./views/rules.js?v=202610161643'));
const logView = lazy(() => import('./views/log.js?v=202610161643'));
const adminView = lazy(() => import('./views/admin.js?v=202610161643'));
const helpView = lazy(() => import('./views/help.js?v=202610161643'));

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
  if (route[2].load) route[2].load().catch(() => { /* ошибку покажет сам вызов раздела ниже */ });
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
startAlerts();
renderWho();
restore()
  .catch((e) => toast('Не удалось восстановить вход: ' + (e.message || String(e)), true))
  .finally(() => { renderWho(); render(); });
