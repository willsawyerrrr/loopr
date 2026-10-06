# CLAUDE.md

## Repo purpose

Loopr generates loop routes (GPX) for a run, walk or ride. A Vercel
TypeScript function (`/api/route`) calls Trail Router and picks the candidate
closest to the target distance; a native SwiftUI iOS 26 app drives it.

## Layout

- `api/` — Vercel handlers (`route.ts`, `preview.ts`).
- `src/` — route generation: workout parsing, Trail Router client, guided
  (pins/heading) tuning, variants, GPX, preview rendering and store.
- `test/` — Vitest suites, one per `src/` module.
- `ios/` — XcodeGen app (`project.yml`), `Loopr/` UI, `RouteKit/` shared Swift
  package with its own tests.
- `docs/feat/ios-app/overview.md` — iOS app design; `docs/brand/` — icon source.

## Commands

- `npm test`, `npm run typecheck` — API checks (Node 22).
- `cd ios/RouteKit && swift test` — RouteKit tests.
- `cd ios && xcodegen generate` — regenerate the uncommitted `.xcodeproj`.

## Conventions

- Change to the API request/response or iOS behaviour updates `README.md` and
  `docs/feat/ios-app/overview.md` in the same PR.
- `RouteConfig` defaults in `src/config.ts` are mirrored by `PaceStore` in
  RouteKit; change both together.
- Bundle ID is `dev.willsawyerrrr.loopr`. `ios/Config/Local.xcconfig` is
  gitignored.
