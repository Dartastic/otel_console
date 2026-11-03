// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'stdio_stub.dart' if (dart.library.io) 'stdio_io.dart' as stdio;

/// Zone flag set while a console line is being emitted as a log record.
/// Anything printed under it reaches the console but is not captured
/// again, so an emit that prints cannot loop.
const Symbol _emittingKey = #otel_console_emitting;

/// Zone flag set by [OTelConsole.runUncaptured].
const Symbol _suppressKey = #otel_console_suppress;

/// Captures the application's console output into the OpenTelemetry logs
/// signal, and gives OpenTelemetry's own reports a console that is never
/// captured.
///
/// ```dart
/// void main() => OTelConsole.capture(() async {
///   await OTel.initialize(serviceName: 'my-app');
///   print('ready'); // on the console, and an INFO log record
/// });
/// ```
///
/// Inside [capture]:
/// - `print`, and Flutter's `debugPrint` (which goes through `print`),
///   become INFO records with `log.iostream` `stdout`.
/// - On dart:io platforms, `stdout` writes become INFO records and
///   `stderr` writes become WARN records, with `log.iostream` set, one
///   record per line.
/// - Every line still reaches the real console unchanged.
///
/// Three rules keep the capture from looping, for example when a failed
/// export reports an error that would otherwise be printed, captured,
/// and fail to export again:
/// 1. OpenTelemetry's error handler and its diagnostics
///    (`OTelLog.logFunction`) write to the original console
///    ([write], [writeError]), never through the capture.
/// 2. While a record is being emitted, anything printed in that call is
///    written to the console but not captured again.
/// 3. OpenTelemetry's own diagnostics are therefore never bridged.
///
/// Capture never throws into the application: a failure is reported
/// through `OTelErrorHandling.report`.
abstract final class OTelConsole {
  /// The instrumentation scope name of captured records.
  static const String scopeName = 'otel_console';

  /// Writes [line] to the original console's standard output. It is
  /// never captured, so it is safe in an error handler or a log
  /// function.
  static void write(String line) => Zone.root.print(line);

  /// Writes [line] to the original console's standard error (standard
  /// output where there is none, as on the web). It is never captured.
  static void writeError(String line) => stdio.writeOriginalError(line);

  /// Sends OpenTelemetry's error handler and its diagnostics
  /// (`OTelLog.logFunction`) to the original console: errors to
  /// [writeError], diagnostics to [write].
  ///
  /// [capture] calls this unless told not to. Call it yourself if you
  /// install your own error handler afterwards: that handler should
  /// write with [write] or [writeError], not `print`.
  static void routeOTelDiagnostics() {
    OTelAPI.setErrorHandler((error, stackTrace) {
      writeError('OpenTelemetry error: $error');
      if (stackTrace != null) writeError('$stackTrace');
    });
    OTelLog.logFunction = write;
  }

  /// Runs [body] with its console output captured. Run all of `main` in
  /// it: only code in this zone is seen, so a `print` before the call or
  /// from another isolate is not captured.
  ///
  /// [captureStdio] also captures `stdout` and `stderr` on dart:io
  /// platforms. [routeDiagnostics] calls [routeOTelDiagnostics] first.
  /// [loggerProvider] defaults to `OTelAPI.loggerProvider()`, looked up
  /// on each line, so the SDK can be initialized inside [body].
  static R capture<R>(
    R Function() body, {
    bool captureStdio = true,
    bool routeDiagnostics = true,
    APILoggerProvider? loggerProvider,
  }) {
    if (routeDiagnostics) routeOTelDiagnostics();
    void emit(String line, LogIostream stream, Severity severity) =>
        _emit(line, stream, severity, loggerProvider);
    R printing() => runZoned(
          body,
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              parent.print(zone, line);
              emit(line, LogIostream.stdout, Severity.INFO);
            },
          ),
        );
    return captureStdio ? stdio.runWithStdio(printing, emit) : printing();
  }

  /// Runs [body] with capture turned off: its output reaches the console
  /// but does not become log records.
  static R runUncaptured<R>(R Function() body) =>
      runZoned(body, zoneValues: {_suppressKey: true});

  /// Whether output in the current zone is not captured: inside
  /// [runUncaptured], or while a captured line is being emitted.
  static bool get isUncaptured =>
      Zone.current[_suppressKey] == true || Zone.current[_emittingKey] == true;

  static void _emit(
    String line,
    LogIostream stream,
    Severity severity,
    APILoggerProvider? loggerProvider,
  ) {
    if (isUncaptured) return;
    // Emitted in the caller's zone, so the record carries the span that
    // was active when the line was written, with the emitting flag set.
    Zone.current.fork(zoneValues: {_emittingKey: true}).run(() {
      try {
        (loggerProvider ?? OTelAPI.loggerProvider()).getLogger(scopeName).emit(
              severityNumber: severity,
              severityText: severity.name,
              body: line,
              attributes: OTelAPI.attributes([
                OTelAPI.attributeString(Log.logIostream.key, stream.value),
              ]),
            );
      } catch (error, stackTrace) {
        OTelErrorHandling.report(error, stackTrace);
      }
    });
  }
}
