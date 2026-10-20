// Apple Health export parser. Runs inside a Web Worker (see app.js), or in Node for tests.
//
// Input: the export.zip from Health → profile → Export All Health Data, or the export.xml inside it.
// Output: compact daily aggregates. Raw records never leave this function.
//
// The whole file is streamed: the zip is read through its central directory with Blob.slice,
// the export.xml entry is inflated with DecompressionStream('deflate-raw'), and the XML is scanned
// chunk by chunk. Nothing is uploaded anywhere.

/* eslint-disable no-restricted-globals */
function beParserModule(scope) {
  const DAY_MS = 86400000;
  const KEEP_DAYS = 400; // daily history kept, counted back from the export date
  const STAGE_NIGHTS = 21; // nights kept with full stage segments for the hypnogram

  // Cumulative types: deduplicated by keeping, for each hour, the largest total from any one source.
  // This mirrors what Apple Health shows when an Apple Watch and a Fitbit both record steps.
  const SUM = {
    HKQuantityTypeIdentifierStepCount: 'steps',
    HKQuantityTypeIdentifierDistanceWalkingRunning: 'distanceKm',
    HKQuantityTypeIdentifierFlightsClimbed: 'flights',
    HKQuantityTypeIdentifierActiveEnergyBurned: 'activeKcal',
    HKQuantityTypeIdentifierAppleExerciseTime: 'exerciseMin',
    HKQuantityTypeIdentifierDietaryWater: 'waterL',
    HKQuantityTypeIdentifierDietaryEnergyConsumed: 'kcal',
    HKQuantityTypeIdentifierDietaryProtein: 'proteinG',
    HKQuantityTypeIdentifierDietaryCarbohydrates: 'carbsG',
    HKQuantityTypeIdentifierDietaryFatTotal: 'fatG',
  };
  // Discrete types: daily mean of all readings.
  const MEAN = {
    HKQuantityTypeIdentifierRestingHeartRate: 'rhr',
    HKQuantityTypeIdentifierHeartRateVariabilitySDNN: 'hrv',
    HKQuantityTypeIdentifierOxygenSaturation: 'spo2',
    HKQuantityTypeIdentifierRespiratoryRate: 'resp',
    HKQuantityTypeIdentifierWalkingHeartRateAverage: 'walkHr',
    HKQuantityTypeIdentifierAppleSleepingWristTemperature: 'wristTemp',
  };
  // Last reading of the day.
  const LAST = {
    HKQuantityTypeIdentifierVO2Max: 'vo2',
    HKQuantityTypeIdentifierBodyMass: 'weightKg',
    HKQuantityTypeIdentifierBodyFatPercentage: 'bodyFat',
    HKQuantityTypeIdentifierHeight: 'heightCm',
  };
  const HR = 'HKQuantityTypeIdentifierHeartRate';
  const SLEEP = 'HKCategoryTypeIdentifierSleepAnalysis';
  const MINDFUL = 'HKCategoryTypeIdentifierMindfulSession';
  const EVENTS = {
    HKCategoryTypeIdentifierHighHeartRateEvent: 'highHr',
    HKCategoryTypeIdentifierLowHeartRateEvent: 'lowHr',
    HKCategoryTypeIdentifierIrregularHeartRhythmEvent: 'irregular',
  };
  const STAGE = {
    HKCategoryValueSleepAnalysisAsleepCore: 'core',
    HKCategoryValueSleepAnalysisAsleepDeep: 'deep',
    HKCategoryValueSleepAnalysisAsleepREM: 'rem',
    HKCategoryValueSleepAnalysisAsleepUnspecified: 'asleep',
    HKCategoryValueSleepAnalysisAsleep: 'asleep',
    HKCategoryValueSleepAnalysisAwake: 'awake',
    HKCategoryValueSleepAnalysisInBed: 'inbed',
  };

  // ---------- unit conversion ----------
  function convert(key, v, unit) {
    switch (key) {
      case 'distanceKm': return unit === 'mi' ? v * 1.609344 : unit === 'm' ? v / 1000 : v;
      case 'activeKcal': case 'kcal': return unit === 'kJ' ? v / 4.184 : v; // 'kcal' and 'Cal' are the same
      case 'waterL': return unit === 'mL' ? v / 1000 : unit === 'fl_oz_us' ? v * 0.0295735 : unit === 'fl_oz_imp' ? v * 0.0284131 : v;
      case 'proteinG': case 'carbsG': case 'fatG': return unit === 'mg' ? v / 1000 : unit === 'oz' ? v * 28.3495 : v;
      case 'spo2': case 'bodyFat': return v <= 1 ? v * 100 : v; // stored as a fraction
      case 'weightKg': return unit === 'lb' ? v * 0.45359237 : unit === 'st' ? v * 6.35029 : unit === 'g' ? v / 1000 : v;
      case 'heightCm': return unit === 'm' ? v * 100 : unit === 'in' ? v * 2.54 : unit === 'ft' ? v * 30.48 : v;
      case 'wristTemp': return unit === 'degF' ? (v - 32) / 1.8 : v;
      default: return v;
    }
  }

  // ---------- dates ----------
  // Health dates look like "2026-10-19 07:20:00 +1100". The day key is the local calendar day as recorded.
  const dayOf = (s) => s.slice(0, 10);
  function epoch(s) { // milliseconds since 1970 (UTC instant)
    return Date.parse(`${s.slice(0, 10)}T${s.slice(11, 19)}${s.slice(20, 23)}:${s.slice(23, 25)}`);
  }
  function wallMs(s) { // the local wall-clock time, expressed as if it were UTC
    return Date.parse(`${s.slice(0, 10)}T${s.slice(11, 19)}Z`);
  }
  const keyFromWall = (ms) => new Date(ms).toISOString().slice(0, 10);
  const dayIndex = (k) => Math.round(Date.parse(k + 'T00:00:00Z') / DAY_MS);

  // ---------- attribute reading ----------
  function attr(tag, name) {
    const i = tag.indexOf(' ' + name + '="');
    if (i < 0) return null;
    const s = i + name.length + 3;
    return tag.slice(s, tag.indexOf('"', s));
  }
  const unescapeXml = (s) => s.replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

  // ---------- zip reading ----------
  async function readBytes(blob, start, len) {
    return new Uint8Array(await blob.slice(start, start + len).arrayBuffer());
  }
  async function findXmlInZip(blob) {
    const size = blob.size;
    const tailLen = Math.min(size, 65557 + 20);
    const tail = await readBytes(blob, size - tailLen, tailLen);
    const dv = new DataView(tail.buffer);
    let eocd = -1;
    for (let i = tail.length - 22; i >= 0; i--) if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
    if (eocd < 0) throw new Error('This file is not a valid zip archive.');
    let cdCount = dv.getUint16(eocd + 10, true), cdSize = dv.getUint32(eocd + 12, true), cdOffset = dv.getUint32(eocd + 16, true);
    if (cdOffset === 0xffffffff || cdCount === 0xffff) { // Zip64
      const loc = eocd - 20;
      if (loc < 0 || dv.getUint32(loc, true) !== 0x07064b50) throw new Error('Unsupported zip format.');
      const z64At = Number(dv.getBigUint64(loc + 8, true));
      const z = new DataView((await readBytes(blob, z64At, 56)).buffer);
      cdCount = Number(z.getBigUint64(32, true)); cdSize = Number(z.getBigUint64(40, true)); cdOffset = Number(z.getBigUint64(48, true));
    }
    const cd = await readBytes(blob, cdOffset, cdSize);
    const c = new DataView(cd.buffer);
    const dec = new TextDecoder();
    const entries = [];
    for (let p = 0, n = 0; n < cdCount && p + 46 <= cd.length; n++) {
      if (c.getUint32(p, true) !== 0x02014b50) break;
      const method = c.getUint16(p + 10, true);
      let comp = c.getUint32(p + 20, true), uncomp = c.getUint32(p + 24, true);
      const nameLen = c.getUint16(p + 28, true), extraLen = c.getUint16(p + 30, true), commentLen = c.getUint16(p + 32, true);
      let local = c.getUint32(p + 42, true);
      const name = dec.decode(cd.subarray(p + 46, p + 46 + nameLen));
      // Zip64 extra field holds the real sizes and offset when the 32-bit ones are saturated.
      let e = p + 46 + nameLen; const eEnd = e + extraLen;
      while (e + 4 <= eEnd) {
        const id = c.getUint16(e, true), sz = c.getUint16(e + 2, true);
        if (id === 0x0001) {
          let q = e + 4;
          if (uncomp === 0xffffffff) { uncomp = Number(c.getBigUint64(q, true)); q += 8; }
          if (comp === 0xffffffff) { comp = Number(c.getBigUint64(q, true)); q += 8; }
          if (local === 0xffffffff) { local = Number(c.getBigUint64(q, true)); q += 8; }
        }
        e += 4 + sz;
      }
      entries.push({ name, method, comp, uncomp, local });
      p += 46 + nameLen + extraLen + commentLen;
    }
    const xmls = entries.filter((x) => /\.xml$/i.test(x.name) && !/cda/i.test(x.name));
    const entry = xmls.find((x) => /(^|\/)export\.xml$/i.test(x.name)) || xmls.sort((a, b) => b.uncomp - a.uncomp)[0];
    if (!entry) throw new Error('No export.xml found in this zip. Choose the export.zip from the Health app.');
    const lh = new DataView((await readBytes(blob, entry.local, 30)).buffer);
    if (lh.getUint32(0, true) !== 0x04034b50) throw new Error('The zip archive is damaged.');
    const dataStart = entry.local + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
    if (entry.method !== 0 && entry.method !== 8) throw new Error('Unsupported compression in this zip.');
    return { dataStart, comp: entry.comp, method: entry.method };
  }

  // ---------- main ----------
  async function parseExport(blob, onProgress) {
    const head = await readBytes(blob, 0, 4);
    const isZip = head[0] === 0x50 && head[1] === 0x4b && head[2] === 0x03 && head[3] === 0x04;
    // Progress counts input bytes (compressed bytes for a zip), measured before inflation.
    let consumed = 0;
    const counter = () => new TransformStream({ transform(chunk, ctl) { consumed += chunk.byteLength; ctl.enqueue(chunk); } });
    let byteStream, total;
    if (isZip) {
      const z = await findXmlInZip(blob);
      total = z.comp;
      byteStream = blob.slice(z.dataStart, z.dataStart + z.comp).stream().pipeThrough(counter());
      if (z.method === 8) {
        if (typeof DecompressionStream === 'undefined') throw new Error('This browser cannot unzip files. Unzip the export first and choose export.xml, or update your browser.');
        byteStream = byteStream.pipeThrough(new DecompressionStream('deflate-raw'));
      }
    } else {
      total = blob.size;
      byteStream = blob.stream().pipeThrough(counter());
    }

    const textStream = byteStream.pipeThrough(new TextDecoderStream());
    const reader = textStream.getReader();

    const st = {
      exportDate: null, cutoffDay: null, me: {}, records: 0, used: 0,
      hourly: new Map(), // key -> Map(hourKey -> Map(source -> value))
      mean: new Map(), // key -> Map(day -> [sum, n])
      last: new Map(), // key -> Map(day -> [epoch, value])
      hr: new Map(), // day -> [sum, n, min, max]
      mindful: new Map(), events: new Map(),
      nights: new Map(), // nightKey -> Map(source -> [[start,end,stage]])
      rings: new Map(), workouts: [], sources: new Map(),
      firstDay: null, lastDay: null,
    };

    let buf = '';
    let lastReport = 0;
    for (;;) {
      const { value, done } = await reader.read();
      if (value) buf += value;
      const cut = done ? buf.length : buf.lastIndexOf('>') + 1;
      if (cut > 0) {
        scan(buf.slice(0, cut), st);
        buf = buf.slice(cut);
      }
      const now = Date.now();
      if (onProgress && (now - lastReport > 200 || done)) {
        lastReport = now;
        onProgress({ phase: 'reading', done: consumed, total, records: st.records });
      }
      if (done) break;
    }
    if (onProgress) onProgress({ phase: 'building', done: total, total, records: st.records });
    return finish(st);
  }

  const TAG_RE = /<(Record|ActivitySummary|Workout|Me|ExportDate)\s([^>]*)>/g;
  function scan(text, st) {
    TAG_RE.lastIndex = 0;
    let m;
    while ((m = TAG_RE.exec(text))) {
      const kind = m[1], t = ' ' + m[2];
      if (kind === 'Record') { st.records++; record(t, st); }
      else if (kind === 'ActivitySummary') summary(t, st);
      else if (kind === 'Workout') workout(t, st);
      else if (kind === 'Me') me(t, st);
      else if (kind === 'ExportDate') {
        const v = attr(t, 'value');
        if (v) { st.exportDate = v; st.cutoffDay = keyFromWall(wallMs(v) - KEEP_DAYS * DAY_MS); }
      }
    }
  }

  function noteSource(st, t, type, day) {
    const name = unescapeXml(attr(t, 'sourceName') || 'Unknown');
    let s = st.sources.get(name);
    if (!s) {
      const dev = unescapeXml(attr(t, 'device') || '');
      const model = (dev.match(/model:([^,>]+)/) || [])[1] || '';
      const devName = (dev.match(/name:([^,>]+)/) || [])[1] || '';
      s = { name, model: model.trim(), device: devName.trim(), count: 0, first: day, last: day, types: new Map() };
      st.sources.set(name, s);
    }
    s.count++;
    if (day < s.first) s.first = day;
    if (day > s.last) s.last = day;
    s.types.set(type, (s.types.get(type) || 0) + 1);
    return name;
  }

  function record(t, st) {
    const type = attr(t, 'type');
    if (!type) return;
    const isSum = SUM[type], isMean = MEAN[type], isLast = LAST[type];
    if (!isSum && !isMean && !isLast && type !== HR && type !== SLEEP && type !== MINDFUL && !EVENTS[type]) return;
    const start = attr(t, 'startDate'), end = attr(t, 'endDate');
    if (!start || !end) return;
    const day = dayOf(start);
    if (st.cutoffDay && day < st.cutoffDay && type !== SLEEP) return;
    if (type === SLEEP && st.cutoffDay && dayOf(end) < st.cutoffDay) return;
    st.used++;
    if (!st.firstDay || day < st.firstDay) st.firstDay = day;
    if (!st.lastDay || day > st.lastDay) st.lastDay = day;
    const source = noteSource(st, t, type, day);
    const unit = attr(t, 'unit') || '';
    const raw = attr(t, 'value');

    if (isSum) {
      const v = convert(isSum, parseFloat(raw), unit);
      if (!isFinite(v)) return;
      const hourKey = start.slice(0, 13); // "YYYY-MM-DD HH"
      let byHour = st.hourly.get(isSum); if (!byHour) st.hourly.set(isSum, byHour = new Map());
      let bySrc = byHour.get(hourKey); if (!bySrc) byHour.set(hourKey, bySrc = new Map());
      bySrc.set(source, (bySrc.get(source) || 0) + v);
    } else if (isMean) {
      const v = convert(isMean, parseFloat(raw), unit);
      if (!isFinite(v)) return;
      let m = st.mean.get(isMean); if (!m) st.mean.set(isMean, m = new Map());
      const a = m.get(day) || [0, 0]; a[0] += v; a[1]++; m.set(day, a);
    } else if (isLast) {
      const v = convert(isLast, parseFloat(raw), unit);
      if (!isFinite(v)) return;
      let m = st.last.get(isLast); if (!m) st.last.set(isLast, m = new Map());
      const e = epoch(end), cur = m.get(day);
      if (!cur || e >= cur[0]) m.set(day, [e, v]);
    } else if (type === HR) {
      const v = parseFloat(raw);
      if (!isFinite(v)) return;
      const a = st.hr.get(day) || [0, 0, Infinity, -Infinity];
      a[0] += v; a[1]++; if (v < a[2]) a[2] = v; if (v > a[3]) a[3] = v;
      st.hr.set(day, a);
    } else if (type === SLEEP) {
      const stage = STAGE[raw];
      if (!stage) return;
      const s = epoch(start), e = epoch(end);
      if (!(e > s)) return;
      // A night runs 18:00 to 18:00 and belongs to the day you wake up.
      const night = keyFromWall(wallMs(end) + 6 * 3600000);
      let bySrc = st.nights.get(night); if (!bySrc) st.nights.set(night, bySrc = new Map());
      let list = bySrc.get(source); if (!list) bySrc.set(source, list = []);
      list.push([s, e, stage, wallMs(start) - s]); // keep the tz offset to show local clock times
    } else if (type === MINDFUL) {
      const mins = (epoch(end) - epoch(start)) / 60000;
      if (mins > 0) st.mindful.set(day, (st.mindful.get(day) || 0) + mins);
    } else if (EVENTS[type]) {
      const k = EVENTS[type];
      const a = st.events.get(day) || {}; a[k] = (a[k] || 0) + 1; st.events.set(day, a);
    }
  }

  function summary(t, st) {
    const day = attr(t, 'dateComponents');
    if (!day || (st.cutoffDay && day < st.cutoffDay)) return;
    const unit = attr(t, 'activeEnergyBurnedUnit') || 'kcal';
    const k = (n) => { const v = parseFloat(attr(t, n)); return isFinite(v) ? v : null; };
    const move = k('activeEnergyBurned'), moveGoal = k('activeEnergyBurnedGoal');
    st.rings.set(day, {
      move: move == null ? null : convert('activeKcal', move, unit), moveGoal: moveGoal == null ? null : convert('activeKcal', moveGoal, unit),
      ex: k('appleExerciseTime'), exGoal: k('appleExerciseTimeGoal'), stand: k('appleStandHours'), standGoal: k('appleStandHoursGoal'),
    });
  }

  function workout(t, st) {
    const start = attr(t, 'startDate');
    if (!start || (st.cutoffDay && dayOf(start) < st.cutoffDay)) return;
    const type = (attr(t, 'workoutActivityType') || '').replace('HKWorkoutActivityType', '');
    let mins = parseFloat(attr(t, 'duration'));
    const du = attr(t, 'durationUnit');
    if (du === 's') mins /= 60; else if (du === 'h') mins *= 60;
    st.workouts.push({ day: dayOf(start), type, mins: isFinite(mins) ? Math.round(mins) : null, source: unescapeXml(attr(t, 'sourceName') || '') });
  }

  function me(t, st) {
    const dob = attr(t, 'HKCharacteristicTypeIdentifierDateOfBirth');
    const sex = attr(t, 'HKCharacteristicTypeIdentifierBiologicalSex');
    const blood = attr(t, 'HKCharacteristicTypeIdentifierBloodType');
    const wheel = attr(t, 'HKCharacteristicTypeIdentifierWheelchairUse');
    st.me = {
      dob: dob || null,
      sex: sex && !/NotSet/.test(sex) ? sex.replace('HKBiologicalSex', '').toLowerCase() : null,
      blood: blood && !/NotSet/.test(blood) ? blood.replace('HKBloodType', '').replace('Positive', '+').replace('Negative', '−') : null,
      wheelchair: wheel && !/NotSet/.test(wheel) ? /Yes/.test(wheel) : null,
    };
  }

  // ---------- interval helpers ----------
  function unionMinutes(intervals) {
    if (!intervals.length) return 0;
    const s = intervals.slice().sort((a, b) => a[0] - b[0]);
    let total = 0, cs = s[0][0], ce = s[0][1];
    for (let i = 1; i < s.length; i++) {
      if (s[i][0] <= ce) { if (s[i][1] > ce) ce = s[i][1]; }
      else { total += ce - cs; cs = s[i][0]; ce = s[i][1]; }
    }
    return (total + ce - cs) / 60000;
  }

  function finishNight(bySrc) {
    // Use the one source that recorded the most detail for the night (stages beat plain "asleep").
    let best = null, bestScore = -1;
    for (const [src, list] of bySrc) {
      const staged = list.filter((x) => x[2] === 'core' || x[2] === 'deep' || x[2] === 'rem');
      const asleep = list.filter((x) => x[2] !== 'awake' && x[2] !== 'inbed');
      const score = unionMinutes(staged) * 2 + unionMinutes(asleep);
      if (score > bestScore) { bestScore = score; best = { src, list }; }
    }
    if (!best) return null;
    const L = best.list;
    const by = (k) => L.filter((x) => x[2] === k);
    const asleepIv = L.filter((x) => x[2] === 'core' || x[2] === 'deep' || x[2] === 'rem' || x[2] === 'asleep');
    const asleep = unionMinutes(asleepIv);
    if (asleep < 30) return null; // ignore stray naps shorter than half an hour
    const start = Math.min(...L.map((x) => x[0])), end = Math.max(...L.map((x) => x[1]));
    const offset = L[0][3];
    const stages = { core: unionMinutes(by('core')), deep: unionMinutes(by('deep')), rem: unionMinutes(by('rem')), awake: unionMinutes(by('awake')), unspecified: unionMinutes(by('asleep')) };
    const segs = L.filter((x) => x[2] !== 'inbed').sort((a, b) => a[0] - b[0])
      .map((x) => [Math.round((x[0] - start) / 60000), Math.round((x[1] - start) / 60000), x[2] === 'asleep' ? 'core' : x[2]]);
    return {
      source: best.src, asleepMin: Math.round(asleep), inBedMin: Math.round((end - start) / 60000),
      bed: new Date(start + offset).toISOString().slice(11, 16), wake: new Date(end + offset).toISOString().slice(11, 16),
      stages: Object.fromEntries(Object.entries(stages).map(([k, v]) => [k, Math.round(v)])), segs, staged: stages.core + stages.deep + stages.rem > 0,
    };
  }

  function finish(st) {
    const days = {};
    const put = (day, k, v) => { (days[day] ||= {})[k] = v; };
    for (const [key, byHour] of st.hourly) {
      const perDay = new Map();
      for (const [hourKey, bySrc] of byHour) {
        let max = 0; for (const v of bySrc.values()) if (v > max) max = v;
        const d = hourKey.slice(0, 10); perDay.set(d, (perDay.get(d) || 0) + max);
      }
      for (const [d, v] of perDay) put(d, key, key === 'distanceKm' || key === 'waterL' ? Math.round(v * 100) / 100 : Math.round(v));
    }
    for (const [key, m] of st.mean) for (const [d, a] of m) put(d, key, Math.round((a[0] / a[1]) * 10) / 10);
    for (const [key, m] of st.last) for (const [d, a] of m) put(d, key, Math.round(a[1] * 10) / 10);
    for (const [d, a] of st.hr) put(d, 'hr', { avg: Math.round(a[0] / a[1]), min: Math.round(a[2]), max: Math.round(a[3]) });
    for (const [d, v] of st.mindful) put(d, 'mindfulMin', Math.round(v));
    for (const [d, v] of st.events) put(d, 'events', v);
    for (const [d, r] of st.rings) put(d, 'rings', r);

    const nightKeys = [...st.nights.keys()].sort();
    const keepSegs = new Set(nightKeys.slice(-STAGE_NIGHTS));
    for (const k of nightKeys) {
      const n = finishNight(st.nights.get(k));
      if (!n) continue;
      if (!keepSegs.has(k)) delete n.segs;
      put(k, 'sleep', n);
    }
    const workouts = st.workouts.sort((a, b) => (a.day < b.day ? -1 : 1));
    for (const w of workouts) { const d = (days[w.day] ||= {}); (d.workouts ||= []).push({ type: w.type, mins: w.mins }); }

    const sortedDays = Object.keys(days).sort();
    const lastDataDay = sortedDays[sortedDays.length - 1] || null;
    const sources = [...st.sources.values()].sort((a, b) => b.count - a.count).map((s) => ({
      name: s.name, model: s.model, device: s.device, count: s.count, first: s.first, last: s.last,
      kind: /watch/i.test(s.model) || /watch/i.test(s.device) ? 'watch' : /fitbit|google/i.test(s.name) ? 'fitbit' : /iphone/i.test(s.model) ? 'iphone' : 'app',
      types: Object.fromEntries([...s.types.entries()].sort((a, b) => b[1] - a[1]).map(([t, n]) => [t.replace(/^HK(Quantity|Category)TypeIdentifier/, ''), n])),
    }));
    return {
      version: 1,
      exportDate: st.exportDate, lastDataDay, firstDay: sortedDays[0] || null,
      recordsScanned: st.records, recordsUsed: st.used, me: st.me, sources, days,
    };
  }

  // Worker wiring.
  if (scope && typeof scope.postMessage === 'function' && typeof scope.addEventListener === 'function') {
    scope.addEventListener('message', async (e) => {
      try {
        const result = await parseExport(e.data.file, (p) => scope.postMessage({ type: 'progress', ...p }));
        scope.postMessage({ type: 'done', result });
      } catch (err) {
        scope.postMessage({ type: 'error', message: err && err.message ? err.message : String(err) });
      }
    });
  }
  return { parseExport, unionMinutes, dayIndex };
}
