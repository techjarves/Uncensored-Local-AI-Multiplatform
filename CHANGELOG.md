# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2026-09-02

Correctness and security pass over the local API server, the inference path,
and model downloading, plus desktop packaging for all three platforms.

### Security

- **The local API server now requires an API key.** It previously performed no
  authentication at all — the README advertised a key (`local`) that no request
  handler ever read, so any caller, including any web page the user visited
  (CORS was `*`), could drive the loaded model. Each install now generates its
  own bearer token, shown and copyable in Settings. `/healthz` stays open for
  liveness probes and never echoes the token.
- Authentication cannot be disabled while **Allow External Connections** is on.
- Tokens are compared in constant time and can be regenerated on demand.

### Fixed

- **Changing the API port broke the server.** `setPort()` updated the observable
  before calling `start()`, whose no-op guard compared against that same
  observable — so the socket was never rebound. The new port refused
  connections, the old one kept serving, and `/healthz` reported a port it was
  not listening on. `setAllInterfaces()` hit the same guard, so the external
  connections toggle silently did nothing too.
- **The in-app chat ignored each model's prompt template.** It hand-built a
  fixed pseudo-ChatML prompt for every model, while the API server correctly
  applied the GGUF's own template. Gemma, Llama 3 and Mistral all expect
  different control tokens; both recommended models are Gemma. Both paths now
  share one templated implementation.
- **The temperature slider did nothing.** The value was persisted, restored and
  passed all the way down to `generate()`, which declared the parameter and then
  never used it.
- **Model downloads were never validated.** No HTTP status was checked, so a
  404 page, a 403, or a login redirect was written to disk and renamed to
  `.gguf`. Resume sent a `Range` header without verifying `206 Partial
  Content`, so a server answering `200` produced a corrupt file roughly 1.5x
  the correct size.
- **Cancelling one download killed the others.** All transfers shared a single
  `http.Client` field that each new download overwrote and any completion
  closed. Each transfer now owns its client.
- **Streaming responses did not stream.** SSE frames were never flushed, so
  tokens arrived in bursts instead of as generated.
- **Malformed API requests were masked.** The model-readiness check ran before
  body parsing, so invalid JSON and empty message arrays all returned
  `503 model_not_loaded`. Validation now runs first and reports the offending
  parameter.
- **An out-of-range port was silently replaced with 4891** with no feedback.
- **macOS release builds were broken by their entitlements.** The sandboxed
  release build granted only `app-sandbox`, so it could not download models
  (no `network.client`), could not start the API server (no `network.server`),
  and could not import a `.gguf` (no user-selected file access).
- The wakelock is no longer released while a model is still loaded or
  generating.

### Added

- **Context-window budgeting.** The full history was sent every turn against a
  1024-token context on Android, so long conversations were truncated by
  llama.cpp with no indication and the model quietly forgot the beginning.
- **Optional SHA-256 verification** of downloaded models, via a `sha256` field
  on catalog entries. Hashing streams the file, so a multi-GB model is never
  held in memory; a mismatch deletes the download.
- **Desktop packaging** in [`packaging/`](packaging/README.md): a Linux
  AppImage builder (verified end to end), a Windows Inno Setup installer plus
  portable zip, and a macOS sign/notarize/staple script.
- **CI** that gates on `flutter analyze` and `flutter test`, and builds Linux,
  Windows and macOS.
- **A real test suite**: 50 tests covering API rebinding, authentication,
  request validation, routing, download integrity, resume behaviour, context
  trimming, and the chat widgets. The previous suite was 3 happy-path API tests
  plus a stub asserting `true`.

### Changed

- Repaints during streaming are coalesced to ~66ms instead of rebuilding the
  entire message list and sidebar on every token.
- `flutter analyze` is scoped to `lib/` and `test/`, excluding generated and
  platform runner directories.
- Deprecated `Color.withOpacity()` replaced with `withValues(alpha:)`.
- Version aligned with the README: `pubspec.yaml` said `1.1.0+2` while the
  project shipped as v2.0.0.
- Removed a stray `test.cpp` from the repository root.

### Breaking

- API clients must send the key from **Settings → Local API Server** as
  `Authorization: Bearer <key>`. The previously documented value `local` was
  never validated and is now rejected. Authentication can be turned off for
  loopback-only use.

## [2.0.0] - 2026-04-23

### Added
- **Global Loading Overlay**: Real-time feedback during large model imports with dynamic pulse messages.
- **Deduplication Logic**: Prevents duplicate model cards and synchronized loading states for models with the same filename.
- **Log Viewer**: New "Logs" screen accessible from the drawer to track and share system logs for troubleshooting.
- **RAM/Size Validation**: Safety dialogs that warn users before importing or loading models that exceed device resource thresholds.
- **Manual Cache Management**: "Clear Temporary Cache" button in settings to reclaim storage from interrupted imports.

### Changed
- **Optimized Model Imports**: Switched from slow stream-copying to instantaneous file-renaming (moving) for local file imports.
- **Startup Resilience**: App no longer crashes on splash screen if the Local API port is already in use.
- **UI Improvements**: Hidden '0%' percentage text on local imports for a cleaner indeterminate loading state.
- **Version Bump**: Updated app version to v2.0.0.

### Fixed
- **Ghost Writing**: Resolved issue where AI generation continued after tapping the "Stop" button.
- **Temporary Cache Bloat**: Automatic cleanup of massive temporary files after successful model imports.
- **Address in Use Error**: Handled socket exceptions in `LocalApiServerService`.

---
