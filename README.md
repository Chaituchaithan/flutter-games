# Chess (Aura games platform)

A Flutter multiplayer games platform built from the Aura design. Chess, Ludo
and Snakes & Ladders are playable. The platform (accounts, profile, store,
friends, tournaments, season pass) is shared, and each game is a
self-contained module, so a release can ship one game per app (see
docs/RUN_AND_TEST.md §11 "Apps").

- **Play:** Quick Play vs the computer (3 levels, time per move), online
  matches, private rooms with friends, offline practice.
- **Backend:** REST API gateway (auth, profile) + a realtime WebSocket per
  game service.
- **Stack:** Flutter · Riverpod · Dio · `web_socket_channel` · `google_fonts`.

## Quick start

```
flutter pub get
dart run tools/cors_proxy.dart      # terminal 1 — dev proxy (needed for web)
flutter run -d chrome               # terminal 2
```
On an Android emulator without the proxy:
`flutter run -d emulator-5554 --dart-define=USE_PROXY=false`.

Checks: `flutter analyze` and `flutter test`.

## Docs

| Doc | Read it for |
|---|---|
| [docs/RUN_AND_TEST.md](docs/RUN_AND_TEST.md) | Running (web / emulator, proxy on/off), logs, socket diagnostics, tests |
| [docs/BUILD_GUIDE.md](docs/BUILD_GUIDE.md) | Building an app per game (Android / iOS / web), installing, store-release checklist, build log |
| [docs/SERVICES_AND_REALTIME.md](docs/SERVICES_AND_REALTIME.md) | Configuration, REST + socket flows, profile API, game switching |
| [docs/DESIGN_SPEC.md](docs/DESIGN_SPEC.md) | Design tokens, shared widgets, differences from the mockup, required assets |
| [docs/TEST_CASES.md](docs/TEST_CASES.md) | Manual QA test cases (by area, with status) and the automated test map |

## Project layout

```
lib/
  main.dart         all-games app (development)
  main_<game>.dart  one app per game (chess, ludo, snakes)
  app/        app shell: routes, AppProfile (which games an app ships), GameModule, GameArea
  configs/    ALL configuration (hosts, ports, endpoints, switches, games)
  data/       models, sources (static + remote), repositories
  game/       one folder per game (rules, board, screens, module) + common/ (shared by games)
  screens/    shared UI by feature (auth, home, match, profile, store, …)
  services/   API client, auth/session, sockets, game session contract
  state/      shared async view
  widgets/    shared UI components
tools/        dev proxy (cors_proxy), chess end-to-end check (chess_flow_test)
```
