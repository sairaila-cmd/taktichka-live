// Связь с базой: чтение таблиц, вызовы api_* с личным кодом, подписки на изменения.
import { SUPABASE_URL, SUPABASE_KEY } from './config.js?v=202610150001';

export const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const CODE_KEY = 'taktichka.code';
export const session = { code: null, me: null, listeners: new Set() };

function storeGet() { try { return localStorage.getItem(CODE_KEY); } catch { return null; } }
function storeSet(v) { try { v ? localStorage.setItem(CODE_KEY, v) : localStorage.removeItem(CODE_KEY); } catch { /* приватный режим */ } }

export async function login(code) {
  const { data, error } = await sb.rpc('api_whoami', { p_code: code });
  if (error) throw new Error(error.message);
  session.code = code; session.me = data; storeSet(code);
  session.listeners.forEach((f) => f());
  return data;
}
export function logout() {
  session.code = null; session.me = null; storeSet(null);
  session.listeners.forEach((f) => f());
}
export async function restore() {
  const code = storeGet();
  if (!code) return null;
  try { return await login(code); } catch { storeSet(null); return null; }
}
export const isAdmin = () => !!(session.me && session.me.is_admin);

// Вызов api_*: код подставляется сам; все параметры функции надо передать (null — если не нужен).
export async function call(fn, args = {}) {
  if (!session.code) throw new Error('Войдите по личному коду');
  const { data, error } = await sb.rpc(fn, { p_code: session.code, ...args });
  if (error) throw new Error(error.message);
  return data;
}

// Чтение: rows('figures', q => q.order('name'))
export async function rows(table, build = (q) => q, columns = '*') {
  const { data, error } = await build(sb.from(table).select(columns));
  if (error) throw new Error(error.message);
  return data || [];
}

// Подписка на изменения таблиц (Realtime); возвращает функцию отписки.
export function watch(name, tables, onChange) {
  let ch = sb.channel(name + ':' + Math.random().toString(36).slice(2));
  tables.forEach((t) => {
    const [table, filter] = Array.isArray(t) ? t : [t, undefined];
    ch = ch.on('postgres_changes', { event: '*', schema: 'public', table, ...(filter ? { filter } : {}) }, onChange);
  });
  ch.subscribe();
  return () => { sb.removeChannel(ch); };
}

// Общие справочники (кэш на время открытой страницы, обновляется по запросу).
export const cache = { players: null, properties: null, nominals: null };
export async function loadRefs(force = false) {
  if (force || !cache.players) {
    const [players, properties, nominals] = await Promise.all([
      rows('players', (q) => q.order('name')),
      rows('properties', (q) => q.order('name')),
      rows('nominals', (q) => q.order('rank', { ascending: false })),
    ]);
    Object.assign(cache, {
      players, properties, nominals,
      playerById: Object.fromEntries(players.map((p) => [p.id, p])),
      propByName: Object.fromEntries(properties.map((p) => [p.name, p])),
    });
  }
  return cache;
}
