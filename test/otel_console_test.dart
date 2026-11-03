// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_console/otel_console.dart';
import 'package:test/test.dart';

/// Records every log record it is asked to export, and fails each export
/// when [fail] is set.
class _Exporter implements LogRecordExporter {
  _Exporter({this.fail = false});

  final bool fail;
  final List<ReadableLogRecord> records = [];

  @override
  Future<ExportResult> export(List<ReadableLogRecord> rs) async {
    records.addAll(rs);
    return fail ? ExportResult.failure : ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

/// A stand-in for the process's stdout or stderr that keeps what is
/// written to it.
class _Sink implements Stdout {
  final StringBuffer text = StringBuffer();

  @override
  void write(Object? object) => text.write(object);

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Runs [body] where print reaches [console] (the "real" console the
/// capture writes through to), and stdout and stderr are [out] and [err].
Future<void> _withConsole(
  List<String> console,
  _Sink out,
  _Sink err,
  Future<void> Function() body,
) =>
    IOOverrides.runZoned(
      () => runZoned(
        body,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => console.add(line),
        ),
      ),
      stdout: () => out,
      stderr: () => err,
    );

void main() {
  late List<String> console;
  late _Sink out;
  late _Sink err;

  setUp(() async {
    await OTel.reset();
    console = [];
    out = _Sink();
    err = _Sink();
  });

  tearDown(() async {
    OTelLog.currentLevel = LogLevel.error;
    OTelLog.logFunction = print;
    OTelAPI.setErrorHandler(null);
    await OTel.shutdown();
    await OTel.reset();
  });

  Future<_Exporter> initialize(
    LogRecordProcessor Function(_Exporter) p, {
    bool fail = false,
  }) async {
    final exporter = _Exporter(fail: fail);
    await OTel.initialize(
      serviceName: 'otel-console-test',
      detectPlatformResources: false,
      logRecordProcessor: p(exporter),
    );
    return exporter;
  }

  test('print reaches the console and becomes an INFO record', () async {
    await _withConsole(console, out, err, () async {
      await OTelConsole.capture(() async {
        final exporter = await initialize(SimpleLogRecordProcessor.new);
        print('hello');
        await Future<void>.delayed(Duration.zero);

        final record = exporter.records.singleWhere((r) => r.body == 'hello');
        expect(record.severityNumber, Severity.INFO);
        expect(record.instrumentationScope.name, OTelConsole.scopeName);
        expect(
          record.attributes?.getString(Log.logIostream.key),
          LogIostream.stdout.value,
        );
      });
    });
    expect(console, contains('hello'));
  });

  test('stdout lines are INFO, stderr lines are WARN, written through',
      () async {
    await _withConsole(console, out, err, () async {
      await OTelConsole.capture(() async {
        final exporter = await initialize(SimpleLogRecordProcessor.new);
        stdout.write('par');
        stdout.write('tial\nsecond\n');
        stderr.writeln('oops');
        await Future<void>.delayed(Duration.zero);

        final bodies = {
          for (final r in exporter.records) r.body: r.severityNumber,
        };
        expect(bodies, {
          'partial': Severity.INFO,
          'second': Severity.INFO,
          'oops': Severity.WARN,
        });
        final oops = exporter.records.singleWhere((r) => r.body == 'oops');
        expect(
          oops.attributes?.getString(Log.logIostream.key),
          LogIostream.stderr.value,
        );
      });
    });
    expect(out.text.toString(), 'partial\nsecond\n');
    expect(err.text.toString(), 'oops\n');
  });

  test('a record carries the span that was active when the line was written',
      () async {
    await _withConsole(console, out, err, () async {
      await OTelConsole.capture(() async {
        final exporter = await initialize(SimpleLogRecordProcessor.new);
        final span = OTel.tracer().startSpan('work');
        Context.current.withSpan(span).runSync(() => print('inside'));
        span.end();
        await Future<void>.delayed(Duration.zero);

        final record = exporter.records.singleWhere((r) => r.body == 'inside');
        expect(record.spanId, span.spanContext.spanId);
      });
    });
  });

  test('printing while a record is emitted is not captured again', () async {
    await _withConsole(console, out, err, () async {
      await OTelConsole.capture(() async {
        final exporter = await initialize(
          (e) => _PrintingProcessor(SimpleLogRecordProcessor(e)),
        );
        print('once');
        await Future<void>.delayed(Duration.zero);

        expect(exporter.records.map((r) => r.body), ['once']);
      });
    });
    expect(console, ['once', 'processing once']);
  });

  test('runUncaptured output reaches the console only', () async {
    await _withConsole(console, out, err, () async {
      await OTelConsole.capture(() async {
        final exporter = await initialize(SimpleLogRecordProcessor.new);
        OTelConsole.runUncaptured(() => print('quiet'));
        await Future<void>.delayed(Duration.zero);

        expect(exporter.records, isEmpty);
      });
    });
    expect(console, ['quiet']);
  });

  test('a capture failure is reported, never thrown into the app', () async {
    final reported = <Object>[];
    await _withConsole(console, out, err, () async {
      await OTelConsole.capture(
        () async {
          OTelAPI.setErrorHandler((e, _) => reported.add(e));
          print('still printed');
        },
        routeDiagnostics: false,
        loggerProvider: _ThrowingProvider(),
      );
    });
    expect(console, ['still printed']);
    expect(reported, hasLength(1));
  });

  group('an always-failing exporter', () {
    // The batch processor's timer runs in the capture zone, outside any
    // emit, like a real export that fails on a later batch.
    LogRecordProcessor batch(_Exporter e) => BatchLogRecordProcessor(
          e,
          const BatchLogRecordProcessorConfig(
            scheduleDelay: Duration(milliseconds: 5),
          ),
        );

    test('gets one export attempt per printed line', () async {
      late _Exporter exporter;
      await _withConsole(console, out, err, () async {
        await OTelConsole.capture(() async {
          OTelLog.currentLevel = LogLevel.debug;
          exporter = await initialize(batch, fail: true);
          for (var i = 0; i < 3; i++) {
            print('line $i');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      });
      expect(exporter.records.map((r) => r.body), [
        'line 0',
        'line 1',
        'line 2',
      ]);
    });

    test('loops when diagnostics go through print (the control)', () async {
      // Validates the test above: with OTel's diagnostics printed through
      // the capture, each failed batch makes the next one.
      late _Exporter exporter;
      await _withConsole(console, out, err, () async {
        await OTelConsole.capture(() async {
          OTelLog.currentLevel = LogLevel.debug;
          OTelLog.logFunction = print;
          exporter = await initialize(batch, fail: true);
          print('line 0');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }, routeDiagnostics: false);
      });
      expect(exporter.records.length, greaterThan(3));
    });
  });
}

/// Prints while each record is processed, as a diagnostic would.
class _PrintingProcessor implements LogRecordProcessor {
  _PrintingProcessor(this._inner);

  final LogRecordProcessor _inner;

  @override
  Future<void> onEmit(ReadWriteLogRecord logRecord, Context? context) {
    print('processing ${logRecord.body}');
    return _inner.onEmit(logRecord, context);
  }

  @override
  bool enabled({
    Context? context,
    InstrumentationScope? instrumentationScope,
    Severity? severityNumber,
    String? eventName,
  }) =>
      true;

  @override
  Future<void> forceFlush() => _inner.forceFlush();

  @override
  Future<void> shutdown() => _inner.shutdown();
}

/// A logger provider whose loggers cannot be created.
class _ThrowingProvider implements APILoggerProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('no loggers');
}
