// Связь с базой: чтение таблиц, вызовы api_* с личным кодом, подписки на изменения.
import { SUPABASE_URL, SUPABASE_KEY } from './config.js?v=202610151535';

export const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const CODE_KEY = 'taktichka.code';
export const session = { code: null, me: null, listeners: new Set() };

function storeGet() { try { return localStorage.getItem(CODE_KEY); } catch { return null; } }
function storeSet(v) { try { v ? localStorage.setItem(CODE_KEY, v) : localStorage.removeItem(CODE_KEY); } catch { /* приватный режим */ } }

export async function login(code) {
  const { data, error } = await sb.rpc('api_whoami', { p_code: code });
  if (error) throw Object.assign(new Error(error.message), { code: error.code, status: error.status });
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
  try {
    return await login(code);
  } catch (error) {
    if (error.code === 'P0001' && error.message === 'Неверный код') {
      storeSet(null);
      return null;
    }
    throw error;
  }
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

// Supabase REST responses are capped at 1000 rows; fetch remaining pages for complete datasets.
export async function rowsAll(table, build = (q) => q, columns = '*') {
  const pageSize = 1000;
  const all = [];
  for (let offset = 0; ; offset += pageSize) {
    const page = await rows(table, (q) => build(q).range(offset, offset + pageSize - 1), columns);
    all.push(...page);
    if (page.length < pageSize) return all;
  }
}

export async function journalPage(before, limit) {
  const { data, error } = await sb.rpc('journal_page', {
    p_before_at: before ? before.at : null,
    p_before_id: before ? before.id : null,
    p_limit: limit,
  });
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

// Общие данные (справочники кэшируются, игроки можно обновить отдельно).
export const cache = { players: null, properties: null, nominals: null };
let playersRequest = null;
let refsRequest = null;

export function loadPlayers(force = false) {
  if (playersRequest) return playersRequest;
  if (!force && cache.players) return Promise.resolve(cache.players);
  const request = rowsAll('players', (q) => q.order('name')).then((players) => {
    Object.assign(cache, {
      players,
      playerById: Object.fromEntries(players.map((p) => [p.id, p])),
    });
    return players;
  });
  playersRequest = request;
  request.then(
    () => { if (playersRequest === request) playersRequest = null; },
    () => { if (playersRequest === request) playersRequest = null; },
  );
  return request;
}

export async function loadRefs(force = false) {
  if (refsRequest) return refsRequest;
  if (!force && cache.properties && cache.nominals) {
    await loadPlayers();
    return cache;
  }
  const request = Promise.all([
    loadPlayers(force),
    force || !cache.properties ? rows('properties', (q) => q.order('name')) : cache.properties,
    force || !cache.nominals ? rows('nominals', (q) => q.order('rank', { ascending: false })) : cache.nominals,
  ]).then(([, properties, nominals]) => {
    Object.assign(cache, {
      properties, nominals,
      propByName: Object.fromEntries(properties.map((p) => [p.name, p])),
    });
    return cache;
  });
  refsRequest = request;
  request.then(
    () => { if (refsRequest === request) refsRequest = null; },
    () => { if (refsRequest === request) refsRequest = null; },
  );
  return request;
}
