# Carbs

A personal iOS app for meal tracking and weight management, with weekly coaching that adjusts your calorie target.

- Food logging with timestamps and suggested carb absorption times
- Weight tracking with trend weight
- Weekly check-ins that suggest a new calorie target you can accept or override
- Confirm-only carb suggestions for Loop



## Build

1. Open `Carbs.xcodeproj` in Xcode (or regenerate it with `xcodegen generate` after editing `project.yml`).
2. Pick your iPhone as the run destination and press Run. Signing uses your paid team (W8BGT53U8Q).
3. Tests: `xcodebuild -project Carbs.xcodeproj -scheme Carbs -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`

Debug builds accept `-demo` (sample data) and `-tab N` launch arguments for Simulator screenshots.

## How the coach works

See `Carbs/Coach/CoachEngine.swift`. Each check-in:

- counts the week as on target when average calories are within ±3% and protein is at least 97% of target (carbs and fat don't count);
- measures weight change by start/end weigh-ins, then weekly averages, then trend weight as on-target weeks add up;
- updates a maintenance estimate from intake and weight change (3,500 Cal per lb);
- suggests a target that moves toward your goal rate by at most 7% (Gentle) or 15% (Aggressive), never below your calorie floor.

You can accept the suggestion or set your own number.
