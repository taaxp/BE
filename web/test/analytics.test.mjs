// node test/analytics.test.mjs <fixture.zip>
import { readFileSync, openAsBlob } from 'node:fs';
import assert from 'node:assert/strict';
const load = (f, fn) => new Function(readFileSync(new URL(f, import.meta.url), 'utf8') + `\nreturn ${fn};`)();
const { parseExport } = load('../src/parser.js', 'beParserModule(null)');
const A = load('../src/analytics.js', 'beAnalyticsModule()');
const data = await parseExport(await openAsBlob(process.argv[2]));
const day = data.lastDataDay;
const t = A.recommendTargets(data, day);
console.log('targets', t);
assert.ok(t.steps >= 5000 && t.steps % 500 === 0);
assert.equal(t.sleepH, 7.5);
assert.equal(t.proteinG, 95); // 1.2 g/kg of ~77.8 kg, rounded to 5
// The fixture's last night is short and resting HR/HRV are off-baseline: coach must say so.
const rhr = A.coach(data, 'rhr', day, t), hrv = A.coach(data, 'hrv', day, t), sl = A.coach(data, 'sleepH', day, t);
console.log(rhr.h, '|', hrv.h, '|', sl.h);
assert.equal(rhr.h, 'Higher than your usual');
assert.equal(hrv.h, 'Lower than your usual');
assert.equal(sl.h, 'Short night');
const g = A.greeting(data, day, t, 'Sam', true, 8);
console.log(g);
assert.equal(g.hello, 'Good morning, Sam');
assert.equal(g.line, 'easy does it');
const prev = A.greeting(data, A.addDays(day, -1), t, 'Sam', false, 8);
assert.ok(prev.hello === 'Sunday' && prev.line.startsWith('was'));
const ss = A.sleepScore(data.days[day].sleep, 7.5), ssPrev = A.sleepScore(data.days[A.addDays(day, -1)].sleep, 7.5);
console.log('sleep score', ss, ssPrev);
assert.ok(ss.score < ssPrev.score);
const st = A.streaks(data, day, t);
console.log('streaks', Object.fromEntries(Object.entries(st).map(([k, v]) => [k, [v.current, v.best, v.hits30]])));
assert.equal(st.rings.current, 0); // exercise 22 of 30 every day in the fixture
assert.equal(st.waterL.best, 0); // 1.25 L vs a 2 L+ target
const sum = A.aiSummary(data, day, t, 'Sam');
assert.equal(sum.metrics.weightKg.day > 70, true);
assert.equal(sum.profile.age, 35);
assert.ok(JSON.stringify(sum).length < 6000);
// Weight is carried from the last weigh-in, not shown as missing.
assert.ok(A.coach(data, 'weightKg', day, t).h.length > 0);
assert.equal(A.coach(data, 'spo2', day, t).h, 'Looks normal');
console.log('all analytics checks passed; summary', JSON.stringify(sum).length, 'chars');
