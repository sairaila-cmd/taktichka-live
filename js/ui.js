// Мелкие помощники для разметки: элементы без innerHTML (тексты из базы не исполняются).

export function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style') el.style.cssText = v;
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else if (v === true) el.setAttribute(k, '');
    else el.setAttribute(k, v);
  }
  append(el, kids);
  return el;
}
function append(el, kids) {
  for (const k of kids.flat(Infinity)) {
    if (k == null || k === false) continue;
    el.append(k instanceof Node ? k : document.createTextNode(String(k)));
  }
}
export const clear = (el, ...kids) => { el.replaceChildren(); append(el, kids); return el; };

export function card(title, ...kids) {
  return h('section', { class: 'card' }, title ? h('h2', {}, title) : null, ...kids);
}
export function cardH(title, actions, ...kids) {
  return h('section', { class: 'card' }, h('header', {}, h('h2', {}, title), h('div', { class: 'row' }, actions)), ...kids);
}
export const btn = (text, onclick, cls = '') => h('button', { class: 'btn ' + cls, type: 'button', onclick }, text);
export const badge = (text, cls = '') => h('span', { class: 'badge ' + cls }, text);
export const empty = (text) => h('p', { class: 'empty' }, text);

export function toast(text, error = false) {
  const box = document.getElementById('toasts');
  const t = h('div', { class: 'toast' + (error ? ' error' : ''), role: error ? 'alert' : 'status' }, text);
  box.append(t);
  // Уведомления — в верхнем слое браузера (popover), иначе открытое окно (showModal) их затемняет.
  // Переоткрытие поднимает их над окном, открытым позже.
  if (box.showPopover) {
    if (box.matches(':popover-open')) box.hidePopover();
    box.showPopover();
  }
  setTimeout(() => {
    t.remove();
    if (box.hidePopover && !box.children.length && box.matches(':popover-open')) box.hidePopover();
  }, error ? 7000 : 3500);
}

// Обёртка для действий: ошибка базы → понятное уведомление; успех → onDone.
export async function act(fn, okText, onDone) {
  try {
    const r = await fn();
    if (okText) toast(typeof okText === 'function' ? okText(r) : okText);
    if (onDone) await onDone(r);
    return r;
  } catch (e) {
    toast(e.message || String(e), true);
    return undefined;
  }
}

// Модальное окно: build(close) возвращает содержимое.
export function modal(title, build) {
  const dlg = document.getElementById('dialog');
  const close = () => { if (dlg.open) dlg.close(); };
  clear(dlg, h('div', { class: 'dlg' },
    h('div', { class: 'row', style: 'justify-content: space-between' },
      h('h2', {}, title), btn('✕', close, 'ghost small')),
    build(close)));
  dlg.showModal();
  return close;
}

// Форма из полей: fields = [{name, label, type, value, options, required, min, max, multiple}]
export function form(fields, submitText, onSubmit) {
  const inputs = {};
  const f = h('form', { class: 'form' });
  for (const fd of fields) {
    let input;
    if (fd.type === 'select') {
      input = h('select', { name: fd.name, required: fd.required, multiple: fd.multiple },
        (fd.options || []).map((o) => {
          const [v, t] = Array.isArray(o) ? o : [o, o];
          const sel = fd.multiple ? (fd.value || []).map(String).includes(String(v)) : String(v) === String(fd.value);
          return h('option', { value: v, selected: sel }, t);
        }));
      if (fd.multiple) input.size = Math.min(8, (fd.options || []).length || 1);
    } else if (fd.type === 'textarea') {
      input = h('textarea', { name: fd.name, required: fd.required }, fd.value || '');
    } else if (fd.type === 'checkbox') {
      input = h('input', { type: 'checkbox', name: fd.name, checked: !!fd.value });
    } else {
      input = h('input', { type: fd.type || 'text', name: fd.name, required: fd.required, value: fd.value ?? '',
        min: fd.min, max: fd.max, placeholder: fd.placeholder, autocomplete: 'off' });
    }
    inputs[fd.name] = input;
    f.append(fd.type === 'checkbox' ? h('label', { class: 'inline' }, input, fd.label) : h('label', {}, fd.label, input));
    if (fd.hint) f.append(h('p', { class: 'muted small', style: 'margin:0' }, fd.hint));
  }
  const submit = h('button', { class: 'btn primary', type: 'submit' }, submitText);
  f.append(h('div', { class: 'row end' }, submit));
  f.addEventListener('submit', async (e) => {
    e.preventDefault();
    const vals = {};
    for (const fd of fields) {
      const i = inputs[fd.name];
      if (fd.type === 'checkbox') vals[fd.name] = i.checked;
      else if (fd.multiple) vals[fd.name] = [...i.selectedOptions].map((o) => o.value);
      else if (fd.type === 'number') vals[fd.name] = i.value === '' ? null : Number(i.value);
      else vals[fd.name] = i.value.trim() === '' ? null : i.value.trim();
    }
    submit.disabled = true;
    try { await onSubmit(vals); } finally { submit.disabled = false; }
  });
  return f;
}

// Перерисовать текущий раздел (после правки).
export const refresh = () => window.dispatchEvent(new Event('taktichka:refresh'));

export function fmtTime(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  return d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
}

export const NOM_GLYPH = { 'король': '♚', 'ферзь': '♛', 'ладья': '♜', 'офицер': '♝', 'конь': '♞', 'пешка': '♟' };
export const STATE_RU = { ok: 'цела', damaged: 'повреждена', discard: 'в отбое', reserve: 'в резерве', dump: 'на свалке' };
export const GIFT_RU = { alaya: 'Алая луна — Ярость', belaya: 'Белая луна — Приливы и отливы',
  gorkaya: 'Горькая луна — Эхо', chernaya: 'Чёрная луна — Прилив времени' };
export const STATUS_RU = { draft: 'сбор отрядов', running: 'идёт', closed: 'закончена' };
export const plural = (n, one, few, many) => {
  const m10 = n % 10, m100 = n % 100;
  return n + ' ' + (m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20) ? few : many);
};
