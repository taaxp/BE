// BE web: reads an Apple Health export in the browser and shows it. No sample data, no simulation:
// every number comes from the export via analytics.js. Nothing is uploaded.
(() => {
  'use strict';
  const A = beAnalyticsModule();
  const { fmt, addDays, range } = A;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ---------- icons ----------
  const I = {
    steps: '<path fill="currentColor" d="M3 15.5c0-2.5.8-6 1.4-8.5h3.3c.3 1.3 1.3 2.2 2.6 2.2l1-1.6 1.6.9-.8 1.5 1.5.9.9-1.4 1.6 1c2.6 1.6 5 2.8 5 5.2v1.8H3z"/>',
    drop: '<path fill="currentColor" d="M12 2.5c-3.2 4.3-6.5 8-6.5 11.8a6.5 6.5 0 0 0 13 0c0-3.8-3.3-7.5-6.5-11.8z"/>',
    heart: '<path fill="currentColor" d="M12 20.5s-7.5-4.6-7.5-10.4A4.3 4.3 0 0 1 12 7.3a4.3 4.3 0 0 1 7.5 2.8c0 5.8-7.5 10.4-7.5 10.4z"/>',
    moon: '<path fill="currentColor" d="M20 14.6A8.3 8.3 0 1 1 9.4 4a6.6 6.6 0 0 0 10.6 10.6z"/>',
    flame: '<path fill="currentColor" d="M12 2c1.2 3.5 5 5.6 5 10.5a5 5 0 0 1-10 0c0-2.4 1.3-3.8 2.4-4.8 0 2.2 1.1 3.4 2.3 3.4C11.7 7.6 10.8 5 12 2z"/>',
    wave: '<path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M2.5 12h4l2.2-5.5 3.6 11 2.4-5.5h6.8"/>',
    lungs: '<path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M12 3.5v8m0 0c-1.5 0-6.5.6-6.5 6.6 0 1.6.8 2.4 2 2.4 2.6 0 4.5-2.6 4.5-6.2m0-2.8c1.5 0 6.5.6 6.5 6.6 0 1.6-.8 2.4-2 2.4-2.6 0-4.5-2.6-4.5-6.2"/>',
    bolt: '<path fill="currentColor" d="M13.5 2L4.5 13.6h6.6l-1 8.4 9.4-12h-6.8z"/>',
    scale: '<path fill="currentColor" d="M6 4h12a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3zm6 3.5a4.5 4.5 0 0 0-4.5 4.5h9A4.5 4.5 0 0 0 12 7.5z"/>',
    food: '<path fill="currentColor" d="M4 10.5C4 6.9 7.6 4.5 12 4.5s8 2.4 8 6zM3.5 12.5h17v2h-17zM4.5 16.5h15a3 3 0 0 1-3 3h-9a3 3 0 0 1-3-3z"/>',
    run: '<path fill="currentColor" d="M14.5 2.5a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM10 8.2l3.6-.9 2.4 3.2 3 .9-.5 1.9-3.8-1.1-1-1.3-.9 3.4 2.6 2.6V22h-2v-4.2l-2.6-2.4-1.3 4.4-5.6 1.4-.5-1.9 4.5-1.1 1.9-7.1-1.3.4-1.5 2.7-1.8-1z"/>',
    rings: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2.4"/><circle cx="12" cy="12" r="4.5" fill="none" stroke="currentColor" stroke-width="2.4"/>',
    check: '<path fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" d="M5 12.5l4.5 4.5L19 7.5"/>',
    x: '<path fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" d="M6 6l12 12M18 6L6 18"/>',
    up: '<path fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" d="M12 19V5m-6 6l6-6 6 6"/>',
    upload: '<path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M12 16V4m-5 5l5-5 5 5M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>',
    camera: '<path fill="currentColor" d="M8.5 5l1.4-2h4.2l1.4 2H19a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h3.5zM12 17a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9z"/>',
    sparkle: '<path fill="currentColor" d="M12 2.5l1.9 5.6 5.6 1.9-5.6 1.9-1.9 5.6-1.9-5.6L4.5 10l5.6-1.9zM18.5 15l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9z"/>',
    lock: '<path fill="currentColor" d="M7 10V7.5a5 5 0 0 1 10 0V10h1a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2zm2 0h6V7.5a3 3 0 0 0-6 0z"/>',
    phone: '<rect x="6" y="2.5" width="12" height="19" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M10.5 18.5h3"/>',
    watch: '<rect x="6.5" y="6" width="11" height="12" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path stroke="currentColor" stroke-width="2" d="M9 6l.8-3.5h4.4L15 6M9 18l.8 3.5h4.4L15 18"/>',
    app: '<rect x="4" y="4" width="16" height="16" rx="4.5" fill="none" stroke="currentColor" stroke-width="2"/>',
    seal: '<path fill="currentColor" d="M12 2l2.4 2 3.1-.4.9 3 2.7 1.6-1.1 2.9 1.1 2.9-2.7 1.6-.9 3-3.1-.4L12 22l-2.4-2-3.1.4-.9-3-2.7-1.6 1.1-2.9L2.9 10l2.7-1.6.9-3 3.1.4z"/>',
    person: '<circle cx="12" cy="6.5" r="3.2" fill="currentColor"/><path fill="currentColor" d="M6 21c0-5 1.8-9.5 6-9.5S18 16 18 21z"/>',
    photo: '<path fill="none" stroke="currentColor" stroke-width="2" d="M4 5h16v14H4z"/><path fill="currentColor" d="M6 17l4-5 3 3.5 2-2 3 3.5z"/>',
  };
  const svg = (n, a = '') => `<svg viewBox="0 0 24 24" aria-hidden="true" ${a}>${I[n]}</svg>`;

  // ---------- storage ----------
  // The parsed summary, meals and progress photos stay in this browser (IndexedDB). Never uploaded.
  const store = (() => {
    let p = null;
    const open = () => p || (p = new Promise((res, rej) => {
      try {
        const r = indexedDB.open('be-web', 1);
        r.onupgradeneeded = () => { for (const n of ['kv', 'meals', 'progress']) if (!r.result.objectStoreNames.contains(n)) r.result.createObjectStore(n); };
        r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
      } catch (e) { rej(e); }
    }));
    const run = async (s, mode, fn) => {
      try { const d = await open(); return await new Promise((res) => { const t = d.transaction(s, mode); const q = fn(t.objectStore(s)); t.oncomplete = () => res(q && q.result); t.onerror = t.onabort = () => res(null); }); }
      catch (e) { return null; }
    };
    return { get: (s, k) => run(s, 'readonly', (o) => o.get(k)), put: (s, k, v) => run(s, 'readwrite', (o) => o.put(v, k)), del: (s, k) => run(s, 'readwrite', (o) => o.delete(k)),
      all: (s) => run(s, 'readonly', (o) => o.getAll()), clear: (s) => run(s, 'readwrite', (o) => o.clear()) };
  })();
  const local = { get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }, set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* unavailable */ } } };

  // ---------- state ----------
  const S = { data: null, meta: null, sel: null, tab: 'today', name: local.get('be.name', 'Azad'), targets: {}, meals: [], progress: [],
    snapMode: 'meals', calMonth: null, snapImg: null, snapBusy: false, chat: [], chatBusy: false };
  const dayData = () => (S.data && S.data.days[S.sel]) || {};
  const isLatest = () => S.data && S.sel === S.data.lastDataDay;
  const longDay = (k) => new Date(k + 'T12:00:00Z').toLocaleDateString('en-AU', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
  const shortDay = (k) => new Date(k + 'T12:00:00Z').toLocaleDateString('en-AU', { day: 'numeric', month: 'short', timeZone: 'UTC' });
  const wk = (k) => new Date(k + 'T12:00:00Z').toLocaleDateString('en-AU', { weekday: 'short', timeZone: 'UTC' });
  const localToday = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
  const daysBetween = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000);

  function setTargets(t) { S.targets = t; local.set('be.targets', t); }
  function ensureTargets() {
    const rec = S.data ? A.recommendTargets(S.data, S.data.lastDataDay) : { steps: 8000, sleepH: 7.5, exerciseMin: 30, waterL: 2 };
    const saved = local.get('be.targets', null);
    S.targets = { ...rec, ...(saved || {}) };
  }

  // ---------- number animation ----------
  const shown = {};
  function countUp(root) {
    root.querySelectorAll('[data-n]').forEach((el) => {
      const key = el.dataset.n, to = Number(el.dataset.v), d = Number(el.dataset.d || 0);
      const from = key in shown ? shown[key] : to * 0.6;
      shown[key] = to;
      if (reduce || from === to || !isFinite(to)) { el.textContent = fmt(to, d); return; }
      const t0 = performance.now();
      const step = (t) => { const p = Math.min(1, (t - t0) / 700), e = 1 - (1 - p) ** 3; el.textContent = fmt(from + (to - from) * e, d); if (p < 1) requestAnimationFrame(step); };
      requestAnimationFrame(step);
    });
  }
  const N = (key, v, d = 0) => (v == null ? '<span class="empty-val">–</span>' : `<span data-n="${key}" data-v="${v}" data-d="${d}">${fmt(v, d)}</span>`);

  // ---------- shared pieces ----------
  const coachLine = (c) => `<div class="coach"><b class="t-${c.tone}">${esc(c.h)}</b><span>${esc(c.act)}</span></div>`;
  const track = (f, c) => `<div class="track"><i style="width:${Math.round(Math.max(0, Math.min(1, f || 0)) * 100)}%;background:${c}"></i></div>`;
  function metricValue(k, day = S.sel) {
    const m = A.METRICS[k];
    if (m.carry) { const l = A.latest(S.data, k, day); return l ? l.v : null; }
    return A.value(S.data, k, day);
  }
  // "+6 bpm vs your normal" with good/bad colour from the metric's better direction.
  function vsNormal(k) {
    const v = metricValue(k), b = A.baseline(S.data, k, S.sel), m = A.METRICS[k];
    if (v == null || !b) return `<div class="vs">${b ? '' : 'Not enough history for a normal yet'}</div>`;
    const diff = v - b.mean, small = Math.abs(diff) < Math.max(b.sd * 0.5, Math.abs(b.mean) * 0.02);
    const cls = small || m.better === 'range' ? '' : (diff > 0) === (m.better === 'up') ? 'up-good' : 'up-bad';
    const sign = diff > 0 ? '+' : '−';
    return `<div class="vs">${small ? 'In line with' : `<b class="${cls}">${sign}${fmt(Math.abs(diff), m.d)} ${m.unit}</b> vs`} your normal of ${fmt(b.mean, m.d)}</div>`;
  }
  function ring(size, stroke, frac, color, label) {
    const r = (size - stroke) / 2, C = 2 * Math.PI * r;
    return `<div class="ring" style="width:${size}px;height:${size}px"><svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="var(--track)" stroke-width="${stroke}"/>
      <circle class="arc" cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${(C * Math.max(0, Math.min(1, frac))).toFixed(1)} ${C.toFixed(1)}"/></svg><b style="font-size:${Math.round(size * 0.3)}px">${label}</b></div>`;
  }

  // ---------- TODAY ----------
  function renderToday(enter) {
    const el = $('#v-today');
    el.innerHTML = S.data ? dashboardHTML() : importHeroHTML();
    if (S.data) countUp(el);
    if (reduce) requestAnimationFrame(drawEcg);
    wireDrop(el);
    play(el, enter);
  }

  function header() {
    if (!S.data) return `<div class="top"><div class="brand"><img src="${LOGO}" alt=""><b>BE</b></div></div>`;
    const age = daysBetween(S.data.lastDataDay, localToday());
    return `<div class="top"><div class="brand"><img src="${LOGO}" alt=""><b>BE</b></div>
      <button class="data-chip" data-act="data" aria-haspopup="dialog"><i class="${age > 2 ? 'stale' : ''}"></i>Data to ${shortDay(S.data.lastDataDay)}</button></div>`;
  }

  function importHeroHTML() {
    return `${header()}
      <h1 tabindex="-1" style="--i:0">Bring in your<br><span class="soft">Apple Health data</span></h1>
      <div class="card hero-import" style="--i:1">
        <p class="p">Web pages can't connect to Apple Health directly, so BE works from the export the Health app makes. Every number here comes from your own records.</p>
        <ol class="steps-list">
          <li><span>On your iPhone, open the <b>Health</b> app and tap your picture at the top right.</span></li>
          <li><span>Tap <b>Export All Health Data</b>, then <b>Export</b>. It can take a few minutes.</span></li>
          <li><span>Save <b>export.zip</b> to Files, then choose it below. Open this page in Safari on the same iPhone to skip copying it.</span></li>
        </ol>
        <div class="drop" id="drop">
          ${svg('upload')}
          <b>Choose export.zip</b>
          <span class="note">or drop it here. export.xml works too.</span>
          <label class="btn ink" for="file-in" style="max-width:240px">Choose file</label>
          <input id="file-in" type="file" accept=".zip,.xml,application/zip,text/xml" hidden>
        </div>
        <div class="assure">
          <div>${svg('lock')}<span>Read on this device. Nothing is uploaded.</span></div>
          <div>${svg('check')}<span>Only daily totals are kept, in this browser. Delete them any time.</span></div>
          <div>${svg('phone')}<span>Live, automatic sync needs the BE iPhone app. Here, re-import to update.</span></div>
        </div>
      </div>`;
  }

  function dashboardHTML() {
    const D = S.data, d = dayData(), latest = isLatest();
    const g = A.greeting(D, S.sel, S.targets, null, latest, new Date().getHours());
    const days7 = range(addDays(D.lastDataDay, -6), D.lastDataDay);
    return `${header()}
      <h1 tabindex="-1" style="--i:0">${esc(g.hello)}${latest && S.name ? `, <button class="name-btn" data-act="name" aria-label="Your name: ${esc(S.name)}. Change">${esc(S.name)}</button>` : ''}<br><span class="soft">${esc(g.line)}</span></h1>
      ${scoreCard(g)}
      ${latest ? askCard() : ''}
      <div class="dates" role="group" aria-label="Choose a day" style="--i:3">
        ${days7.map((k) => `<button class="date" data-day="${k}" aria-pressed="${k === S.sel}"><b>${k.slice(8).replace(/^0/, '')}</b><span>${k === D.lastDataDay ? 'Latest' : wk(k)}</span></button>`).join('')}
      </div>
      <div class="bento">
        ${activityCard(days7)}
        ${waterCard(d)}
        ${heartCard(d)}
        ${caloriesCard(d)}
        ${ringsCard(d)}
        ${sleepCard(d)}
        ${smallCard('hrv', 'wave', 'var(--hrv)', 10)}
        ${smallCard('spo2', 'lungs', 'var(--o2)', 11)}
        ${smallCard('vo2', 'bolt', 'var(--vo2)', 12)}
        ${smallCard('weightKg', 'scale', 'var(--weight)', 13)}
        ${workoutsCard()}
      </div>
      <p class="note" style="text-align:center;padding:6px 8px">From your Apple Health export${D.exportDate ? ` of ${esc(D.exportDate.slice(0, 16))}` : ''}. Re-import a newer export to update.</p>`;
  }

  function scoreCard(g) {
    const D = S.data, v = (k) => A.value(D, k, S.sel), t = S.targets;
    const pct = (x) => (x == null ? 'not recorded' : `${Math.round(Math.max(0, Math.min(1, x)) * 100)}%`);
    const br = A.baseline(D, 'rhr', S.sel), bh = A.baseline(D, 'hrv', S.sel);
    const rows = [
      ['Sleep vs target', v('sleepH') == null ? null : v('sleepH') / (t.sleepH || 7.5)],
      ['Resting heart rate vs normal', v('rhr') == null || !br ? null : 1 - Math.max(0, v('rhr') - br.mean) / 10],
      ['HRV vs normal', v('hrv') == null || !bh ? null : v('hrv') / bh.mean],
      ['Steps vs target', v('steps') == null ? null : v('steps') / (t.steps || 8000)],
      ['Exercise vs target', v('exerciseMin') == null ? null : v('exerciseMin') / (t.exerciseMin || 30)],
      ['Water vs target', v('waterL') == null ? null : v('waterL') / (t.waterL || 2)],
    ];
    return `<div class="card" style="--i:1;gap:10px">
      <div class="score-card" style="display:flex;padding:0">${ring(64, 7, g.score / 100, 'var(--brand)', N('score', g.score))}
        <p><strong>BE score ${g.score}.</strong> ${esc(g.why)}</p></div>
      <details class="how"><summary>How this is worked out</summary>
        <p style="margin-top:6px">55% recovery (${pct(g.recovery)}) and 45% activity (${pct(g.activity)}), from this day's records. Missing readings count as 50%.</p>
        <div class="how-grid">${rows.map(([n, x]) => `<span>${n}</span><span>${pct(x)}</span>`).join('')}</div>
      </details>
    </div>`;
  }

  function askCard() {
    return `<div class="card" style="--i:2;gap:10px">
      <div class="ch"><span class="orb" aria-hidden="true"></span><span>Ask your coach</span><span class="end">Reads your data</span></div>
      <button class="ask-field" data-act="ask">Ask about your sleep, heart, activity…<span class="go">${svg('up')}</span></button>
      <div class="chips">${SUGGEST.map((q) => `<button class="chip" data-ask="${esc(q)}">${esc(q)}</button>`).join('')}</div>
    </div>`;
  }

  function activityCard(days7) {
    const D = S.data, v = A.value(D, 'steps', S.sel), t = S.targets.steps;
    const vals = days7.map((k) => A.value(D, 'steps', k));
    const max = Math.max(t || 0, ...vals.filter((x) => x != null), 1) * 1.08;
    const goalPct = t ? (t / max) * 100 : null;
    return `<div class="card span2" style="--i:4" data-metric="steps" role="button" tabindex="0" aria-label="Steps ${fmt(v)}. Open details.">
      <div class="ch" style="color:var(--steps)">${svg('steps')}<span style="color:var(--ink)">Activity</span><span class="end"><span class="num" style="font-size:28px;color:var(--ink)">${N('steps', v)}</span> steps</span></div>
      <div class="bars">${days7.map((k, i) => { const x = vals[i]; return `<div class="bar ${k === S.sel ? 'sel' : ''} ${x == null ? 'none' : t && x >= t ? 'met' : ''}" style="--b:${i}"><div class="plot"><div class="col" style="height:${x == null ? 6 : Math.max(6, (x / max) * 100)}%"></div></div><span>${wk(k)}</span></div>`; }).join('')}
        ${goalPct ? `<div class="goal-line" style="bottom:calc(22px + ${(goalPct / 100).toFixed(3)} * (100% - 22px))"><em>Target ${fmt(t)}</em></div>` : ''}</div>
      ${vsNormal('steps')}
      ${coachLine(A.coach(D, 'steps', S.sel, S.targets))}
    </div>`;
  }

  // The glass holds your water target and drains as you drink: empty means target reached.
  function waterCard(d) {
    const v = A.value(S.data, 'waterL', S.sel), t = S.targets.waterL || 2;
    const rem = v == null ? 1 : Math.max(0, 1 - v / t), y = (8 + (1 - rem) * 79).toFixed(1);
    return `<div class="card" style="--i:5" data-metric="waterL" role="button" tabindex="0" aria-label="Water ${v == null ? 'not logged' : fmt(v, 2) + ' litres'}. Open details.">
      <div class="ch" style="color:var(--water)">${svg('drop')}<span style="color:var(--ink)">Water</span></div>
      <div class="water-row"><div style="min-width:0"><div class="num">${N('water', v, 2)}<small>/${fmt(t, 1)} L</small></div>
        <div class="vs" style="margin-top:4px">${v == null ? 'None logged in Health' : v >= t ? 'Glass empty. Target hit.' : `${fmt(t - v, 2)} L left in the glass`}</div></div>
        <svg class="glass" viewBox="0 0 60 92" role="img" aria-label="${v == null ? 'No water logged' : fmt(Math.max(0, t - v), 2) + ' litres left of ' + fmt(t, 1)}">
          <defs><clipPath id="g-in"><path d="M6.6 6 L53.4 6 L48.2 84.6 Q47.9 86.6 45.6 86.6 L14.4 86.6 Q12.1 86.6 11.8 84.6 Z"/></clipPath>
          <linearGradient id="g-w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--water)" stop-opacity=".45"/><stop offset="1" stop-color="var(--water)" stop-opacity=".95"/></linearGradient></defs>
          <path d="M4 4 L56 4 L50.3 86 Q49.9 88.6 47.2 88.6 L12.8 88.6 Q10.1 88.6 9.7 86 Z" fill="var(--glass-hi)" fill-opacity=".6"/>
          ${v == null ? '' : `<g clip-path="url(#g-in)"><g style="transform:translateY(${y}px);transition:transform 1s var(--spring)"><path class="wave" style="animation-delay:-${Math.round(performance.now() % 2800)}ms" d="M0 3 Q7.5 0 15 3 T30 3 T45 3 T60 3 T75 3 T90 3 T105 3 T120 3 V120 H0 Z" fill="url(#g-w)"/></g></g>`}
          <path d="M4 4 L56 4 L50.3 86 Q49.9 88.6 47.2 88.6 L12.8 88.6 Q10.1 88.6 9.7 86 Z" fill="none" stroke="var(--ink)" stroke-opacity=".35" stroke-width="1.6" stroke-linejoin="round"/>
          <path d="M10.5 11 L14.6 78" stroke="#fff" stroke-opacity=".6" stroke-width="2.4" stroke-linecap="round"/></svg></div>
      <div class="grow"></div>${coachLine(A.coach(S.data, 'waterL', S.sel, S.targets))}
    </div>`;
  }

  function heartCard(d) {
    const v = A.value(S.data, 'rhr', S.sel), hr = d.hr;
    const bpm = v || (hr && hr.avg) || null;
    return `<div class="card tall" style="--i:6" data-metric="rhr" role="button" tabindex="0" aria-label="Resting heart rate ${v == null ? 'not recorded' : fmt(v) + ' bpm'}. Open details.">
      <div class="ch" style="color:var(--heart)">${bpm ? `<span class="beat" style="--p:${(60 / bpm).toFixed(3)}s;--o:-${Math.round(performance.now() % (60000 / bpm))}ms">${svg('heart')}</span>` : svg('heart')}<span style="color:var(--ink)">Heart</span></div>
      ${bpm ? `<canvas class="ecg" id="ecg" data-bpm="${bpm}" aria-hidden="true"></canvas><span class="vs">Trace paced to your resting rate, not a live reading</span>` : '<div class="grow"></div>'}
      <div class="grow"></div>
      <div class="num" style="font-size:36px">${N('rhr', v)}<small>bpm resting</small></div>
      ${hr ? `<div class="hr-range"><span>Low <b>${hr.min}</b></span><span>Avg <b>${hr.avg}</b></span><span>High <b>${hr.max}</b></span></div>` : ''}
      ${vsNormal('rhr')}
      ${coachLine(A.coach(S.data, 'rhr', S.sel, S.targets))}
    </div>`;
  }

  function caloriesCard(d) {
    const v = A.value(S.data, 'kcal', S.sel), t = S.targets;
    const macro = (l, k, c) => { const x = A.value(S.data, k, S.sel); return `<div style="display:grid;grid-template-columns:52px 1fr;gap:6px;align-items:center;font-size:11.5px;font-weight:600;font-variant-numeric:tabular-nums">${l} ${x == null ? '–' : fmt(x) + 'g'}${track(x == null ? 0 : t[k] ? x / t[k] : 1, c)}</div>`; };
    return `<div class="card" style="--i:7" data-metric="kcal" role="button" tabindex="0" aria-label="Calories eaten ${v == null ? 'not logged' : fmt(v)}. Open details.">
      <div class="ch" style="color:var(--cal)">${svg('food')}<span style="color:var(--ink)">Food</span></div>
      <div class="num">${N('kcal', v)}<small>kcal</small></div>
      ${v == null && A.value(S.data, 'proteinG', S.sel) == null ? '<div class="vs">No food logged in Health this day</div>' : `${macro('P', 'proteinG', 'var(--cal)')}${macro('C', 'carbsG', 'var(--cal)')}${macro('F', 'fatG', 'var(--cal)')}`}
    </div>`;
  }

  function ringsCard(d) {
    const r = d.rings;
    if (!r || !r.moveGoal) return `<div class="card span2" style="--i:8"><div class="ch" style="color:var(--r-move)">${svg('rings')}<span style="color:var(--ink)">Rings</span></div><div class="vs">No Activity rings for this day. They come from an Apple Watch.</div></div>`;
    const line = (n, v, g, u, c) => `<div class="ring-line"><div class="top2"><span>${n}</span><span>${fmt(v)} / ${fmt(g)} ${u}</span></div><div class="soft-track"><i style="width:${Math.round(Math.min(1, v / g) * 100)}%;background:linear-gradient(90deg,var(${c}-2),var(${c}))"></i></div></div>`;
    const rg = (f, c, rad, id) => { const C = 2 * Math.PI * rad; return `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(${c}-2)"/><stop offset="1" stop-color="var(${c})"/></linearGradient>
      <circle cx="54" cy="54" r="${rad}" fill="none" stroke="var(${c})" stroke-opacity=".15" stroke-width="9"/>
      <circle cx="54" cy="54" r="${rad}" fill="none" stroke="url(#${id})" stroke-width="9" stroke-linecap="round" stroke-dasharray="${(C * Math.min(1, f)).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 54 54)" style="transition:stroke-dasharray 1.2s var(--ease)"/>`; };
    const all = r.move >= r.moveGoal && r.ex >= r.exGoal && r.stand >= r.standGoal;
    const remEx = Math.max(0, (r.exGoal || 0) - (r.ex || 0));
    return `<div class="card span2" style="--i:8;gap:12px">
      <div class="ch" style="color:var(--r-move)">${svg('rings')}<span style="color:var(--ink)">Rings</span><span class="end">${all ? 'All closed' : 'From your Apple Watch'}</span></div>
      <div class="ring-row"><svg class="rings" viewBox="0 0 108 108" role="img" aria-label="Move ${Math.round((r.move / r.moveGoal) * 100)}%, exercise ${Math.round((r.ex / r.exGoal) * 100)}%, stand ${Math.round((r.stand / r.standGoal) * 100)}%">
        ${rg(r.move / r.moveGoal, '--r-move', 49, 'rg1')}${rg(r.ex / r.exGoal, '--r-exer', 37, 'rg2')}${rg(r.stand / r.standGoal, '--r-stand', 25, 'rg3')}</svg>
        <div class="ring-meta">${line('Move', r.move, r.moveGoal, 'kcal', '--r-move')}${line('Exercise', r.ex, r.exGoal, 'min', '--r-exer')}${line('Stand', r.stand, r.standGoal, 'h', '--r-stand')}</div></div>
      <div class="coach"><span>${all ? 'Every ring closed. Lovely work.' : remEx ? `${fmt(remEx)} more exercise minutes would have closed Exercise.` : 'Exercise closed; Move and Stand were close.'}</span></div>
    </div>`;
  }

  function sleepCard(d) {
    const sl = d.sleep;
    if (!sl) return `<div class="card span2" style="--i:9" data-metric="sleepH" role="button" tabindex="0"><div class="ch" style="color:var(--sleep)">${svg('moon')}<span style="color:var(--ink)">Sleep</span></div><div class="vs">No sleep recorded for the night before ${esc(longDay(S.sel))}.</div></div>`;
    const sc = A.sleepScore(sl, S.targets.sleepH);
    const hrs = (m) => `${Math.floor(m / 60)}h ${String(Math.round(m % 60)).padStart(2, '0')}m`;
    let hyp = '';
    if (sl.segs && sl.segs.length && sl.staged) {
      const W = 320, Hh = 92, L = 34, top = 6, rowH = 20, lv = { awake: 0, rem: 1, core: 2, deep: 3 }, span = Math.max(1, sl.segs[sl.segs.length - 1][1]);
      const rows = ['Awake', 'REM', 'Core', 'Deep'].map((n, i) => `<text x="0" y="${top + i * rowH + 13}">${n}</text><line x1="${L}" x2="${W}" y1="${top + i * rowH + rowH / 2}" y2="${top + i * rowH + rowH / 2}" stroke="var(--track)"/>`).join('');
      const bars = sl.segs.map(([a, b, k]) => `<rect x="${(L + ((W - L) * a) / span).toFixed(1)}" y="${top + lv[k] * rowH + 3}" width="${Math.max(1.5, ((W - L) * (b - a)) / span - 0.6).toFixed(1)}" height="${rowH - 6}" rx="4" fill="var(--s-${k})"/>`).join('');
      hyp = `<svg class="hypno" viewBox="0 0 ${W} ${Hh}" role="img" aria-label="Sleep stages through the night, ${sl.bed} to ${sl.wake}">${rows}${bars}</svg>`;
    }
    const st = sl.stages;
    return `<div class="card span2" style="--i:9;gap:12px" data-metric="sleepH" role="button" tabindex="0" aria-label="Sleep ${hrs(sl.asleepMin)}, score ${sc.score}. Open details.">
      <div class="ch" style="color:var(--sleep)">${svg('moon')}<span style="color:var(--ink)">Sleep</span><span class="end">${esc(sl.bed)} – ${esc(sl.wake)}</span></div>
      <div class="sleep-top">${ring(70, 7, sc.score / 100, 'var(--s-core)', N('sleepscore', sc.score))}
        <div class="facts">
          <div><b>${hrs(sl.asleepMin)}</b><span>Asleep</span></div><div><b>${sc.label}</b><span>Sleep score</span></div><div><b>${sc.efficiency}%</b><span>Efficiency</span></div>
          <div><b>${hrs(sl.inBedMin)}</b><span>In bed</span></div><div><b>${fmt(st.awake)}m</b><span>Awake</span></div><div><b>${A.value(S.data, 'hrv', S.sel) == null ? '–' : fmt(A.value(S.data, 'hrv', S.sel)) + ' ms'}</b><span>HRV</span></div>
        </div></div>
      ${hyp}
      ${sl.staged ? `<div class="stages">${[['REM', 'rem'], ['Core', 'core'], ['Deep', 'deep'], ['Awake', 'awake']].map(([n, k]) => `<div class="stage"><span class="k"><i style="background:var(--s-${k})"></i>${n}</span><b>${hrs(st[k])}</b><span class="note" style="font-size:11px">${k === 'awake' ? '&nbsp;' : Math.round((st[k] / sl.asleepMin) * 100) + '%'}</span></div>`).join('')}</div>`
        : '<div class="vs">This source records sleep without stages.</div>'}
      <div class="vs">From ${esc(sl.source)}</div>
      ${coachLine(A.coach(S.data, 'sleepH', S.sel, S.targets))}
    </div>`;
  }

  function smallCard(k, icon, color, i) {
    const m = A.METRICS[k], v = metricValue(k), l = m.carry ? A.latest(S.data, k, S.sel) : null;
    return `<div class="card" style="--i:${i}" data-metric="${k}" role="button" tabindex="0" aria-label="${m.name}: ${v == null ? 'not recorded' : fmt(v, m.d) + ' ' + m.unit}. Open details.">
      <div class="ch" style="color:${color}">${svg(icon)}<span style="color:var(--ink)">${m.short || m.name}</span></div>
      <div class="num">${N(k, v, m.d)}<small>${m.unit}</small></div>
      ${l && l.day !== S.sel ? `<div class="vs">Measured ${shortDay(l.day)}</div>` : vsNormal(k)}
      <div class="grow"></div>${coachLine(A.coach(S.data, k, S.sel, S.targets))}
    </div>`;
  }

  const pretty = (t) => t.replace(/([a-z])([A-Z])/g, '$1 $2').replace('Traditional Strength Training', 'Strength training').replace('Functional Strength Training', 'Functional strength');
  function workoutsCard() {
    const days = range(addDays(S.sel, -6), S.sel);
    const list = days.flatMap((k) => ((S.data.days[k] && S.data.days[k].workouts) || []).map((w) => ({ ...w, day: k }))).reverse();
    return `<div class="card span2" style="--i:14">
      <div class="ch" style="color:var(--vo2)">${svg('run')}<span style="color:var(--ink)">Workouts</span><span class="end">7 days to ${shortDay(S.sel)}</span></div>
      ${list.length ? `<div class="rows">${list.slice(0, 6).map((w) => `<div class="row"><span class="ico" style="background:var(--vo2)">${svg('run')}</span><div><div class="rt">${esc(pretty(w.type || 'Workout'))}</div><div class="rs">${wk(w.day)} ${shortDay(w.day)}</div></div><span class="end">${w.mins == null ? '' : fmt(w.mins) + ' min'}</span></div>`).join('')}</div>`
        : '<div class="vs">No workouts recorded in these 7 days.</div>'}
    </div>`;
  }

  // ---------- ECG (decorative, paced to resting heart rate) ----------
  function ecgValue(t, period) {
    const n = Math.floor(t / period), p = (t - n * period) / period;
    const g = (mu, a, w) => a * Math.exp(-((p - mu) ** 2) / (2 * w * w));
    return g(0.16, 0.11, 0.022) + g(0.285, -0.09, 0.008) + g(0.31, 1 + 0.06 * Math.sin(n * 1.7), 0.0085) + g(0.335, -0.2, 0.01) + g(0.56, 0.24, 0.045) + 0.025 * Math.sin(t / 2300);
  }
  let ecgColour = '', ecgAt = 0;
  function drawEcg(now) {
    const cv = document.getElementById('ecg');
    if (cv && cv.offsetParent) {
      const dpr = devicePixelRatio || 1, w = cv.clientWidth, h = cv.clientHeight;
      if (w && h) {
        if (cv.width !== Math.round(w * dpr)) { cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr); }
        if (!ecgColour || now - ecgAt > 1000) { ecgColour = getComputedStyle(cv).getPropertyValue('--heart').trim() || '#FF6B2C'; ecgAt = now; }
        const ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
        const period = 60000 / Number(cv.dataset.bpm || 60), span = period * 2.6, mid = h * 0.62, amp = h * 0.5, t = reduce ? period * 0.9 : now;
        ctx.globalAlpha = 0.08; ctx.strokeStyle = ecgColour; ctx.lineWidth = 1;
        for (let gx = 0; gx <= w; gx += 12) { ctx.beginPath(); ctx.moveTo(gx, 0); ctx.lineTo(gx, h); ctx.stroke(); }
        ctx.globalAlpha = 1; ctx.lineWidth = 2; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
        const grad = ctx.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, 'rgba(0,0,0,0)'); grad.addColorStop(0.35, ecgColour); grad.addColorStop(1, ecgColour);
        ctx.strokeStyle = grad; ctx.beginPath();
        for (let x = 0; x <= w; x++) { const y = mid - ecgValue(t - span + (span * x) / w, period) * amp; x ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
        ctx.stroke();
        ctx.fillStyle = ecgColour; ctx.shadowColor = ecgColour; ctx.shadowBlur = 10; ctx.beginPath(); ctx.arc(w - 2, mid - ecgValue(t, period) * amp, 3.2, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      }
    }
    if (!reduce) requestAnimationFrame(drawEcg);
  }

  // ---------- metric detail ----------
  const TYPE_OF = { steps: 'StepCount', rhr: 'RestingHeartRate', hrv: 'HeartRateVariabilitySDNN', spo2: 'OxygenSaturation', vo2: 'VO2Max', weightKg: 'BodyMass',
    waterL: 'DietaryWater', kcal: 'DietaryEnergyConsumed', proteinG: 'DietaryProtein', sleepH: 'SleepAnalysis', exerciseMin: 'AppleExerciseTime', resp: 'RespiratoryRate' };
  function chart(k) {
    const m = A.METRICS[k], pts = A.series(S.data, k, S.sel, 90), b = A.baseline(S.data, k, S.sel), t = S.targets[k];
    const vals = pts.map((p) => p.v).filter((v) => v != null);
    if (!vals.length) return '<p class="note">No readings in the last 90 days.</p>';
    const W = 340, H = 170, L = 38, R = 6, T = 12, B = 20;
    let hi = Math.max(...vals, t || -Infinity, b ? b.mean + b.sd : -Infinity), lo = m.better === 'up' && ['steps', 'waterL', 'kcal', 'proteinG', 'exerciseMin', 'sleepH'].includes(k) ? 0 : Math.min(...vals, b ? b.mean - b.sd : Infinity);
    const pad = (hi - lo) * 0.08 || 1; hi += pad; if (lo !== 0) lo -= pad;
    const y = (v) => T + (H - T - B) * (1 - (v - lo) / (hi - lo)), x = (i) => L + ((W - L - R) * i) / (pts.length - 1);
    const ticks = [lo, (lo + hi) / 2, hi];
    const grid = ticks.map((v) => `<line x1="${L}" x2="${W - R}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}" stroke="var(--track)"/><text x="${L - 6}" y="${(y(v) + 3).toFixed(1)}" text-anchor="end">${fmt(v, hi - lo < 10 ? 1 : 0)}</text>`).join('');
    const band = b ? `<rect x="${L}" width="${W - L - R}" y="${y(b.mean + b.sd).toFixed(1)}" height="${Math.max(0, y(b.mean - b.sd) - y(b.mean + b.sd)).toFixed(1)}" fill="var(--track)" rx="4"/>` : '';
    const goal = t ? `<line x1="${L}" x2="${W - R}" y1="${y(t).toFixed(1)}" y2="${y(t).toFixed(1)}" stroke="var(--muted)" stroke-dasharray="4 4"/><text x="${L + 2}" y="${(y(t) - 4).toFixed(1)}">Target ${fmt(t, m.d)}</text>` : '';
    let path = '', seg = [];
    pts.forEach((p, i) => { if (p.v == null) { if (seg.length) { path += 'M' + seg.join('L'); seg = []; } } else seg.push(`${x(i).toFixed(1)},${y(p.v).toFixed(1)}`); });
    if (seg.length) path += 'M' + seg.join('L');
    const lastV = pts[pts.length - 1].v;
    return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${m.name}, last 90 days">${grid}${band}${goal}
      <path d="${path}" fill="none" stroke="var(--brand)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
      ${lastV != null ? `<circle cx="${x(pts.length - 1)}" cy="${y(lastV).toFixed(1)}" r="4.5" fill="var(--brand)"/>` : ''}
      <text x="${L}" y="${H - 4}">${shortDay(pts[0].day)}</text><text x="${W - R}" y="${H - 4}" text-anchor="end">${shortDay(S.sel)}</text></svg>
      <p class="note" style="font-size:12px">${b ? 'Shaded band: your normal range (average ± 1 standard deviation over the previous 90 days).' : ''}${t ? ' Dashed line: your target.' : ''}</p>`;
  }
  function openDetail(k) {
    const m = A.METRICS[k], v = metricValue(k), b = A.baseline(S.data, k, S.sel), a7 = A.average(S.data, k, S.sel), tr = A.trend(S.data, k, S.sel), c = A.coach(S.data, k, S.sel, S.targets);
    const n90 = A.series(S.data, k, S.sel, 90).filter((p) => p.v != null).length;
    const type = TYPE_OF[k];
    const srcs = type ? S.data.sources.filter((s) => s.types && s.types[type]).map((s) => `${s.name} (${fmt(s.types[type])} readings)`) : [];
    openSheet(m.name, `
      <div class="block"><div class="num" style="font-size:44px">${v == null ? '–' : fmt(v, m.d)}<small>${m.unit}</small></div><div class="note">${esc(longDay(S.sel))}</div></div>
      ${c.safety ? `<div class="block" style="color:var(--warn)">${esc(c.safety)}</div>` : ''}
      <div class="block"><div class="t-${c.tone}" style="font-size:18px;font-weight:700">${esc(c.h)}</div>
        <div><div class="lab">What it means</div><p class="p">${esc(c.mean)}</p></div>
        <div><div class="lab">What to do</div><p class="p">${esc(c.act)}</p></div></div>
      <div class="block"><div class="lab">Last 90 days</div>${chart(k)}
        <div class="how-grid" style="font-size:13px;color:var(--muted)">
          <span>7-day average</span><span>${a7 == null ? '–' : fmt(a7, m.d) + ' ' + m.unit}</span>
          <span>Your normal (90 days)</span><span>${b ? `${fmt(b.mean, m.d)} ± ${fmt(b.sd, m.d)}` : 'not enough data'}</span>
          <span>14-day trend</span><span>${tr}</span><span>Days with readings</span><span>${n90} of 90</span></div></div>
      <div class="block"><div class="lab">Source</div><p class="note">${srcs.length ? esc(srcs.join(' · ')) : 'Apple Health'}${k === 'steps' ? '. Where devices overlap, BE keeps the higher count for each hour so steps are not doubled.' : ''}</p></div>
      <p class="note">General wellness information, not medical advice. If you're worried about your health, talk to your GP.</p>`);
  }

  // ---------- data sheet ----------
  function openData() {
    const D = S.data, me = D.me || {};
    const age = me.dob ? Math.floor((Date.parse(D.lastDataDay) - Date.parse(me.dob)) / (365.25 * 86400000)) : null;
    const h = A.latest(D, 'heightCm', D.lastDataDay, 3650), w = A.latest(D, 'weightKg', D.lastDataDay, 365);
    const icon = { watch: ['watch', 'var(--heart)'], fitbit: ['wave', 'var(--water)'], iphone: ['phone', 'var(--steps)'], app: ['app', 'var(--cal)'] };
    openSheet('Your data', `
      <div class="block"><div class="lab">Export</div>
        <div class="how-grid" style="font-size:14px;color:var(--muted);margin:0">
          <span>Exported</span><span>${esc(D.exportDate ? D.exportDate.slice(0, 16) : 'unknown')}</span>
          <span>Latest day with data</span><span>${esc(longDay(D.lastDataDay))}</span>
          <span>History kept</span><span>${shortDay(D.firstDay)} – ${shortDay(D.lastDataDay)}</span>
          <span>Records read</span><span>${fmt(D.recordsScanned)}</span>
          <span>Imported</span><span>${S.meta ? esc(new Date(S.meta.importedAt).toLocaleString('en-AU', { dateStyle: 'medium', timeStyle: 'short' })) : ''}</span></div>
        <p class="note">${daysBetween(D.lastDataDay, localToday()) > 1 ? `This data is ${daysBetween(D.lastDataDay, localToday())} days old. Export again from the Health app to update.` : 'Up to date as of the export.'}</p></div>
      <div class="block"><div class="lab">Devices and apps in your export</div><div class="rows">
        ${D.sources.slice(0, 12).map((s) => { const [ic, col] = icon[s.kind] || icon.app; return `<div class="row"><span class="ico" style="background:${col}">${svg(ic)}</span><div style="min-width:0"><div class="rt">${esc(s.name)}</div><div class="rs">${esc(Object.keys(s.types || {}).slice(0, 4).map(pretty).join(', '))}</div></div><span class="end">${fmt(s.count)}<br><span class="rs">${shortDay(s.first)} – ${shortDay(s.last)}</span></span></div>`; }).join('')}
      </div></div>
      <div class="block" style="flex-direction:row;align-items:center"><div style="flex:1"><div class="lab">Your name</div><p class="p">${S.name ? esc(S.name) : 'Not set'}</p></div><button class="btn glass" style="width:auto;padding:10px 16px" data-act="name">Change</button></div>
      <div class="block"><div class="lab">Profile from Apple Health</div>
        <div class="how-grid" style="font-size:14px;color:var(--muted);margin:0">
          <span>Age</span><span>${age == null ? 'Not set' : age}</span><span>Biological sex</span><span>${me.sex ? esc(me.sex) : 'Not set'}</span>
          <span>Blood type</span><span>${me.blood ? esc(me.blood) : 'Not set'}</span><span>Height</span><span>${h ? fmt(h.v) + ' cm' : 'Not recorded'}</span>
          <span>Weight</span><span>${w ? `${fmt(w.v, 1)} kg (${shortDay(w.day)})` : 'Not recorded'}</span></div>
        <p class="note">Edit these in the Health app under your profile. BE has no account.</p></div>
      <label class="btn ink" for="file-in2">${svg('upload')}Import a newer export</label>
      <input id="file-in2" type="file" accept=".zip,.xml,application/zip,text/xml" hidden>
      <button class="btn danger" data-act="forget">Delete imported data from this browser</button>
      <p class="note">Only daily totals are stored, in this browser, and never uploaded. Live, automatic sync with Apple Health needs the BE iPhone app.</p>`);
  }

  // ---------- import ----------
  let job = null;
  function startImport(file) {
    if (!file) return;
    if (job) job.cancel();
    const mb = (x) => fmt(x / 1048576, 1);
    openSheet('Reading your export', `<div class="progress" id="imp">
        ${ring(120, 10, 0, 'var(--brand)', '<span id="imp-pct">0%</span>')}
        <div><b id="imp-phase">Opening ${esc(file.name)}</b><div class="note" id="imp-sub">${mb(file.size)} MB</div></div>
        <p class="note">Large exports take a minute or two. Keep this page open. Nothing leaves your device.</p>
        <button class="btn glass" data-act="cancel-import">Cancel</button></div>`, { dismissable: false });
    let worker = null, done = false;
    const update = (p) => {
      const pct = p.total ? Math.min(100, Math.round((p.done / p.total) * 100)) : 0;
      const r = $('#imp .arc'); if (r) { const C = 2 * Math.PI * 55; r.setAttribute('stroke-dasharray', `${((C * pct) / 100).toFixed(1)} ${C.toFixed(1)}`); }
      const e1 = $('#imp-pct'), e2 = $('#imp-phase'), e3 = $('#imp-sub');
      if (e1) e1.textContent = pct + '%';
      if (e2) e2.textContent = p.phase === 'building' ? 'Building your dashboard' : 'Reading records';
      if (e3) e3.textContent = `${fmt(p.records)} records · ${mb(p.done)} of ${mb(p.total)} MB`;
    };
    const finish = async (result) => {
      done = true; job = null; if (worker) worker.terminate();
      if (!result || !result.lastDataDay) { showImportError('No health records were found in this file. Choose the export.zip made by the Health app.'); return; }
      S.data = result; S.meta = { fileName: file.name, size: file.size, importedAt: Date.now() };
      S.sel = result.lastDataDay;
      await store.put('kv', 'data', result); await store.put('kv', 'meta', S.meta);
      ensureTargets();
      closeSheet();
      renderAll('today');
      toast('check', 'var(--good)', `${fmt(Object.keys(result.days).length)} days imported`, `${result.sources.length} sources · data to ${shortDay(result.lastDataDay)}`);
    };
    const fail = (msg) => { done = true; job = null; if (worker) worker.terminate(); showImportError(msg); };
    const onMsg = (m) => { if (done) return; if (m.type === 'progress') update(m); else if (m.type === 'done') finish(m.result); else if (m.type === 'error') fail(m.message); };
    const mainThread = () => { // fallback when workers are unavailable; parsing still streams chunk by chunk
      beParserModule(null).parseExport(file, (p) => onMsg({ type: 'progress', ...p })).then((r) => onMsg({ type: 'done', result: r })).catch((e) => onMsg({ type: 'error', message: e.message || String(e) }));
    };
    try {
      const url = URL.createObjectURL(new Blob([PARSER_SRC + '\nbeParserModule(self);'], { type: 'text/javascript' }));
      worker = new Worker(url);
      worker.onmessage = (e) => onMsg(e.data);
      worker.onerror = (e) => { e.preventDefault(); worker.terminate(); worker = null; mainThread(); };
      worker.postMessage({ file });
    } catch (e) { worker = null; mainThread(); }
    job = { cancel: () => { done = true; if (worker) worker.terminate(); job = null; } };
  }
  function showImportError(msg) {
    openSheet('Couldn\'t read that file', `<p class="p">${esc(msg)}</p><label class="btn ink" for="file-in3">Choose another file</label><input id="file-in3" type="file" accept=".zip,.xml,application/zip,text/xml" hidden>`);
  }
  function wireDrop(root) {
    const zone = root.querySelector('#drop'); if (!zone) return;
    zone.addEventListener('dragover', (e) => { e.preventDefault(); zone.classList.add('over'); });
    zone.addEventListener('dragleave', () => zone.classList.remove('over'));
    zone.addEventListener('drop', (e) => { e.preventDefault(); e.stopPropagation(); zone.classList.remove('over'); const f = e.dataTransfer && e.dataTransfer.files[0]; if (f) startImport(f); });
  }

  // ---------- STREAKS ----------
  function renderStreaks(enter) {
    const el = $('#v-streaks');
    if (!S.data) { el.innerHTML = `${header()}<h1 tabindex="-1">Streaks</h1>${needData()}`; return play(el, enter); }
    const st = A.streaks(S.data, S.data.lastDataDay, S.targets), bd = A.badges(S.data, S.data.lastDataDay, S.targets, st);
    const ic = { steps: 'steps', exerciseMin: 'run', sleepH: 'moon', waterL: 'drop', rings: 'rings' };
    const best = Object.values(st).reduce((a, s) => Math.max(a, s.current), 0);
    el.innerHTML = `${header()}
      <h1 tabindex="-1" style="--i:0">Keep it<br><span class="soft">going</span></h1>
      <div class="card" style="--i:1;gap:12px"><div class="ch">${svg('flame', 'style="color:var(--brand)"')}<span>Current streaks</span><span class="end">to ${shortDay(S.data.lastDataDay)}</span></div>
        ${Object.entries(st).map(([k, s]) => `<div class="goal"><div style="min-width:0"><div class="gn">${s.name}</div><div class="gs">Best ${s.best} · ${s.hits30} of last 30 days</div>
          <div class="week" aria-label="Last 7 days">${s.week.map((on) => `<i class="${on ? 'on' : ''}"></i>`).join('')}</div></div>
          <div class="cur"><b>${N('st-' + k, s.current)}</b><span>day${s.current === 1 ? '' : 's'}</span></div></div>`).join('')}
        <p class="note">${best ? 'Counted from your Health history against your targets in Plan.' : 'No current streaks yet. Targets you can hit most days build them fastest; adjust them in Plan.'}</p></div>
      <div class="card" style="--i:2;gap:12px"><div class="ch">${svg('seal', 'style="color:var(--brand)"')}<span>Badges</span><span class="end">${bd.filter((b) => b.on).length} of ${bd.length}</span></div>
        <div class="badges">${bd.map((b) => `<div class="badge ${b.on ? 'on' : ''}"><div class="disc">${svg(b.on ? 'seal' : 'lock')}</div>${esc(b.title)}<small>${esc(b.detail)}</small></div>`).join('')}</div></div>`;
    countUp(el); play(el, enter);
  }
  const needData = () => `<div class="card" style="gap:12px"><p class="p">Import your Apple Health export first. Everything here is calculated from it.</p><button class="btn ink" data-tab-go="today">Go to import</button></div>`;

  // ---------- PLAN ----------
  const STEP = { steps: 500, sleepH: 0.25, exerciseMin: 5, waterL: 0.25, proteinG: 5, kcal: 50 };
  function renderPlan(enter) {
    const el = $('#v-plan');
    const keys = ['steps', 'sleepH', 'exerciseMin', 'waterL', 'proteinG', 'kcal'];
    el.innerHTML = `${header()}
      <h1 tabindex="-1" style="--i:0">Your<br><span class="soft">daily targets</span></h1>
      <div class="card" style="--i:1;gap:12px">
        ${keys.map((k) => { const m = A.METRICS[k], v = S.targets[k]; const reason = v == null ? 'Not set.' : A.REASONS[k] && S.data ? A.REASONS[k](S.data, S.data.lastDataDay) : ''; return `<div class="target">
          <div style="min-width:0"><div class="tn">${m.name}</div><div class="tr">${esc(reason)}</div></div>
          <div class="tv">${v == null ? '–' : Number(v.toFixed(2)).toLocaleString('en-AU', { maximumFractionDigits: 2 })} ${m.unit}</div>
          <div class="stepper"><button data-step="${k}" data-dir="-1" aria-label="Decrease ${m.name}">−</button><button data-step="${k}" data-dir="1" aria-label="Increase ${m.name}">+</button></div></div>`; }).join('')}
      </div>
      ${S.data ? '<button class="btn glass" data-act="reset-targets" style="--i:2">Reset to recommended</button>' : ''}
      <p class="note" style="padding:0 4px">Recommendations come from your own 90-day averages. Calories count as met within 10% either way, so eating far less never counts. Saved in this browser.</p>`;
    play(el, enter);
  }

  // ---------- SNAP ----------
  // Meal photos are analysed by Claude through this page's sample capability, then saved in this browser.
  function renderSnap(enter) {
    const el = $('#v-snap');
    el.innerHTML = `${header()}
      <h1 tabindex="-1" style="--i:0">${S.snapMode === 'meals' ? 'Snap<br><span class="soft">your meal</span>' : 'Track<br><span class="soft">your progress</span>'}</h1>
      <div class="seg" role="tablist" aria-label="Snap mode" style="--i:1"><span class="seg-ind" style="transform:translateX(${S.snapMode === 'meals' ? 0 : 100}%)"></span>
        <button role="tab" aria-selected="${S.snapMode === 'meals'}" data-snapmode="meals">Meals</button><button role="tab" aria-selected="${S.snapMode === 'progress'}" data-snapmode="progress">Progress</button></div>
      ${S.snapMode === 'meals' ? mealsHTML() : progressHTML()}`;
    const f1 = $('#meal-file', el); if (f1) f1.addEventListener('change', (e) => { const f = e.target.files[0]; e.target.value = ''; if (f) analyseMeal(f); });
    const f2 = $('#prog-file', el); if (f2) f2.addEventListener('change', async (e) => { const f = e.target.files[0]; e.target.value = ''; if (!f) return; const img = await shrink(f, 900); if (!img) return; const rec = { id: 'p' + Date.now(), date: Date.now(), img }; S.progress.push(rec); await store.put('progress', rec.id, rec); toast('camera', 'var(--brand)', 'Progress photo saved', 'Kept in this browser, not your photo library'); renderSnap(); });
    countUp(el); play(el, enter);
  }
  function mealsHTML() {
    const today = localToday(), mine = S.meals.filter((m) => m.day === today);
    const sum = (f) => mine.reduce((a, m) => a + (m[f] || 0), 0);
    return `<div class="card" style="--i:2;align-items:center;text-align:center;gap:10px;padding:20px 16px 16px">
        <div class="lens"><div class="face ${S.snapBusy ? 'scan' : ''}">${S.snapImg ? `<img src="${S.snapImg}" alt="Your meal">` : svg('camera')}</div></div>
        <div style="font-size:20px;font-weight:700;letter-spacing:-0.02em">${S.snapBusy ? 'Reading your plate…' : 'Point, shoot, check'}</div>
        <p class="note" style="max-width:32ch">Claude estimates each food, its portion, calories and macros. You check and edit before it's saved.</p>
        <div class="btn-row" style="width:100%"><label class="btn ink" for="meal-file" role="button" tabindex="0">${svg('camera')}Photo</label><button class="btn glass" data-act="manual">Type it</button></div>
        <input id="meal-file" type="file" accept="image/*" hidden></div>
      <div class="card" style="--i:3"><div class="lab">Logged in BE today</div>
        <div class="totals">${[['kcal', 'kcal'], ['p', 'Protein g'], ['c', 'Carbs g'], ['f', 'Fat g']].map(([f, l]) => `<div><b>${fmt(sum(f))}</b><span>${l}</span></div>`).join('')}</div>
        <p class="note">Meals saved here stay in this browser. A web page can't write to Apple Health.</p></div>
      ${calendarHTML()}`;
  }
  function calendarHTML() {
    if (!S.calMonth) { const d = new Date(); S.calMonth = [d.getFullYear(), d.getMonth()]; }
    const [y, m] = S.calMonth, first = new Date(Date.UTC(y, m, 1)), lead = (first.getUTCDay() + 6) % 7, n = new Date(Date.UTC(y, m + 1, 0)).getUTCDate(), today = localToday();
    const byDay = {}; S.meals.forEach((x) => (byDay[x.day] ||= []).push(x));
    let cells = ''; for (let i = 0; i < lead; i++) cells += '<span class="cal-cell blank"></span>';
    for (let d = 1; d <= n; d++) {
      const key = `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`, mine = byDay[key] || [], last = mine.filter((x) => x.img).pop();
      const hk = S.data && A.value(S.data, 'kcal', key) != null;
      const any = mine.length || hk;
      cells += `<button class="cal-cell ${key === today ? 'today' : ''} ${last ? 'photo' : ''}" ${any ? `data-calday="${key}"` : 'disabled'} aria-label="${d}${mine.length ? `, ${mine.length} meals in BE` : ''}${hk ? ', food logged in Apple Health' : ''}" ${last ? `style="background-image:url(${last.img})"` : ''}>
        <span class="d">${d}</span>${mine.length ? `<span class="c">${mine.length}</span>` : ''}${hk && !last ? '<i class="hk"></i>' : ''}</button>`;
    }
    return `<div class="card" style="--i:4;gap:10px"><div class="ch">${svg('food', 'style="color:var(--cal)"')}<span>Meal diary</span><span class="end cal-nav"><button data-cal="-1" aria-label="Previous month">‹</button>${first.toLocaleDateString('en-AU', { month: 'short', year: 'numeric', timeZone: 'UTC' })}<button data-cal="1" aria-label="Next month">›</button></span></div>
      <div class="cal-head">${['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((x) => `<span>${x}</span>`).join('')}</div><div class="cal">${cells}</div>
      <p class="note" style="font-size:12px">Photos are your meals logged in BE. Purple dots are days with food logged in Apple Health.</p></div>`;
  }
  function openDay(key) {
    const mine = S.meals.filter((x) => x.day === key);
    const hk = S.data ? ['kcal', 'proteinG', 'carbsG', 'fatG'].map((k) => A.value(S.data, k, key)) : [null];
    openSheet(longDay(key), `
      ${mine.map((x) => `<div class="block" style="flex-direction:row;align-items:center;gap:12px">${x.img ? `<img src="${x.img}" alt="" style="width:72px;height:72px;border-radius:14px;object-fit:cover">` : ''}
        <div style="min-width:0;display:flex;flex-direction:column;gap:3px"><b>${esc(x.name)}</b><span class="note">${new Date(x.at).toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' })} · ${fmt(x.kcal)} kcal · P ${fmt(x.p)} · C ${fmt(x.c)} · F ${fmt(x.f)} g</span>
        <button class="btn danger" style="padding:6px 10px;width:auto;font-size:13px" data-delmeal="${x.id}">Delete</button></div></div>`).join('')}
      ${hk[0] != null ? `<div class="block"><div class="lab">Logged in Apple Health</div><p class="p">${fmt(hk[0])} kcal${hk[1] != null ? ` · protein ${fmt(hk[1])} g` : ''}${hk[2] != null ? ` · carbs ${fmt(hk[2])} g` : ''}${hk[3] != null ? ` · fat ${fmt(hk[3])} g` : ''}</p></div>` : ''}`);
  }
  function progressHTML() {
    const list = [...S.progress].sort((a, b) => a.date - b.date), first = list[0], last = list[list.length - 1];
    const dstr = (t) => new Date(t).toLocaleDateString('en-AU', { day: 'numeric', month: 'short' });
    const wAt = (t) => { if (!S.data) return null; const d = new Date(t); const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; const l = A.latest(S.data, 'weightKg', k > S.data.lastDataDay ? S.data.lastDataDay : k, 30); return l ? l.v : null; };
    const w1 = first && wAt(first.date), w2 = last && wAt(last.date);
    return `<div class="card" style="--i:2;align-items:center;text-align:center;gap:10px;padding:20px 16px 16px">
        <div class="lens"><div class="face">${last ? `<img src="${last.img}" alt="Latest progress photo">` : svg('person', 'style="width:64px;height:64px"')}</div></div>
        <div style="font-size:20px;font-weight:700">${last ? `Last photo ${dstr(last.date)}` : 'Your first progress photo'}</div>
        <p class="note" style="max-width:32ch">Same spot, same light, once a week. Saved in this browser, never in your photo library.</p>
        <label class="btn ink" for="prog-file" role="button" tabindex="0">${svg('camera')}Take progress photo</label><input id="prog-file" type="file" accept="image/*" hidden></div>
      ${list.length >= 2 ? `<div class="card" style="--i:3;gap:10px"><div class="ch">${svg('sparkle', 'style="color:var(--brand)"')}<span>Then and now</span><span class="end">${Math.max(1, Math.round((last.date - first.date) / 86400000))} days</span></div>
        <div class="compare"><figure><img src="${first.img}" alt="First photo"><figcaption>${dstr(first.date)}${w1 ? ` · ${fmt(w1, 1)} kg` : ''}</figcaption></figure><figure><img src="${last.img}" alt="Latest photo"><figcaption>${dstr(last.date)}${w2 ? ` · ${fmt(w2, 1)} kg` : ''}</figcaption></figure></div>
        ${w1 && w2 ? `<p class="note">${Math.abs(w2 - w1) < 0.3 ? 'Weight about the same. Photos often show changes the scale misses.' : `${w2 < w1 ? 'Down' : 'Up'} ${fmt(Math.abs(w2 - w1), 1)} kg between these photos, from Apple Health.`}</p>` : ''}</div>` : ''}
      ${list.length ? `<div class="card" style="--i:4;gap:10px"><div class="ch">${svg('photo')}<span>All photos</span><span class="end">${list.length}</span></div><div class="pgrid">${list.slice().reverse().map((p) => `<button class="pcell" data-progress="${p.id}" style="background-image:url(${p.img})" aria-label="Progress photo ${dstr(p.date)}"><span>${dstr(p.date)}</span></button>`).join('')}</div></div>` : ''}`;
  }
  function shrink(file, max = 720) {
    return new Promise((res) => { const url = URL.createObjectURL(file), img = new Image();
      img.onload = () => { const k = Math.min(1, max / Math.max(img.width, img.height)), c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(url); res(c.toDataURL('image/jpeg', 0.8)); };
      img.onerror = () => { URL.revokeObjectURL(url); res(null); }; img.src = url; });
  }
  const samplerP = window.claude && typeof window.claude.use === 'function' ? window.claude.use('sample').catch(() => null) : Promise.resolve(null);
  let review = null;
  async function analyseMeal(file) {
    S.snapImg = await shrink(file, 720); S.snapBusy = true; renderSnap();
    const sample = await samplerP;
    let items = null, note = '';
    if (sample) {
      try {
        const caps = await sample.limits().catch(() => null);
        if (!caps || !caps.images) throw { code: 'images_unavailable' };
        const out = await sample.json('This is a photo of a meal. Identify each food you can see and estimate its portion. Reply with only JSON: {"mealName": string, "items": [{"name": string, "portion": string, "grams": number, "kcal": number, "protein": number, "carbs": number, "fat": number, "confidence": number between 0 and 1}]}. Use typical Australian serving sizes. If it is not food, reply {"mealName": "Not a meal", "items": []}.', { images: [file], cache: false });
        if (out && Array.isArray(out.items)) items = { name: String(out.mealName || 'Meal'), items: out.items };
      } catch (e) { note = e && (e.code === 'not_granted' || e.code === 'images_unavailable' || e.code === 'sampling_disabled') ? 'Photo analysis isn\'t available in this view, so enter the meal yourself.' : 'The photo couldn\'t be read. Enter the meal yourself or try another photo.'; }
    } else note = 'Photo analysis isn\'t available here, so enter the meal yourself.';
    S.snapBusy = false; renderSnap();
    openReview(items ? validate(items) : { name: 'Meal', items: [{ name: '', grams: 0, kcal: 0, protein: 0, carbs: 0, fat: 0, confidence: 1 }] }, !!items, note);
  }
  // Same rules as BECore's MealValidator: clamp impossible values, flag doubtful items.
  function validate(m) {
    const cl = (v, lo, hi) => (isFinite(+v) ? Math.min(hi, Math.max(lo, +v)) : lo);
    const items = m.items.map((x) => ({ name: String(x.name || '').slice(0, 80).trim(), portion: String(x.portion || ''), grams: cl(x.grams, 0, 3000), kcal: cl(x.kcal, 0, 5000), protein: cl(x.protein, 0, 300), carbs: cl(x.carbs, 0, 500), fat: cl(x.fat, 0, 300), confidence: cl(x.confidence, 0, 1) }))
      .filter((x) => x.name).map((x) => { const fm = 4 * x.protein + 4 * x.carbs + 9 * x.fat; return { ...x, flag: (fm > 0 && Math.abs(x.kcal - fm) / fm > 0.25) || x.confidence < 0.5 }; });
    return { name: m.name, items };
  }
  function openReview(meal, fromPhoto, note) {
    review = { ...meal, fromPhoto };
    const sum = (f) => review.items.reduce((a, x) => a + (+x[f] || 0), 0);
    openSheet('Review meal', `${note ? `<p class="note" style="color:var(--warn)">${esc(note)}</p>` : ''}
      <input class="text-in boxed" id="meal-name" value="${esc(review.name)}" aria-label="Meal name">
      <div class="block"><div class="totals" id="rv-tot">${[['kcal', 'kcal'], ['protein', 'Protein g'], ['carbs', 'Carbs g'], ['fat', 'Fat g']].map(([f, l]) => `<div><b data-tot="${f}">${fmt(sum(f))}</b><span>${l}</span></div>`).join('')}</div></div>
      <div class="block">${review.items.map((x, i) => `<div class="item"><div class="item-top"><input data-i="${i}" data-f="name" value="${esc(x.name)}" placeholder="Food" aria-label="Food name">${x.flag ? '<span class="flag">Check this</span>' : ''}</div>
        ${x.portion ? `<div class="note" style="font-size:12px">${esc(x.portion)}${x.grams ? ` · about ${fmt(x.grams)} g` : ''}</div>` : ''}
        <div class="fields">${[['kcal', 'kcal'], ['protein', 'Protein'], ['carbs', 'Carbs'], ['fat', 'Fat']].map(([f, l]) => `<label>${l}<input data-i="${i}" data-f="${f}" type="number" inputmode="decimal" min="0" step="any" value="${x[f]}"></label>`).join('')}</div></div>`).join('')}
        <button class="btn glass" data-act="add-item">Add item</button></div>
      <p class="note">${fromPhoto ? 'Estimates from your photo by Claude. Oils, sauces and mixed dishes are hard to judge, so adjust anything that looks off.' : ''}</p>
      <button class="btn ink" data-act="save-meal">Save to diary</button>`);
  }
  async function saveMeal() {
    if (!review) return;
    const items = review.items.filter((x) => String(x.name).trim());
    const sum = (f) => Math.round(items.reduce((a, x) => a + (+x[f] || 0), 0));
    if (!sum('kcal') && !sum('protein')) return toast('x', 'var(--warn)', 'Nothing to save', 'Add a food with calories or protein');
    const rec = { id: 'm' + Date.now(), day: localToday(), at: Date.now(), name: review.name || 'Meal', kcal: sum('kcal'), p: sum('protein'), c: sum('carbs'), f: sum('fat'), img: review.fromPhoto ? S.snapImg : null, items };
    S.meals.push(rec); await store.put('meals', rec.id, rec);
    review = null; S.snapImg = null; closeSheet(); renderSnap();
    toast('food', 'var(--cal)', `${rec.name} saved`, `${fmt(rec.kcal)} kcal in your diary`);
  }

  // ---------- coach ----------
  const SUGGEST = ['Prepare my insights', 'How did I sleep this week?', 'Why is my HRV where it is?', 'Am I ready to train hard?', 'What should I change first?'];
  function coachPrompt() {
    const D = S.data, day = S.data.lastDataDay;
    const recent = range(addDays(day, -13), day).map((k) => { const d = D.days[k] || {}; return { date: k, steps: d.steps ?? null, sleepH: d.sleep ? Math.round(d.sleep.asleepMin / 6) / 10 : null, rhr: d.rhr ?? null, hrv: d.hrv ?? null, exerciseMin: d.exerciseMin ?? null, waterL: d.waterL ?? null, kcal: d.kcal ?? null, workouts: (d.workouts || []).length }; });
    return `You are BE's health coach inside a phone app, talking to ${S.name || 'the user'}. Use Australian English. Be warm, brief and practical: 2-5 short sentences, or up to 4 short lines starting with "• ". Plain text only. Use ONLY the data below, quote real numbers and dates, and compare with their own 90-day normal. Say so when data is missing; never guess values. You are not a doctor: never diagnose, never name medical conditions, never suggest medication or supplements. For anything concerning or persistent, suggest talking to a GP (000 in an emergency). The data is from an Apple Health export; the latest day is ${day}.\n\nSummary (JSON): ${JSON.stringify(A.aiSummary(D, day, S.targets, S.name))}\n\nLast 14 days (JSON): ${JSON.stringify(recent)}`;
  }
  function localAnswer(q) {
    const t = q.toLowerCase(), day = S.data.lastDataDay;
    const k = t.includes('sleep') ? 'sleepH' : t.includes('hrv') ? 'hrv' : t.includes('heart') ? 'rhr' : t.includes('water') ? 'waterL' : t.includes('step') || t.includes('walk') ? 'steps' : t.includes('eat') || t.includes('food') || t.includes('protein') ? 'proteinG' : null;
    if (k) { const c = A.coach(S.data, k, day, S.targets); return `${c.mean} ${c.act}`; }
    const g = A.greeting(S.data, day, S.targets, S.name, true, 12); return `Your BE score for ${shortDay(day)} is ${g.score}. ${g.why}`;
  }
  function openChat(first) {
    if (!S.data) return;
    openSheet('Ask your coach', `<div class="chat-log" id="chat-log" aria-live="polite"></div>
      <div class="chips">${SUGGEST.map((q) => `<button class="chip" data-ask="${esc(q)}">${esc(q)}</button>`).join('')}</div>
      <form class="composer" id="composer"><textarea id="chat-in" rows="1" placeholder="Ask about your health…" aria-label="Your question"></textarea><button class="icon-btn" id="chat-send" type="submit" aria-label="Send" style="background:var(--pill);color:var(--pill-fg)">${svg('up')}</button></form>
      <p class="note" style="font-size:11.5px">Answers by Claude, from your imported data. In the iPhone app this uses Apple Intelligence on the phone, or ChatGPT with your consent. General wellness information, not medical advice.</p>`);
    const log = $('#chat-log');
    if (!S.chat.length) bubble('bot', `Hi${S.name ? ' ' + S.name : ''}. I can see ${fmt(Object.keys(S.data.days).length)} days of your Health data, up to ${shortDay(S.data.lastDataDay)}. Ask me anything, or tap “Prepare my insights”.`);
    else S.chat.forEach((m) => (m.role === 'user' ? bubble('me', m.content) : bubble('bot', m.content)));
    $('#composer').addEventListener('submit', (e) => { e.preventDefault(); const v = $('#chat-in').value.trim(); if (v) ask(v); });
    $('#chat-in').addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#composer').requestSubmit(); } });
    if (first) ask(first);
    log.scrollIntoView({ block: 'end' });
  }
  function bubble(who, text, meta) {
    const log = $('#chat-log'); if (!log) return null;
    const el = document.createElement('div'); el.className = 'msg ' + who; el.textContent = text;
    if (meta) { const m = document.createElement('span'); m.className = 'meta'; m.textContent = meta; el.appendChild(m); }
    log.appendChild(el); el.scrollIntoView({ block: 'end', behavior: reduce ? 'auto' : 'smooth' }); return el;
  }
  async function ask(q) {
    if (S.chatBusy) return;
    const input = $('#chat-in'); if (input) input.value = '';
    bubble('me', q);
    const out = bubble('bot', ''); out.innerHTML = '<span class="typing" aria-label="Thinking"><i></i><i></i><i></i></span>';
    S.chatBusy = true;
    const sample = await samplerP;
    const insights = q === SUGGEST[0];
    try {
      if (!sample) throw { code: 'unavailable' };
      if (insights) {
        const list = await sample.json(`${coachPrompt()}\n\nTask: the 3 most useful insights from this data, most important first. Reply with only a JSON array of exactly 3 objects {"title": at most 6 words, "detail": one sentence quoting numbers and dates, "action": one practical step}.`, { cache: false });
        out.remove();
        (Array.isArray(list) ? list.slice(0, 3) : []).forEach((x) => {
          const c = document.createElement('div'); c.className = 'insight';
          const b = document.createElement('b'); b.textContent = String(x.title || ''); const p = document.createElement('p'); p.textContent = String(x.detail || '');
          const d = document.createElement('div'); d.className = 'do'; const s = document.createElement('strong'); s.textContent = 'Next: '; d.append(s, String(x.action || ''));
          c.append(b, p, d); $('#chat-log').appendChild(c);
        });
        S.chat.push({ role: 'user', content: q }, { role: 'assistant', content: (Array.isArray(list) ? list : []).map((x) => `${x.title}: ${x.detail} Next: ${x.action}`).join('\n') });
      } else {
        S.chat.push({ role: 'user', content: q });
        const { text } = await sample([{ role: 'user', content: coachPrompt() }, ...S.chat.slice(-12)], { cache: false, onText: ({ text }) => { out.textContent = text; } });
        out.textContent = text; S.chat.push({ role: 'assistant', content: text });
        const m = document.createElement('span'); m.className = 'meta'; m.textContent = 'From your data · answered by Claude'; out.appendChild(m);
      }
    } catch (e) {
      const a = localAnswer(q);
      if (out.isConnected) { out.textContent = a; const m = document.createElement('span'); m.className = 'meta'; m.textContent = e && e.code === 'rate_limited' ? 'Built-in coach (AI busy, try again shortly)' : 'Built-in coach (AI not available in this view)'; out.appendChild(m); }
      if (!insights) S.chat.push({ role: 'assistant', content: a });
    } finally { S.chatBusy = false; }
  }

  // ---------- sheets (dialog) ----------
  const dlg = $('#sheet');
  function openSheet(title, body, opts = {}) {
    dlg.innerHTML = `<div class="grab"></div><div class="sheet-in"><div class="sheet-top"><h2 id="sheet-title">${esc(title)}</h2>${opts.dismissable === false ? '' : `<button class="icon-btn" data-close aria-label="Close">${svg('x')}</button>`}</div>${body}</div>`;
    dlg.setAttribute('aria-labelledby', 'sheet-title');
    dlg.dataset.locked = opts.dismissable === false ? '1' : '';
    dlg.setAttribute('closedby', opts.dismissable === false ? 'none' : 'any');
    if (!dlg.open) dlg.showModal();
    dlg.scrollTop = 0;
  }
  function closeSheet() { if (dlg.open) dlg.close(); }
  dlg.addEventListener('cancel', (e) => { if (dlg.dataset.locked) e.preventDefault(); });
  dlg.addEventListener('close', () => { review = null; });
  if (!('closedBy' in HTMLDialogElement.prototype)) {
    dlg.addEventListener('click', (e) => {
      if (e.target !== dlg || dlg.dataset.locked) return;
      const r = dlg.getBoundingClientRect();
      if (r.top <= e.clientY && e.clientY <= r.bottom && r.left <= e.clientX && e.clientX <= r.right) return;
      dlg.close();
    });
  }

  // ---------- toast ----------
  function toast(icon, color, title, sub) {
    document.querySelectorAll('.toast').forEach((t) => t.remove());
    const el = document.createElement('div'); el.className = 'toast'; el.setAttribute('role', 'status');
    el.innerHTML = `<span class="ic" style="background:${color}">${svg(icon)}</span><div style="min-width:0"><b>${esc(title)}</b><span>${esc(sub)}</span></div>`;
    $('#phone').appendChild(el); setTimeout(() => el.remove(), 2800);
  }

  // ---------- navigation ----------
  function play(el, enter) {
    if (!enter || reduce) return;
    el.classList.remove('enter'); void el.offsetWidth; el.classList.add('enter');
    clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove('enter'), 1500);
  }
  const RENDER = { today: renderToday, snap: renderSnap, streaks: renderStreaks, plan: renderPlan };
  function renderAll(enterTab) { for (const [k, f] of Object.entries(RENDER)) f(enterTab === k); moveIndicator(); }
  function moveIndicator() {
    const tab = document.querySelector(`.tab[data-tab="${S.tab}"]`), ind = $('#indicator'); if (!tab || !ind) return;
    const bar = tab.parentElement.getBoundingClientRect(), r = tab.getBoundingClientRect(), w = Math.min(r.width - 8, 70);
    ind.style.width = w + 'px'; ind.style.transform = `translateX(${r.left - bar.left - 8 + (r.width - w) / 2}px)`;
  }
  function show(tab) {
    if (tab === S.tab) return;
    const update = () => {
      S.tab = tab;
      document.querySelectorAll('.tab').forEach((t) => t.setAttribute('aria-selected', String(t.dataset.tab === tab)));
      document.querySelectorAll('.view').forEach((v) => { v.hidden = v.id !== 'v-' + tab; });
      $('#screen').scrollTop = 0; RENDER[tab](true); moveIndicator();
    };
    const focusHeading = () => { const h = document.querySelector(`#v-${tab} h1`); if (h) h.focus({ preventScroll: true }); };
    if (!document.startViewTransition || reduce) { update(); focusHeading(); return; }
    document.startViewTransition(update).finished.finally(focusHeading);
  }

  // ---------- events ----------
  document.addEventListener('click', async (e) => {
    const el = e.target.closest('[data-close],[data-ask],[data-day],[data-metric],[data-tab],[data-tab-go],[data-step],[data-snapmode],[data-cal],[data-calday],[data-progress],[data-delmeal],[data-delprogress],[data-act]');
    if (!el) return;
    const ds = el.dataset;
    if ('close' in ds) return closeSheet();
    if (ds.ask) { if ($('#chat-log')) ask(ds.ask); else openChat(ds.ask); return; }
    if (ds.day) { S.sel = ds.day; return renderToday(false); }
    if (ds.metric) return openDetail(ds.metric);
    if (ds.tab) return show(ds.tab);
    if (ds.tabGo) return show(ds.tabGo);
    if (ds.step) {
      const k = ds.step, cur = S.targets[k] ?? (k === 'kcal' ? 2000 : k === 'proteinG' ? 100 : 0);
      const next = Math.max(STEP[k], Math.round((cur + STEP[k] * Number(ds.dir)) * 100) / 100);
      setTargets({ ...S.targets, [k]: next }); return renderAll();
    }
    if (ds.snapmode) { S.snapMode = ds.snapmode; return renderSnap(true); }
    if (ds.cal) { const [y, m] = S.calMonth; const d = new Date(Date.UTC(y, m + Number(ds.cal), 1)); S.calMonth = [d.getUTCFullYear(), d.getUTCMonth()]; return renderSnap(); }
    if (ds.calday) return openDay(ds.calday);
    if (ds.progress) {
      const p = S.progress.find((x) => x.id === ds.progress); if (!p) return;
      return openSheet(new Date(p.date).toLocaleDateString('en-AU', { weekday: 'long', day: 'numeric', month: 'long' }), `<img src="${p.img}" alt="Progress photo" style="width:100%;border-radius:18px"><button class="btn danger" data-delprogress="${p.id}">Delete photo</button>`);
    }
    if (ds.delmeal) { S.meals = S.meals.filter((x) => x.id !== ds.delmeal); await store.del('meals', ds.delmeal); closeSheet(); return renderSnap(); }
    if (ds.delprogress) { S.progress = S.progress.filter((x) => x.id !== ds.delprogress); await store.del('progress', ds.delprogress); closeSheet(); return renderSnap(); }
    switch (ds.act) {
      case 'data': return openData();
      case 'ask': return openChat();
      case 'name': return openSheet('Your name', `<label class="lab" for="name-in">What should BE call you?</label><input class="text-in boxed" id="name-in" value="${esc(S.name)}" maxlength="30" autocomplete="given-name"><p class="note">Kept in this browser only. Apple Health doesn't share names with apps.</p><button class="btn ink" data-act="save-name">Save</button>`);
      case 'save-name': { S.name = ($('#name-in').value || '').trim().slice(0, 30); local.set('be.name', S.name); closeSheet(); return renderToday(false); }
      case 'cancel-import': if (job) job.cancel(); return closeSheet();
      case 'forget': return openSheet('Delete imported data?', '<p class="p">This removes the daily totals BE saved in this browser. Your Apple Health data and the export file are not affected. Meals and progress photos are kept.</p><button class="btn danger" data-act="forget-yes">Delete imported data</button><button class="btn glass" data-close>Keep it</button>');
      case 'forget-yes': await store.del('kv', 'data'); await store.del('kv', 'meta'); S.data = null; S.meta = null; S.chat = []; closeSheet(); renderAll('today'); return toast('check', 'var(--good)', 'Imported data deleted', 'Import again any time');
      case 'reset-targets': local.set('be.targets', null); ensureTargets(); renderAll(); return toast('check', 'var(--good)', 'Targets reset', 'Recommended from your 90-day history');
      case 'manual': return openReview({ name: 'Meal', items: [{ name: '', grams: 0, kcal: 0, protein: 0, carbs: 0, fat: 0, confidence: 1 }] }, false, '');
      case 'add-item': if (review) { review.items.push({ name: '', grams: 0, kcal: 0, protein: 0, carbs: 0, fat: 0, confidence: 1 }); openReview(review, review.fromPhoto, ''); } return;
      case 'save-meal': return saveMeal();
    }
  });
  document.addEventListener('change', (e) => { if (e.target.matches('#file-in, #file-in2, #file-in3')) { const f = e.target.files[0]; e.target.value = ''; if (f) startImport(f); } });
  document.addEventListener('input', (e) => {
    if (!review) return;
    if (e.target.id === 'meal-name') { review.name = e.target.value; return; }
    const i = e.target.dataset.i, f = e.target.dataset.f; if (i === undefined) return;
    review.items[i][f] = f === 'name' ? e.target.value : Number(e.target.value) || 0;
    const sum = (k) => review.items.reduce((a, x) => a + (+x[k] || 0), 0);
    document.querySelectorAll('[data-tot]').forEach((b) => { b.textContent = fmt(sum(b.dataset.tot)); });
  });
  document.addEventListener('keydown', (e) => { if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('[role="button"]:not(button)')) { e.preventDefault(); e.target.click(); } });
  addEventListener('resize', moveIndicator);
  // Dropping a file anywhere on the page starts an import.
  addEventListener('dragover', (e) => { if (e.dataTransfer && [...e.dataTransfer.types].includes('Files')) e.preventDefault(); });
  addEventListener('drop', (e) => { const f = e.dataTransfer && e.dataTransfer.files[0]; if (f && /\.(zip|xml)$/i.test(f.name)) { e.preventDefault(); startImport(f); } });

  // ---------- boot ----------
  (async () => {
    // Wait briefly for saved data so the import screen doesn't flash before the dashboard.
    const loaded = Promise.all([store.get('kv', 'data'), store.get('kv', 'meta'), store.all('meals'), store.all('progress')]);
    const res = await Promise.race([loaded, new Promise((r) => setTimeout(() => r(null), 800))]);
    const apply = ([data, meta, meals, progress]) => {
      S.meals = meals || []; S.progress = progress || [];
      if (data && data.lastDataDay) { S.data = data; S.meta = meta; S.sel = data.lastDataDay; }
    };
    if (res) apply(res);
    ensureTargets();
    renderAll('today');
    requestAnimationFrame(moveIndicator);
    if (!reduce) requestAnimationFrame(drawEcg);
    if (!res) { apply(await loaded); ensureTargets(); renderAll(S.data ? 'today' : null); }
  })();
})();
