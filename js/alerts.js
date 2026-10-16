// Извещение о нападении: пока игрок вошёл по коду, на любой странице сайта плашка
// «На ваш отряд напали — открыть бой», если его отряд защищается в идущем бою.
// Плашка висит, пока бой не закончен (на странице самого боя скрыта). Если вкладка свёрнута
// и игрок разрешил — ещё и уведомление браузера (один раз на бой).
import { rows, session, watch } from './api.js?v=202610161643';
import { h, clear } from './ui.js?v=202610161643';

let unwatch = null;
let timer = null;
let alerts = [];              // [{ id, attacker, defender }] — названия отрядов
const notified = new Set();   // бои, о которых уже было уведомление браузера

export function startAlerts() {
  session.listeners.add(restart);
  window.addEventListener('hashchange', draw);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && unwatch) schedule(); });
  restart();
}

function restart() {
  if (unwatch) { unwatch(); unwatch = null; }
  clearTimeout(timer);
  alerts = [];
  draw();
  if (!session.me || session.me.is_admin) return;
  unwatch = watch('alerts', ['battles'], schedule);
  check();
}

function schedule() { clearTimeout(timer); timer = setTimeout(check, 300); }

async function check() {
  const me = session.me;
  if (!me) return;
  try {
    const open = await rows('battles', (q) => q.eq('status', 'open').order('id'), 'id, game_id, attacker, defender');
    let found = [];
    if (open.length) {
      const [mine, squads] = await Promise.all([
        rows('strategist_members', (q) => q.eq('player_id', me.id).in('game_id', [...new Set(open.map((b) => b.game_id))]), 'strategist_id'),
        rows('squads', (q) => q.in('id', [...new Set(open.flatMap((b) => [b.attacker, b.defender]))]), 'id, name, strategist_id'),
      ]);
      const my = new Set(mine.map((m) => m.strategist_id));
      const sq = Object.fromEntries(squads.map((s) => [s.id, s]));
      found = open.filter((b) => sq[b.defender] && my.has(sq[b.defender].strategist_id)
          && !(sq[b.attacker] && my.has(sq[b.attacker].strategist_id)))
        .map((b) => ({ id: b.id, attacker: sq[b.attacker] ? sq[b.attacker].name : '?', defender: sq[b.defender].name }));
    }
    if (session.me !== me) return;   // пока читали, игрок вышел или сменился
    alerts = found;
    draw();
    systemNotify();
  } catch { /* сеть или база недоступны — попробуем при следующем изменении */ }
}

function box() {
  let el = document.getElementById('alerts');
  if (!el) {
    el = h('div', { id: 'alerts', class: 'alerts', role: 'alert', 'aria-live': 'assertive' });
    const view = document.getElementById('view');
    view.parentNode.insertBefore(el, view);
  }
  return el;
}

function draw() {
  const el = box();
  const here = (location.hash || '').match(/^#\/battle\/(\d+)$/);
  const list = alerts.filter((a) => !here || Number(here[1]) !== a.id);
  clear(el, ...list.map((a) => h('div', { class: 'alert-attack' },
    h('span', {}, '⚔ На ваш отряд «' + a.defender + '» напал «' + a.attacker + '»'),
    h('a', { class: 'btn small primary', href: '#/battle/' + a.id }, 'Открыть бой'),
    notifyButton())));
  el.classList.toggle('hidden', !list.length);
}

function systemNotify() {
  if (!('Notification' in window) || Notification.permission !== 'granted' || document.visibilityState === 'visible') return;
  alerts.filter((a) => !notified.has(a.id)).forEach((a) => {
    notified.add(a.id);
    try {
      const n = new Notification('Тактичка: на ваш отряд напали', { body: '«' + a.attacker + '» → «' + a.defender + '»', tag: 'battle-' + a.id });
      n.onclick = () => { window.focus(); location.hash = '#/battle/' + a.id; n.close(); };
    } catch { /* браузер не даёт показать уведомление — плашка всё равно на месте */ }
  });
}

// Кнопка «Уведомлять, когда вкладка свёрнута» (null — не нужна: нет поддержки, уже решено).
export function notifyButton() {
  if (!('Notification' in window) || Notification.permission !== 'default') return null;
  return h('button', { class: 'btn small', type: 'button', title: 'Браузер покажет уведомление о нападении, даже если вкладка сайта свёрнута',
    onclick: async (e) => {
      try { await Notification.requestPermission(); } catch { /* старый браузер */ }
      e.target.remove();
    } }, 'Уведомлять, когда вкладка свёрнута');
}
