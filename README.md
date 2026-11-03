<!-- dartastic-header:start -->
# OpenTelemetry instrumentation for console output

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenTelemetry Specification](https://img.shields.io/badge/OpenTelemetry-Specification-blueviolet)](https://opentelemetry.io/docs/specs/otel/)

`otel_console` is an [OpenTelemetry](https://opentelemetry.io/) instrumentation for console output that
easily adds standard observability to any Dart or Flutter application's `print`, `stdout` and `stderr`.  This package depends on 
[dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api).

This package supports Android, iOS, Linux, macOS, Web and Windows. On the web it captures `print`; `stdout` and `stderr` are captured on dart:io platforms. It is WASM-ready.

This package can be used with any OTel backend because it's compliant with the OpenTelemetry Specification.

This Apache-2.0 package is professionally maintained and supported with 💙 by Michael Bushe,
Dart and Flutter Maintainer at OpenTelemetry and the creator of [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
and [dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api). This package is professionally supported by
[Dartastic.io](https://dartastic.io).

---
## Dartastic.io: AI Code Healing and Real User Monitoring for Flutter

**See what your users experience. Find problems with Flutter apps in production. Fix them with AI.**

[Dartastic.io](https://dartastic.io) brings AI code healing, real user monitoring, and OpenTelemetry observability together in one platform built for Dart and Flutter. (Patents pending)

![Dartastic AI answering "Why did crashes jump after the last release?" over a Flutter App Health dashboard](https://dartastic.io/img/pub-dev/HomePageCrashesQuestion.png)

### Dartastic AI — From Production Problems to Code Fixes

Dartastic AI analyzes production telemetry alongside your application source code to diagnose problems and propose fixes.

- **Investigate production issues** using crashes, errors, traces, metrics, and real user telemetry.
- **Find the offending code** by connecting observed problems with your application's source in Dartastic Pub or your source code repos.
- **Generate code patches** that address the underlying problems.
- **Create actionable issues** in your issue tracker, complete with findings and the proposed code patch.

### Dartastic RUM — See What Your Users See

Understand how people actually experience your Flutter application.

- **Replay user sessions** in the Dartastic Observatory session player.
- **Choose your replay fidelity**, from privacy-preserving widget outlines to pixel-level reproductions of the user experience.
- **Investigate real user problems** using session replay and production observability data.

![Dartastic RUM Session Replay](https://dartastic.io/img/pub-dev/session-replay.png)

### Dartastic Observatory — Observability Built for Flutter

A complete observability backend where Flutter and Dart are first-class citizens.

- **Flutter-specific dashboards** for application performance, health, and reliability.
- **Alerts and notifications** through email, Slack, and PagerDuty.
- **Dartastic Cloud Observatory** — Start with a 30-day free trial on isolated, shared infrastructure, as low as $39/mo.
- **Dartastic Hosted Observatory** — Run the observability stack in a private managed environment, sized from Mini to Enterprise XL.
- **Dartastic Self-Hosted Observatory** — The whole platform inside your own network. Your keys, your cluster, with nothing leaving your perimeter.

### Dartastic Native OTel Runtime — Native OpenTelemetry Performance

Collect production telemetry without burdening Flutter's main isolate.

- **Native OpenTelemetry runtime** that moves telemetry processing off the main isolate.
- **Native crash reporting** for problems that Dart can't catch.
- **Widget performance diagnostics** to identify janky widgets.
- **On-device PII filtering** before sensitive data leaves your application.
- **Source-level error diagnostics** powered by the Dartastic Symbolizer API.
- **Platform-native metrics** for iOS, Android, and Linux, including iOS MetricKit and Android Vitals.
- **OpenTelemetry compatibility** — Send telemetry to Dartastic Observatory or any OpenTelemetry platform.

### Dartastic Labs — OpenTelemetry Integrations

Instrument more of your application without writing everything yourself.

- **650+ open-source integrations** for Dart and Flutter libraries and services, including Dio, Shelf, Logger, Anthropic, AWS, Azure, and Stripe. Look for otel_* on pub.dev.

### More Dartastic Tools

**[Dartastic Pub](https://dartastic.io/pub)**

A private Dart package registry for sharing packages and plugins with your team, partners, and customers.

**[Dartastic Symbolizer](https://dartastic.io/symbolizer)**

Turn production errors into lines of source code through a web API, while keeping your source code artifacts private.

### Professional Support and Training

Dartastic.io offers commercial support for the open-source `dartastic_opentelemetry` and `dartastic_opentelemetry_api` packages and the complete Dartastic product suite.

- **Professional support** with available around-the-clock coverage and response times under four hours on qualifying plans.
- **OpenTelemetry training** for teams instrumenting Dart, Flutter, mobile, and web applications.

### Open Standards. No Mandatory Backend.

The Dartastic OpenTelemetry API and SDK are open source and standards-based. You can use them independently of Dartastic's commercial services and send telemetry to any compatible OpenTelemetry backend.

Dartastic's commercial products add native performance, advanced diagnostics, session replay, AI-assisted remediation, and managed observability services.

**[Explore Dartastic.io](https://dartastic.io)**

---
<!-- dartastic-header:end -->

Captures an application's console output into the OpenTelemetry logs
signal: `print`, Flutter's `debugPrint`, and on dart:io platforms
`stdout` and `stderr`. Every line still reaches the console unchanged,
and also becomes a log record that carries the span that was active
when the line was written.

The logging bridges `otel_logging`, `otel_logger`, `otel_loggy`,
`otel_simple_logger` and `otel_talker` use it, so one call captures
both your logging package and your console.

## Install

```yaml
dependencies:
  otel_console: ^0.1.0
```

## Use

Run all of `main` inside `OTelConsole.capture`. Only code in its zone is
seen, so a `print` before the call, or from another isolate, is not
captured.

```dart
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_console/otel_console.dart';

Future<void> main() => OTelConsole.capture(() async {
  await OTel.initialize(serviceName: 'my-app');
  print('ready'); // on the console, and an INFO log record
});
```

| Output                       | Severity | `log.iostream` |
|------------------------------|----------|----------------|
| `print`, `debugPrint`        | INFO     | `stdout`       |
| `stdout` (dart:io platforms) | INFO     | `stdout`       |
| `stderr` (dart:io platforms) | WARN     | `stderr`       |

Each complete line is one record, and empty lines are skipped. Records
use the instrumentation scope `otel_console`.

`OTelConsole.runUncaptured(body)` sends output in `body` to the console
only.

## No loops

If an export fails and the failure is printed, the print becomes a log
record. That record can fail to export too, and so on. Three rules
prevent this:

1. `capture` sends OpenTelemetry's error handler and its diagnostics
   (`OTelLog.logFunction`) to the original console, captured before the
   capture starts. Pass `routeDiagnostics: false` to keep your own.
2. Anything printed while a record is being emitted reaches the console
   but is not captured again.
3. OpenTelemetry's own diagnostics are therefore never bridged.

If you install your own error handler, have it write with
`OTelConsole.write` or `OTelConsole.writeError`, not `print`:

```dart
OTelAPI.setErrorHandler(
  (error, stackTrace) => OTelConsole.writeError('OpenTelemetry: $error'),
);
```

Don't combine `capture` with the SDK's own print interception
(`OTel.initialize(logPrint: true)`), or with a console exporter that
prints through `print`. Give a console exporter
`printFunction: OTelConsole.write` instead.

A capture failure is reported through `OTelErrorHandling.report`, never
thrown into the app.
