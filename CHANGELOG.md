# Changelog

## [0.1.0-wip]

### Added

- `OTelConsole.capture(body)`: inside `body`, `print` (and Flutter's `debugPrint`) and, on dart:io platforms, `stdout` and `stderr` become OpenTelemetry log records, one per line, with `log.iostream` set. `print` and `stdout` are INFO and `stderr` is WARN. Every line still reaches the console unchanged.
- No loops: `capture` sends OpenTelemetry's error handler and its diagnostics (`OTelLog.logFunction`) to the original console, and a line printed while a record is being emitted is not captured again.
- `OTelConsole.write` and `OTelConsole.writeError`: the original console, never captured, for an app's own OpenTelemetry error handler.
- `OTelConsole.runUncaptured(body)`: output in `body` reaches the console only.
- A capture failure is reported through `OTelErrorHandling.report`, never thrown into the app.
