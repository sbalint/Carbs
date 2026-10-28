# Carbs

A personal iOS app for meal tracking and weight management, with weekly coaching that adjusts your calorie target.

- Food logging with timestamps and suggested carb absorption times
- Weight tracking with trend weight
- Weekly check-ins that suggest a new calorie target you can accept or override
- Confirm-only carb suggestions for Loop

Built for personal use.

## Build

1. Open `Carbs.xcodeproj` in Xcode (or regenerate it with `xcodegen generate` after editing `project.yml`).
2. Set `DEVELOPMENT_TEAM` in `project.yml` to your own Apple team, run `xcodegen generate`, pick your iPhone and press Run.
3. Tests: `xcodebuild -project Carbs.xcodeproj -scheme Carbs -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`

Debug builds accept `-demo` (sample data) and `-tab N` launch arguments for Simulator screenshots.

## How the coach works

See `Carbs/Coach/CoachEngine.swift`. Each check-in:

- counts the week as on target when average calories are within ±3% and protein is at least 97% of target (carbs and fat don't count);
- measures weight change by start/end weigh-ins, then weekly averages, then trend weight as on-target weeks add up;
- updates a maintenance estimate from intake and weight change (3,500 Cal per lb);
- suggests a target that moves toward your goal rate by at most 7% (Gentle) or 15% (Aggressive), never below your calorie floor.

You can accept the suggestion or set your own number.

## FatSecret (via Cloudflare Worker)

`server/fatsecret-proxy` holds the FatSecret OAuth 1.0 secret and returns foods with servings.

1. `cd server/fatsecret-proxy && npm install`
2. `npx wrangler login`, then set secrets: `npx wrangler secret put FATSECRET_KEY` (and `FATSECRET_SECRET`, `APP_TOKEN`)
3. `npx wrangler deploy`
4. Copy `Carbs/Config/Secrets.example.xcconfig` to `Secrets.xcconfig` and fill in the Worker URL and `APP_TOKEN`.

For local testing, put the same three values in `server/fatsecret-proxy/.dev.vars` and run `npx wrangler dev`.
Neither `Secrets.xcconfig` nor `.dev.vars` is committed. Without them, search uses USDA and Open Food Facts only.
