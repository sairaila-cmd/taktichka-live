/* Помощник боя: чистый расчёт без сети и страницы.
 *
 * Battle.compute(state) → что сейчас происходит в бою:
 *   очередь фигур (фаза → номинал → Лояльность → атакующий), кто ходит, какие свойства
 *   доступны и почему нет, сила отрядов с разбором, броски, исход.
 *
 * state = {
 *   attacker, defender: { squad_id, name, rage, trophies_s, white_streak,
 *                         figures: [{ id, name, nominal, s, l, v, properties: [..], state }] },
 *   actions:   [{ id, kind, squad_id, figure_id, property, params, roll, cost }]  // по порядку id
 *   gifts:     ['alaya', 'belaya', ...],
 *   echoBlocked: ['Подкуп', ...],             // свойства, запрещённые активными Эхо
 *   properties: { 'Натиск': { phase, cost }, ... }
 * }
 * Состояния фигур (state) живые, из базы: ok | damaged | discard | reserve | dump.
 */
(function (root) {
  'use strict';

  const PHASES = ['Условие', 'Сила', 'Риск', 'Ущерб'];
  const RANK = { 'пешка': 1, 'конь': 2, 'офицер': 3, 'ладья': 4, 'ферзь': 5, 'король': 6 };
  const SIDES = ['attacker', 'defender'];
  const other = (side) => (side === 'attacker' ? 'defender' : 'attacker');
  const inLine = (f) => f.state === 'ok' || f.state === 'damaged';
  // Свойства, которые убирают фигуры из чужого отряда (их отключает «Закон и честь»).
  const REMOVING = new Set(['Добивание', 'Пожирание', 'Фаталити', 'Подкуп', 'СуперПодкуп']);
  // Свойства, которым нужна цель — фигура противника.
  const TARGETED = new Set(['Плен', 'Контрразведка', 'Закон Талиона']);

  function compute(state) {
    const props = state.properties || {};
    const gifts = new Set(state.gifts || []);
    const echoBlocked = new Set(state.echoBlocked || []);
    const sides = { attacker: state.attacker, defender: state.defender };
    const sideOfSquad = {};
    SIDES.forEach((s) => { sideOfSquad[sides[s].squad_id] = s; });
    const figById = {};
    SIDES.forEach((s) => sides[s].figures.forEach((f) => { figById[f.id] = { f, side: s }; }));
    const actions = (state.actions || []).slice().sort((a, b) => a.id - b.id);

    // ── очередь: по записи на (фигура, фаза), где у фигуры есть боевое свойство ──
    const entries = [];
    SIDES.forEach((side) => sides[side].figures.forEach((f) => {
      PHASES.forEach((phase) => {
        const list = (f.properties || []).filter((p) => props[p] && props[p].phase === phase);
        if (list.length) entries.push({ key: f.id + ':' + phase, phase, side, figure: f, properties: list });
      });
    }));
    entries.sort((a, b) =>
      PHASES.indexOf(a.phase) - PHASES.indexOf(b.phase) ||
      (RANK[b.figure.nominal] || 0) - (RANK[a.figure.nominal] || 0) ||
      b.figure.l - a.figure.l ||
      (a.side === 'attacker' ? -1 : 1) - (b.side === 'attacker' ? -1 : 1) ||
      a.figure.id - b.figure.id);

    // Действия фигур в бою: свойство (одно за бой) или пропуск конкретной записи очереди.
    const used = {};      // figure_id → действие со свойством
    const skipped = {};   // key → действие-пропуск
    actions.forEach((a) => {
      if (a.kind === 'property' && a.figure_id != null && !used[a.figure_id]) used[a.figure_id] = a;
      if (a.kind === 'skip' && a.figure_id != null) skipped[a.figure_id + ':' + ((a.params || {}).phase || '')] = a;
    });

    // ── контекст боя ──
    const ctx = {
      noSpend: { attacker: false, defender: false },   // противник применил «Всем друг»
      honor: { attacker: false, defender: false },     // «Закон и честь» у стороны
      perfectDefense: false,                           // «Совершенная оборона» защитника
      provoke: false,                                  // «Провокация» атакующего
      talion: new Set(), plen: new Set(),
      negotiated: false,
      riskBlock: { attacker: false, defender: false }, // «Только ты и я» / «Абсолютное превосходство» противника
      autowin: { attacker: null, defender: null },
    };
    const strength = {};
    const rolls = { attacker: null, defender: null };
    const log = [];
    const result = { entries: [], phase: 'Условие', need: null, strength, rolls, outcome: null, log, ctx };

    const ownName = (side) => sides[side].name;
    const optionCost = (p) => (props[p] ? props[p].cost : 0);
    const paid = (p) => optionCost(p) === null || optionCost(p) > 0;

    function figuresOf(side) { return sides[side].figures.filter(inLine); }
    function damagedOf(side) { return sides[side].figures.filter((f) => f.state === 'damaged'); }

    function startStrength() {
      SIDES.forEach((side) => {
        const parts = [];
        const base = figuresOf(side).filter((f) => !ctx.plen.has(f.id))
          .reduce((n, f) => n + (Number(f.s) || 0), 0);
        if (ctx.provoke && side === 'defender') {
          parts.push({ label: 'Провокация: базовая Сила фигур не считается', value: 0 });
        } else {
          parts.push({ label: 'Сила фигур' + (ctx.plen.size ? ' (без взятых в Плен)' : ''), value: base });
        }
        if (sides[side].trophies_s) parts.push({ label: 'трофеи', value: sides[side].trophies_s });
        if (gifts.has('belaya') && sides[side].white_streak) parts.push({ label: 'Белая луна: три номинала подряд', value: 2 });
        const total = parts.reduce((n, p) => n + p.value, 0);
        strength[side] = { total, parts };
      });
      actions.filter((a) => a.kind === 'rage' && (a.params || {}).use === 'power').forEach((a) => {
        const side = sideOfSquad[a.squad_id];
        if (side) add(side, 5, 'Ярость');
      });
    }
    function add(side, value, label) {
      strength[side].total += value;
      strength[side].parts.push({ label, value });
    }

    // Почему фигура/свойство сейчас недоступны (null — доступно).
    function blocked(entry, prop) {
      const { side, figure } = entry;
      const opp = other(side);
      if (!inLine(figure)) return 'фигура не в строю';
      if (ctx.negotiated) return 'бой закончен Переговорами';
      if (ctx.talion.has(figure.id)) return 'Закон Талиона: фигура не действует';
      if (ctx.perfectDefense && side === 'attacker') return 'Совершенная оборона противника';
      if (entry.phase === 'Риск' && ctx.riskBlock[side]) return 'противник автопобедил в этой фазе';
      if (prop) {
        if (echoBlocked.has(prop)) return 'не работает под действием Эхо';
        if (ctx.noSpend[side] && paid(prop)) return '«Всем друг» противника: тратить Ресурсы нельзя';
        if (REMOVING.has(prop) && ctx.honor[opp]) return '«Закон и честь» противника';
        switch (prop) {
          case 'Штурм': case 'Провокация':
            if (side !== 'attacker') return 'только у нападающего отряда'; break;
          case 'Укрепление': case 'Совершенная оборона':
            if (side !== 'defender') return 'только у защищающегося отряда'; break;
          case 'Осведомленность':
            if (!(strength[side].total < strength[opp].total)) return 'Сила отряда не меньше, чем у противника'; break;
          case 'Плен':
            if (!figuresOf(opp).some((t) => (RANK[t.nominal] || 0) <= (RANK[figure.nominal] || 0) + 1))
              return 'нет подходящей цели'; break;
          case 'Только ты и я':
            if (!rolls[side] || rolls[side].final < 8) return 'нужно 8 или больше на кубике'; break;
          case 'Абсолютное превосходство':
            if (!rolls[side] || rolls[side].final < 5) return 'нужно 5 или больше на кубике'; break;
          case 'Добивание': case 'Пожирание':
            if (!damagedOf(opp).length) return 'у противника нет повреждённых фигур'; break;
          case 'Лечение':
            if (!damagedOf(side).length) return 'в отряде нет повреждённых фигур'; break;
          case 'Фаталити':
            if (!result.outcome || result.outcome.winner !== side) return 'только если отряд победил'; break;
          case 'Подкуп':
            if (!figuresOf(opp).some((t) => RANK[t.nominal] <= 2)) return 'у противника нет пешек и коней'; break;
          case 'СуперПодкуп':
            if (!figuresOf(opp).some((t) => RANK[t.nominal] <= 4)) return 'у противника нет фигур до ладьи'; break;
          case 'Множественность': case 'Quid pro quo':
            if (figure.state !== 'damaged') return 'только если эта фигура повреждена'; break;
          default: break;
        }
      }
      return null;
    }

    // Что даёт применённое свойство.
    function apply(entry, a) {
      const { side } = entry;
      const opp = other(side);
      const p = a.property;
      const params = a.params || {};
      const target = params.target != null ? figById[params.target] : null;
      const who = entry.figure.name + ' (' + ownName(side) + ')';
      switch (p) {
        case 'Всем друг': ctx.noSpend[opp] = true; log.push(who + ': «Всем друг» — противник не тратит Ресурсы'); break;
        case 'Совершенная оборона': ctx.perfectDefense = true; log.push(who + ': Совершенная оборона'); break;
        case 'Провокация': ctx.provoke = true; log.push(who + ': Провокация'); break;
        case 'Закон и честь': ctx.honor[side] = true; log.push(who + ': Закон и честь'); break;
        case 'Закон Талиона': if (target) ctx.talion.add(target.f.id); log.push(who + ': Закон Талиона → ' + (target ? target.f.name : '?')); break;
        case 'Плен': if (target) ctx.plen.add(target.f.id); log.push(who + ': Плен → ' + (target ? target.f.name : '?')); break;
        case 'Штурм': add(side, 5, 'Штурм'); break;
        case 'Укрепление': add(side, 5, 'Укрепление'); break;
        case 'Натиск': add(side, 4 * (a.cost || 0), 'Натиск ×' + (a.cost || 0)); break;
        case 'Контрразведка': if (target) add(side, Number(target.f.s) || 0, 'Контрразведка: Сила «' + target.f.name + '»'); break;
        case 'Осведомленность': add(side, 5, 'Осведомленность'); break;
        case 'Один в поле воин': add(side, strength[side].total * 2, 'Один в поле воин (×3)'); break;
        case 'Мат': add(side, sides[opp].figures.filter(inLine).reduce((n, f) => n + (Number(f.s) || 0), 0), 'Мат'); break;
        case 'Шпионаж':
          if (rolls[opp] && a.roll != null) {
            const before = rolls[opp].final;
            rolls[opp].reroll = a.roll;
            rolls[opp].final = Math.min(rolls[opp].value, a.roll);  // применивший выбирает — меньшее
            log.push(who + ': Шпионаж — противник перебросил ' + before + ' → ' + a.roll + ', берётся ' + rolls[opp].final);
          }
          break;
        case 'Только ты и я':
          if (rolls[side] && rolls[side].final >= 8) { ctx.autowin[side] = 'Только ты и я'; ctx.riskBlock[opp] = true; }
          break;
        case 'Абсолютное превосходство':
          if (rolls[side] && rolls[side].final >= 5) { ctx.autowin[side] = 'Абсолютное превосходство'; ctx.riskBlock[opp] = true; }
          break;
        case 'Переговоры': ctx.negotiated = true; log.push(who + ': Переговоры — ничья'); break;
        default: log.push(who + ': ' + p); break;
      }
    }

    function decideOutcome() {
      if (ctx.negotiated) return { winner: null, reason: 'Переговоры' };
      SIDES.forEach((s) => { if (rolls[s] && rolls[s].final === 10 && !ctx.autowin[s]) ctx.autowin[s] = '10 на кубике'; });
      const aw = ctx.autowin.attacker, dw = ctx.autowin.defender;
      if (aw && dw) return { winner: null, reason: 'обе стороны автопобедили — ничья' };
      if (aw) return { winner: 'attacker', reason: 'автопобеда: ' + aw };
      if (dw) return { winner: 'defender', reason: 'автопобеда: ' + dw };
      const ta = strength.attacker.total + rolls.attacker.final;
      const td = strength.defender.total + rolls.defender.final;
      if (ta === td) return { winner: null, reason: 'равные суммы — ничья', totals: { attacker: ta, defender: td } };
      return { winner: ta > td ? 'attacker' : 'defender', reason: 'Сила + кубик', totals: { attacker: ta, defender: td } };
    }

    // ── проход по очереди ──
    let stopped = false;
    let phaseIdx = -1;
    for (const entry of entries) {
      const idx = PHASES.indexOf(entry.phase);
      while (!stopped && phaseIdx < idx) {
        phaseIdx += 1;
        stopped = enterPhase(PHASES[phaseIdx]);
      }
      const out = { key: entry.key, phase: entry.phase, side: entry.side, figure: entry.figure, properties: entry.properties };
      result.entries.push(out);
      if (stopped) { out.status = 'waiting'; continue; }

      const done = used[entry.figure.id];
      if (done && done.property && entry.properties.includes(done.property) &&
          props[done.property] && props[done.property].phase === entry.phase) {
        out.status = 'done'; out.action = done;
        apply(entry, done);
        continue;
      }
      if (done) { out.status = 'unavailable'; out.reason = 'фигура уже действовала в этом бою'; continue; }
      if (skipped[entry.key]) { out.status = 'skipped'; continue; }

      const general = blocked(entry, null);
      out.options = entry.properties.map((p) => {
        const reason = general || blocked(entry, p);
        return { property: p, available: !reason, reason,
                 cost: optionCost(p), amount: p === 'Натиск' ? [1, 2, 3] : null,
                 targets: TARGETED.has(p) ? targetsFor(entry, p) : null };
      });
      if (!out.options.some((o) => o.available)) {
        out.status = 'unavailable';
        out.reason = general || out.options.map((o) => o.property + ': ' + o.reason).join('; ');
        continue;
      }
      out.status = 'current';
      result.need = { type: 'decide', key: entry.key, side: entry.side, figure: entry.figure };
      stopped = true;
    }
    while (!stopped && phaseIdx < PHASES.length - 1) {
      phaseIdx += 1;
      stopped = enterPhase(PHASES[phaseIdx]);
    }
    if (!stopped) result.phase = 'Итог';

    function targetsFor(entry, p) {
      const opp = other(entry.side);
      return figuresOf(opp).filter((t) => p !== 'Плен' ||
        (RANK[t.nominal] || 0) <= (RANK[entry.figure.nominal] || 0) + 1)
        .map((t) => ({ id: t.id, name: t.name, nominal: t.nominal, s: t.s }));
    }

    // Начало фазы; true — бой ждёт чего-то до записей очереди этой фазы.
    function enterPhase(phase) {
      result.phase = phase;
      if (phase === 'Сила') startStrength();
      if (phase === 'Риск') {
        actions.filter((a) => a.kind === 'roll' && (a.params || {}).purpose === 'risk').forEach((a) => {
          const side = sideOfSquad[a.squad_id];
          if (side && !rolls[side]) rolls[side] = { value: a.roll, reroll: null, final: a.roll, manual: a.manual };
        });
        const missing = SIDES.filter((s) => !rolls[s]);
        if (missing.length) { result.need = { type: 'roll', sides: missing }; return true; }
      }
      if (phase === 'Ущерб') {
        result.outcome = decideOutcome();
        const w = result.outcome.winner;
        if (w) {
          const loser = other(w);
          const dmg = actions.find((a) => a.kind === 'damage' && sideOfSquad[a.squad_id] === loser);
          result.damage = dmg || null;
          if (!dmg && figuresOf(loser).some((f) => f.state === 'ok') && !ctx.negotiated) {
            result.need = { type: 'damage', side: loser,
                            candidates: figuresOf(loser).filter((f) => f.state === 'ok') };
            return true;
          }
        }
      }
      return false;
    }

    if (!result.outcome && result.phase === 'Итог') result.outcome = decideOutcome();
    return result;
  }

  root.Battle = { compute, PHASES, RANK };
})(typeof window !== 'undefined' ? window : globalThis);
