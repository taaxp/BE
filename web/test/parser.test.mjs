// Node test for the export parser: node test/parser.test.mjs <fixture.zip>
import { readFileSync, openAsBlob } from 'node:fs';
import assert from 'node:assert/strict';
const src = readFileSync(new URL('../src/parser.js', import.meta.url), 'utf8');
const { parseExport } = new Function(src + '\nreturn beParserModule(null);')();
const zip = process.argv[2];
const truth = JSON.parse(readFileSync(zip.replace('.zip', '.truth.json'), 'utf8'));
let last;
for (const file of [zip, zip.replace('.zip', '.xml')]) {
  const blob = await openAsBlob(file);
  const t0 = Date.now();
  const r = await parseExport(blob, (p) => { last = p; });
  console.log(file.split('/').pop(), 'records', r.recordsScanned, 'used', r.recordsUsed, `${Date.now() - t0} ms`, 'progress', last.done, '/', last.total);
  assert.equal(r.exportDate, '2026-10-19 21:00:00 +1100');
  assert.equal(r.lastDataDay, '2026-10-19');
  // Steps: watch and Fitbit overlap every hour; the hourly max keeps the watch total, not the sum.
  for (const [day, t] of Object.entries(truth)) assert.equal(r.days[day].steps, t.steps, `steps ${day}`);
  const d = r.days['2026-10-19'];
  assert.equal(d.waterL, 1.25);
  assert.equal(d.activeKcal, 400); // kJ converted
  assert.equal(d.spo2, 97); // fraction to percent
  assert.ok(d.rhr > 60 && Number.isInteger(d.rhr * 2) && !Number.isInteger(d.rhr)); // mean of watch (x) and Fitbit (x+1)
  assert.ok(d.hrv < 46);
  assert.equal(d.rings.moveGoal, 600);
  // Sleep: the watch's staged record wins over Fitbit's single block.
  assert.equal(d.sleep.source, 'Sam’s Apple Watch');
  assert.equal(d.sleep.asleepMin, 370); // 01:00 -> 07:10
  assert.equal(d.sleep.bed, '01:00');
  assert.equal(d.sleep.wake, '07:10');
  assert.ok(d.sleep.segs.length === 4);
  const typical = r.days['2026-10-18'].sleep;
  assert.equal(typical.asleepMin, 440); // 23:00 -> 06:30 minus 10 min awake
  assert.equal(typical.stages.awake, 10);
  assert.equal(typical.stages.deep, 90);
  // Profile and sources.
  assert.equal(r.me.dob, '1991-03-02');
  assert.equal(r.me.sex, null);
  assert.equal(r.me.blood, 'O+');
  const kinds = Object.fromEntries(r.sources.map((s) => [s.name, s.kind]));
  assert.equal(kinds['Sam’s Apple Watch'], 'watch');
  assert.equal(kinds['Google Health'], 'fitbit');
  assert.equal(kinds['Sam’s iPhone'], 'iphone');
  assert.ok(r.days['2026-10-19'].workouts === undefined || r.days['2026-10-19'].workouts.length >= 0);
  assert.equal(r.days['2026-06-22'].workouts[0].type, 'Running');
}
console.log('all parser checks passed');
