// BE analytics: everything shown on screen is computed here from the parsed export.
// Ported from the Swift BECore package (MetricsEngine, CoachLibrary, Thresholds, Greeting,
// PlanRecommender) so the web and iPhone versions reason the same way.

function beAnalyticsModule() {
  const DAY = 86400000;
  const addDays = (k, n) => new Date(Date.parse(k + 'T00:00:00Z') + n * DAY).toISOString().slice(0, 10);
  const range = (from, to) => { const out = []; for (let k = from; k <= to; k = addDays(k, 1)) out.push(k); return out; };
  const clamp = (x) => Math.max(0, Math.min(1, x));

  // Metric catalogue: how to read each value from a day record, and how to judge it.
  const METRICS = {
    steps: { name: 'Steps', unit: 'steps', d: 0, better: 'up', get: (d) => d.steps },
    distanceKm: { name: 'Distance', unit: 'km', d: 1, better: 'up', get: (d) => d.distanceKm },
    exerciseMin: { name: 'Exercise', unit: 'min', d: 0, better: 'up', get: (d) => d.exerciseMin },
    activeKcal: { name: 'Active energy', unit: 'kcal', d: 0, better: 'up', get: (d) => d.activeKcal },
    rhr: { name: 'Resting heart rate', unit: 'bpm', d: 0, better: 'down', get: (d) => d.rhr },
    hrv: { name: 'Heart rate variability', short: 'HRV', unit: 'ms', d: 0, better: 'up', get: (d) => d.hrv },
    spo2: { name: 'Blood oxygen', unit: '%', d: 0, better: 'up', get: (d) => d.spo2 },
    resp: { name: 'Respiratory rate', unit: 'br/min', d: 1, better: 'down', get: (d) => d.resp },
    vo2: { name: 'Cardio fitness', unit: 'VO₂ max', d: 1, better: 'up', get: (d) => d.vo2, carry: true },
    weightKg: { name: 'Weight', unit: 'kg', d: 1, better: 'range', get: (d) => d.weightKg, carry: true },
    sleepH: { name: 'Sleep', unit: 'h', d: 1, better: 'up', get: (d) => (d.sleep ? d.sleep.asleepMin / 60 : undefined) },
    waterL: { name: 'Water', unit: 'L', d: 2, better: 'up', get: (d) => d.waterL },
    kcal: { name: 'Calories eaten', unit: 'kcal', d: 0, better: 'range', get: (d) => d.kcal },
    proteinG: { name: 'Protein', unit: 'g', d: 0, better: 'up', get: (d) => d.proteinG },
    carbsG: { name: 'Carbs', unit: 'g', d: 0, better: 'range', get: (d) => d.carbsG },
    fatG: { name: 'Fat', unit: 'g', d: 0, better: 'range', get: (d) => d.fatG },
    mindfulMin: { name: 'Mindful minutes', unit: 'min', d: 0, better: 'up', get: (d) => d.mindfulMin },
    heightCm: { name: 'Height', unit: 'cm', d: 0, better: 'range', get: (d) => d.heightCm, carry: true },
  };

  function fmt(v, d = 0) {
    if (v == null || !isFinite(v)) return '–';
    return Number(v).toLocaleString('en-AU', { minimumFractionDigits: d, maximumFractionDigits: d });
  }

  function value(data, k, day) {
    const d = data.days[day];
    const v = d ? METRICS[k].get(d) : undefined;
    return v == null || !isFinite(v) ? null : v;
  }

  // Latest value on or before `day` (for weight and VO2 max, measured only now and then).
  function latest(data, k, day, maxBack = 60) {
    for (let i = 0; i <= maxBack; i++) { const kk = addDays(day, -i); const v = value(data, k, kk); if (v != null) return { v, day: kk }; }
    return null;
  }

  function series(data, k, toDay, n) {
    return range(addDays(toDay, -(n - 1)), toDay).map((day) => ({ day, v: value(data, k, day) }));
  }

  // Your normal: the 90 days before `day`, excluding it, like MetricsEngine.baseline.
  function baseline(data, k, day, window = 90) {
    const xs = series(data, k, addDays(day, -1), window).map((p) => p.v).filter((v) => v != null);
    if (xs.length < 3) return null;
    const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
    const sd = Math.sqrt(xs.reduce((a, b) => a + (b - mean) ** 2, 0) / Math.max(1, xs.length - 1));
    return { mean, sd, n: xs.length, z: (v) => (xs.length >= 7 && sd > 0 ? (v - mean) / sd : null) };
  }

  function average(data, k, day, n = 7) {
    const xs = series(data, k, addDays(day, -1), n).map((p) => p.v).filter((v) => v != null);
    return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
  }

  // Least-squares slope over 14 days; steady when the change is under 3% of the mean.
  function trend(data, k, day, n = 14) {
    const pts = series(data, k, addDays(day, -1), n).map((p, i) => [i, p.v]).filter((p) => p[1] != null);
    if (pts.length < 5) return 'steady';
    const mx = pts.reduce((a, p) => a + p[0], 0) / pts.length, my = pts.reduce((a, p) => a + p[1], 0) / pts.length;
    let num = 0, den = 0;
    for (const [x, y] of pts) { num += (x - mx) * (y - my); den += (x - mx) ** 2; }
    if (!den || !my) return 'steady';
    const change = (num / den) * n;
    return Math.abs(change) < Math.abs(my) * 0.03 ? 'steady' : change > 0 ? 'rising' : 'falling';
  }

  // ---------- targets ----------
  function recommendTargets(data, day) {
    const t = {};
    const st = baseline(data, 'steps', day);
    t.steps = st ? Math.min(15000, Math.max(5000, Math.round((st.mean * 1.1) / 500) * 500)) : 8000;
    t.sleepH = 7.5;
    const ex = baseline(data, 'exerciseMin', day);
    t.exerciseMin = Math.max(30, Math.min(60, Math.round((ex ? ex.mean : 30) / 5) * 5));
    const w = baseline(data, 'waterL', day);
    t.waterL = w ? Math.min(3.5, Math.max(2, Math.round((w.mean + 0.25) * 4) / 4)) : 2;
    const kg = latest(data, 'weightKg', day, 120);
    if (kg && kg.v > 30 && kg.v < 300) t.proteinG = Math.round((kg.v * 1.2) / 5) * 5;
    return t;
  }
  const REASONS = {
    steps: (data, day) => { const b = baseline(data, 'steps', day); return b ? `Your 90-day average is ${fmt(b.mean)}. This is a 10% stretch.` : 'A common starting point until BE learns your normal.'; },
    sleepH: (data, day) => { const b = baseline(data, 'sleepH', day); return b ? `You average ${fmt(b.mean, 1)} h. Most adults need 7–9 h.` : 'Most adults need 7–9 hours.'; },
    exerciseMin: () => 'Australian guidelines suggest 150–300 minutes of moderate activity a week.',
    waterL: (data, day) => { const b = baseline(data, 'waterL', day); return b ? `You log about ${fmt(b.mean, 1)} L a day. A little more is easy.` : 'A simple daily baseline; more in heat or on training days.'; },
    proteinG: () => 'About 1.2 g per kg of body weight, a common target for active adults.',
  };

  function isMet(k, v, target) {
    if (v == null || target == null) return false;
    if (k === 'sleepH') return v >= target - 0.25 && v <= target + 1.5;
    if (k === 'kcal') return Math.abs(v - target) <= target * 0.1;
    return v >= target;
  }

  // ---------- safety and coach ----------
  function safety(k, v) {
    if (v == null) return null;
    if (k === 'rhr' && v > 100) return 'Your resting heart rate is above 100 bpm. If this keeps happening, or you feel dizzy, short of breath or have chest pain, talk to your GP. Call 000 in an emergency.';
    if (k === 'rhr' && v < 40) return 'Your resting heart rate is below 40 bpm. That can be normal for very fit people, but if you feel faint or tired, talk to your GP.';
    if (k === 'spo2' && v < 92) return 'Your blood oxygen reading is below 92%. Wrist readings can be off, so re-check while still. If it stays low or you feel short of breath, seek medical advice.';
    if (k === 'resp' && v > 25) return 'Your sleeping breathing rate is higher than typical. If you also feel unwell, talk to your GP.';
    return null;
  }

  function coach(data, k, day, targets) {
    const m = METRICS[k];
    const v = m.carry ? (latest(data, k, day) || {}).v ?? null : value(data, k, day);
    const b = baseline(data, k, day);
    const t = targets[k];
    const tr = trend(data, k, day);
    const z = v != null && b ? b.z(v) : null;
    const pos = z == null ? 'unknown' : z >= 1.5 ? 'high' : z <= -1.5 ? 'low' : 'normal';
    const usual = b ? `${fmt(b.mean, m.d)} ${m.unit}` : null;
    const note = (h, tone, mean, act) => ({ h, tone, mean, act, safety: safety(k, v) });
    if (v == null) {
      const act = ['hrv', 'spo2', 'resp'].includes(k) ? 'Wear your Apple Watch to sleep. These are measured overnight.'
        : ['waterL', 'kcal', 'proteinG', 'carbsG', 'fatG'].includes(k) ? 'Log food and water in Apple Health or an app that writes to it.'
        : k === 'weightKg' ? 'Weigh in with a connected scale or log it in Apple Health.' : 'No reading for this day in your export.';
      return note(`No ${m.name.toLowerCase()} recorded`, 'neutral', `Your export has no ${m.name.toLowerCase()} for this day.`, act);
    }
    let n;
    switch (k) {
      case 'rhr':
        n = pos === 'high' ? note('Higher than your usual', 'attention', `${fmt(v - b.mean)} bpm above your normal of ${usual}. Short-term rises often follow poor sleep, alcohol, stress, illness or a hard session.`, 'Keep training easy, drink water and get to bed earlier. If it stays up for a week, talk to your GP.')
          : pos === 'low' ? note('Lower than your usual', 'positive', 'A lower resting heart rate usually means you are well recovered or getting fitter.', 'A good day to train if you feel good.')
          : note('In your normal range', 'neutral', `A simple read on recovery and fitness.${usual ? ` Your usual is ${usual}.` : ''}`, tr === 'falling' ? 'It is trending down. Keep up the consistency.' : 'Regular cardio and good sleep bring it down over time.');
        break;
      case 'hrv':
        n = pos === 'low' ? note('Lower than your usual', 'attention', `${fmt(v)} ms against your normal of ${usual}. HRV dips under strain: hard training, poor sleep, stress, alcohol or illness.`, 'Go lighter: a walk, mobility or rest. Prioritise sleep tonight.')
          : pos === 'high' ? note('Higher than your usual', 'positive', 'Higher HRV than your norm usually signals good recovery.', 'Your body is ready. A good day for a harder session.')
          : note('In your normal range', 'neutral', `HRV is very personal, so compare it only with your own trend.${usual ? ` Your usual is ${usual}.` : ''}`, 'Keep sleep and training consistent and watch the 7-day trend.');
        break;
      case 'spo2':
        n = v >= 95 ? note('Looks normal', 'positive', 'Most healthy people read 95–100%.', 'Nothing to do.') : note('A little low', 'attention', 'Wrist readings can drop with movement, cold hands or a loose band.', 'Re-check while sitting still with the watch snug.');
        break;
      case 'resp':
        n = note(pos === 'high' ? 'Higher than your usual' : 'In your normal range', pos === 'high' ? 'attention' : 'neutral', 'Breaths per minute while you sleep. It often rises a little when you are run down.', pos === 'high' ? 'Take it easy and keep an eye on how you feel.' : 'Nothing to do.');
        break;
      case 'vo2':
        n = note(tr === 'rising' ? 'Improving' : tr === 'falling' ? 'Slipping a little' : 'Holding steady', tr === 'rising' ? 'positive' : 'neutral', 'VO₂ max estimates how well your body uses oxygen during exercise, one of the strongest markers of long-term health.', 'Brisk walks, runs or rides where you are breathing hard for 20+ minutes push it up.');
        break;
      case 'weightKg': {
        const w30 = latest(data, 'weightKg', addDays(day, -30), 30);
        const ch = w30 ? v - w30.v : null;
        n = note(ch == null ? `Latest: ${fmt(v, 1)} kg` : Math.abs(ch) < 0.5 ? 'Steady' : ch < 0 ? `Down ${fmt(-ch, 1)} kg in 30 days` : `Up ${fmt(ch, 1)} kg in 30 days`, 'neutral', 'Day-to-day changes are mostly water. The 30-day trend is what matters.', 'Weigh in at the same time each morning for a clearer trend.');
        break;
      }
      case 'sleepH': {
        const tt = t || 7.5;
        n = v < tt - 1 ? note('Short night', 'attention', `${fmt(tt - v, 1)} h under your ${fmt(tt, 1)} h target. Short sleep affects mood, appetite and recovery.`, 'Aim for a consistent bedtime tonight and keep caffeine before midday.')
          : note('Well rested', 'positive', `Close to your ${fmt(tt, 1)} h target.`, 'Keep a consistent wake time, including weekends.');
        break;
      }
      default: {
        if (t == null) { n = note(`${fmt(v, m.d)} ${m.unit}`, 'neutral', usual ? `Your usual is ${usual}.` : 'BE is still learning your normal.', 'Add a target in Plan to track this.'); break; }
        if (isMet(k, v, t)) { n = note('Target hit', 'positive', `${fmt(v, m.d)} of ${fmt(t, m.d)} ${m.unit}.`, 'Nice work.'); break; }
        const rem = Math.max(0, t - v);
        const act = { steps: `${fmt(rem)} short of target, about ${Math.round(rem / 110)} minutes of walking.`, waterL: `${fmt(rem, 2)} L short of target.`, proteinG: `${fmt(rem)} g short. Eggs, Greek yoghurt, tuna or tofu help.`, exerciseMin: `${fmt(rem)} min short. A brisk walk counts.`, kcal: v > t ? 'Over target. Look at the weekly picture rather than one day.' : 'Log meals as you go so the day adds up.' }[k] || `${fmt(rem, m.d)} ${m.unit} short of target.`;
        n = note(`${Math.round(clamp(v / t) * 100)}% of target`, 'neutral', `${fmt(v, m.d)} of ${fmt(t, m.d)} ${m.unit}.`, act);
      }
    }
    if (n.safety) n.tone = 'attention';
    return n;
  }

  // ---------- BE score and greeting (BECore Greeting) ----------
  function score(data, day, targets) {
    const v = (k) => value(data, k, day);
    const rec = [];
    rec.push(v('sleepH') == null ? 0.5 : clamp(v('sleepH') / (targets.sleepH || 7.5)));
    const br = baseline(data, 'rhr', day), bh = baseline(data, 'hrv', day);
    if (v('rhr') != null && br) rec.push(clamp(1 - Math.max(0, v('rhr') - br.mean) / 10));
    if (v('hrv') != null && bh && bh.mean > 0) rec.push(clamp(v('hrv') / bh.mean));
    const act = [['steps', 8000], ['exerciseMin', 30], ['waterL', 2]].map(([k, f]) => (v(k) == null ? 0.5 : clamp(v(k) / (targets[k] || f))));
    const recovery = rec.reduce((a, b) => a + b, 0) / rec.length, activity = act.reduce((a, b) => a + b, 0) / act.length;
    return { score: Math.round(100 * (0.55 * recovery + 0.45 * activity)), recovery, activity };
  }

  function flags(data, day, targets) {
    const out = [], v = (k) => value(data, k, day);
    if (v('sleepH') != null && v('sleepH') < (targets.sleepH || 7.5) - 1) out.push('a short night');
    const br = baseline(data, 'rhr', day); const zr = v('rhr') != null && br ? br.z(v('rhr')) : null;
    if (zr != null && zr >= 1.5) out.push(`resting heart rate up ${fmt(v('rhr') - br.mean)} bpm`);
    const bh = baseline(data, 'hrv', day); const zh = v('hrv') != null && bh ? bh.z(v('hrv')) : null;
    if (zh != null && zh <= -1.5) out.push('HRV below your usual');
    return out;
  }

  function greeting(data, day, targets, name, isLatest, hour) {
    const { score: sc, recovery, activity } = score(data, day, targets);
    const fl = flags(data, day, targets);
    const list = (a) => (a.length > 1 ? a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1] : a[0] || '');
    const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
    const dayName = new Date(day + 'T12:00:00Z').toLocaleDateString('en-AU', { weekday: 'long', timeZone: 'UTC' });
    const base = isLatest ? (hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening') : dayName;
    const hello = isLatest && name ? `${base}, ${name}` : base;
    let line, why;
    if (fl.length >= 2 || recovery < 0.75) { line = isLatest ? 'easy does it' : 'was a recovery day'; why = `${fl.length ? cap(list(fl)) + '.' : 'Recovery was lower than usual.'} Keep training light, drink water and aim for an early night.`; }
    else if (sc >= 85) { line = isLatest ? "you're flying" : 'was a cracker'; why = 'Recovered and moving well.'; }
    else if (recovery >= 0.9) { line = isLatest ? "you're ready to go" : 'was well recovered'; why = 'Recovery looks strong. A good day for a harder session.'; }
    else { line = isLatest ? 'steady as she goes' : 'was a steady day'; why = fl.length ? `${cap(list(fl))}, otherwise on track.` : 'On track. Keep chipping away at your targets.'; }
    return { hello, line, score: sc, recovery, activity, why };
  }

  // ---------- sleep score ----------
  // 60% duration against target (full marks at target, zero at 2.5 h short), 25% deep + REM share
  // (full marks at 45%), 15% efficiency (asleep / in bed, full marks at 95%).
  function sleepScore(sleep, targetH) {
    if (!sleep) return null;
    const t = (targetH || 7.5) * 60;
    const dur = clamp(1 - Math.max(0, t - sleep.asleepMin) / 150);
    const restorative = sleep.staged ? clamp((sleep.stages.deep + sleep.stages.rem) / sleep.asleepMin / 0.45) : null;
    const eff = clamp(sleep.asleepMin / Math.max(sleep.inBedMin, sleep.asleepMin) / 0.95);
    const s = restorative == null ? Math.round(100 * (0.8 * dur + 0.2 * eff)) : Math.round(60 * dur + 25 * restorative + 15 * eff);
    return { score: s, label: s >= 85 ? 'Excellent' : s >= 70 ? 'Good' : s >= 55 ? 'Fair' : 'Poor', efficiency: Math.round((sleep.asleepMin / Math.max(1, sleep.inBedMin)) * 100) };
  }

  // ---------- streaks and badges, from real history ----------
  const GOALS = {
    steps: { name: 'Step target', test: (data, d, t) => isMet('steps', value(data, 'steps', d), t.steps) },
    exerciseMin: { name: 'Exercise target', test: (data, d, t) => isMet('exerciseMin', value(data, 'exerciseMin', d), t.exerciseMin) },
    sleepH: { name: 'Sleep target', test: (data, d, t) => isMet('sleepH', value(data, 'sleepH', d), t.sleepH) },
    waterL: { name: 'Water target', test: (data, d, t) => isMet('waterL', value(data, 'waterL', d), t.waterL) },
    rings: { name: 'All rings closed', test: (data, d) => { const r = data.days[d] && data.days[d].rings; return !!(r && r.moveGoal && r.move >= r.moveGoal && r.exGoal && r.ex >= r.exGoal && r.standGoal && r.stand >= r.standGoal); } },
  };
  function streaks(data, day, targets) {
    const first = data.firstDay;
    const out = {};
    for (const [k, g] of Object.entries(GOALS)) {
      let current = 0;
      for (let d = day; d >= first; d = addDays(d, -1)) { if (g.test(data, d, targets)) current++; else break; }
      let best = 0, run = 0;
      for (const d of range(first, day)) { if (g.test(data, d, targets)) { run++; best = Math.max(best, run); } else run = 0; }
      const last30 = range(addDays(day, -29), day);
      const hits = last30.filter((d) => g.test(data, d, targets)).length;
      const week = range(addDays(day, -6), day).map((d) => g.test(data, d, targets));
      out[k] = { name: g.name, current, best, hits30: hits, week };
    }
    return out;
  }
  function badges(data, day, targets, st) {
    const workouts30 = range(addDays(day, -29), day).reduce((a, d) => a + ((data.days[d] && data.days[d].workouts) || []).length, 0);
    return [
      { id: 'steps7', title: 'One week strong', detail: '7 days in a row on your step target', on: st.steps.best >= 7 },
      { id: 'steps30', title: 'Habit formed', detail: '30 days in a row on your step target', on: st.steps.best >= 30 },
      { id: 'rings7', title: 'Perfect week', detail: 'All rings closed 7 days in a row', on: st.rings.best >= 7 },
      { id: 'sleep5', title: 'Well rested', detail: 'Sleep target hit 5 nights in a row', on: st.sleepH.best >= 5 },
      { id: 'water14', title: 'Hydration hero', detail: 'Water target hit on 14 of the last 30 days', on: st.waterL.hits30 >= 14 },
      { id: 'work8', title: 'Regular mover', detail: '8 or more workouts in the last 30 days', on: workouts30 >= 8 },
    ];
  }

  // ---------- compact summary for the AI coach ----------
  function aiSummary(data, day, targets, name) {
    const keys = ['steps', 'exerciseMin', 'activeKcal', 'rhr', 'hrv', 'spo2', 'resp', 'vo2', 'weightKg', 'sleepH', 'waterL', 'kcal', 'proteinG'];
    const metrics = {};
    for (const k of keys) {
      const m = METRICS[k];
      const v = m.carry ? (latest(data, k, day) || {}).v ?? null : value(data, k, day);
      const b = baseline(data, k, day), a7 = average(data, k, day);
      if (v == null && !b) continue;
      const r = (x) => (x == null ? null : Math.round(x * 10) / 10);
      metrics[k] = { label: m.name, unit: m.unit, day: r(v), avg7: r(a7), normal90: b ? r(b.mean) : null, trend: trend(data, k, day), target: targets[k] ?? null };
    }
    const sl = data.days[day] && data.days[day].sleep;
    const age = data.me && data.me.dob ? Math.floor((Date.parse(day) - Date.parse(data.me.dob)) / (365.25 * DAY)) : null;
    const st = streaks(data, day, targets);
    return {
      date: day, name: name || null,
      profile: { age, sex: data.me ? data.me.sex : null, heightCm: (latest(data, 'heightCm', day, 3650) || {}).v ?? null },
      metrics,
      sleep: sl ? { asleepMin: sl.asleepMin, inBedMin: sl.inBedMin, bed: sl.bed, wake: sl.wake, stages: sl.stages, score: (sleepScore(sl, targets.sleepH) || {}).score } : null,
      beScore: score(data, day, targets).score,
      streaks: Object.fromEntries(Object.entries(st).map(([k, s]) => [k, { current: s.current, best: s.best, hitsLast30: s.hits30 }])),
      workoutsLast7: range(addDays(day, -6), day).flatMap((d) => (data.days[d] && data.days[d].workouts) || []),
      sources: data.sources.slice(0, 6).map((s) => s.name),
    };
  }

  return { METRICS, fmt, addDays, range, value, latest, series, baseline, average, trend, recommendTargets, REASONS, isMet, coach, score, greeting, sleepScore, streaks, badges, aiSummary, safety };
}
