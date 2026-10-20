"""Builds a synthetic Apple Health export (export.zip) for parser tests. Not real data."""
import random, zipfile, sys, datetime as dt
random.seed(4)
OUT = sys.argv[1]
TZ = "+1100"
end = dt.date(2026, 10, 19)
WATCH = 'sourceName="Sam&#8217;s Apple Watch" sourceVersion="11.0" device="&lt;&lt;HKDevice: 0x1&gt;, name:Apple Watch, manufacturer:Apple Inc., model:Watch, hardware:Watch7,1, software:11.0&gt;"'
FITBIT = 'sourceName="Google Health" sourceVersion="5.05"'
PHONE = 'sourceName="Sam&#8217;s iPhone" sourceVersion="26.0" device="&lt;&lt;HKDevice: 0x2&gt;, name:iPhone, manufacturer:Apple Inc., model:iPhone, hardware:iPhone17,1, software:26.0&gt;"'
lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<!DOCTYPE HealthData [ <!ELEMENT HealthData ANY> ]>', '<HealthData locale="en_AU">',
         f' <ExportDate value="2026-10-19 21:00:00 {TZ}"/>',
         ' <Me HKCharacteristicTypeIdentifierDateOfBirth="1991-03-02" HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexNotSet" HKCharacteristicTypeIdentifierBloodType="HKBloodTypeOPositive" HKCharacteristicTypeIdentifierFitzpatrickSkinType="HKFitzpatrickSkinTypeNotSet" HKCharacteristicTypeIdentifierCardioFitnessMedicationsUse="None"/>']
def ts(d, h, m=0):
    return f"{d.isoformat()} {h:02d}:{m:02d}:00 {TZ}"
def rec(t, src, unit, s, e, v, children=""):
    tag = f' <Record type="{t}" {src} unit="{unit}" creationDate="{e}" startDate="{s}" endDate="{e}" value="{v}"'
    lines.append(tag + (f">\n{children}\n </Record>" if children else "/>"))
truth = {}
for i in range(120):
    d = end - dt.timedelta(days=119 - i)
    tot_watch = 0
    for h in range(7, 22):
        w = random.randint(200, 900)
        tot_watch += w
        rec("HKQuantityTypeIdentifierStepCount", WATCH, "count", ts(d, h, 5), ts(d, h, 55), w)
        rec("HKQuantityTypeIdentifierStepCount", FITBIT, "count", ts(d, h, 0), ts(d, h, 59), int(w * 0.93))
    truth.setdefault(d.isoformat(), {})["steps"] = tot_watch
    rhr = 58 + random.randint(-2, 2) + (5 if i == 119 else 0)
    rec("HKQuantityTypeIdentifierRestingHeartRate", WATCH, "count/min", ts(d, 6), ts(d, 6), rhr)
    rec("HKQuantityTypeIdentifierRestingHeartRate", FITBIT, "count/min", ts(d, 6), ts(d, 6), rhr + 1)
    rec("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", WATCH, "ms", ts(d, 3), ts(d, 3, 1), 46 + random.randint(-3, 3) - (6 if i == 119 else 0),
        '  <HeartRateVariabilityMetadataList>\n   <InstantaneousBeatsPerMinute bpm="62" time="3:00:01.00 am"/>\n  </HeartRateVariabilityMetadataList>')
    rec("HKQuantityTypeIdentifierOxygenSaturation", WATCH, "%", ts(d, 2), ts(d, 2), 0.97)
    for h in (9, 13, 18):
        rec("HKQuantityTypeIdentifierHeartRate", WATCH, "count/min", ts(d, h), ts(d, h), 70 + random.randint(-8, 30))
    rec("HKQuantityTypeIdentifierDietaryWater", PHONE, "mL", ts(d, 10), ts(d, 10), 750)
    rec("HKQuantityTypeIdentifierDietaryWater", PHONE, "mL", ts(d, 15), ts(d, 15), 500)
    rec("HKQuantityTypeIdentifierDietaryEnergyConsumed", PHONE, "kcal", ts(d, 13), ts(d, 13), 650)
    rec("HKQuantityTypeIdentifierDietaryProtein", PHONE, "g", ts(d, 13), ts(d, 13), 42)
    rec("HKQuantityTypeIdentifierAppleExerciseTime", WATCH, "min", ts(d, 17), ts(d, 17, 30), 22)
    rec("HKQuantityTypeIdentifierActiveEnergyBurned", WATCH, "kJ", ts(d, 17), ts(d, 17, 30), 1674.4)  # 400 kcal
    if i % 7 == 0:
        rec("HKQuantityTypeIdentifierBodyMass", PHONE, "kg", ts(d, 7), ts(d, 7), round(79 - i * 0.01, 1))
    if i % 30 == 0:
        rec("HKQuantityTypeIdentifierVO2Max", WATCH, "mL/min·kg", ts(d, 18), ts(d, 18), round(42.5 + i * 0.01, 1))
    # Sleep for the night ending on d: watch stages 23:00 -> 06:30, Fitbit overlapping and less detailed.
    prev = d - dt.timedelta(days=1)
    short = (i == 119)
    segs = [("Core", 23, 0, 23, 40), ("Deep", 23, 40, 0, 40), ("Core", 0, 40, 1, 50), ("REM", 1, 50, 2, 20), ("Awake", 2, 20, 2, 30),
            ("Core", 2, 30, 3, 40), ("Deep", 3, 40, 4, 10), ("REM", 4, 10, 5, 0), ("Core", 5, 0, 6, 30)]
    if short:
        segs = [("Core", 1, 0, 1, 50), ("Deep", 1, 50, 2, 40), ("REM", 2, 40, 3, 30), ("Core", 3, 30, 7, 10)]
    for st, h1, m1, h2, m2 in segs:
        d1 = prev if h1 >= 18 else d
        d2 = prev if h2 >= 18 else d
        rec("HKCategoryTypeIdentifierSleepAnalysis", WATCH, "", ts(d1, h1, m1), ts(d2, h2, m2), f"HKCategoryValueSleepAnalysisAsleep{st}" if st != "Awake" else "HKCategoryValueSleepAnalysisAwake")
    rec("HKCategoryTypeIdentifierSleepAnalysis", FITBIT, "", ts(prev, 23, 10) if not short else ts(d, 1, 5), ts(d, 6, 20), "HKCategoryValueSleepAnalysisAsleepUnspecified")
    lines.append(f' <ActivitySummary dateComponents="{d.isoformat()}" activeEnergyBurned="400" activeEnergyBurnedGoal="600" activeEnergyBurnedUnit="kcal" appleMoveTime="0" appleMoveTimeGoal="0" appleExerciseTime="22" appleExerciseTimeGoal="30" appleStandHours="{10 if i % 3 else 12}" appleStandHoursGoal="12"/>')
    if i % 4 == 0:
        lines.append(f' <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="31.5" durationUnit="min" {WATCH} creationDate="{ts(d, 18)}" startDate="{ts(d, 17, 30)}" endDate="{ts(d, 18)}">\n  <MetadataEntry key="HKIndoorWorkout" value="0"/>\n </Workout>')
lines.append('</HealthData>')
xml = "\n".join(lines)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("apple_health_export/export.xml", xml)
    z.writestr("apple_health_export/export_cda.xml", "<ClinicalDocument/>")
open(OUT.replace(".zip", ".xml"), "w").write(xml)
import json; json.dump(truth, open(OUT.replace(".zip", ".truth.json"), "w"))
print(len(lines), "lines,", len(xml)//1024, "KB")
