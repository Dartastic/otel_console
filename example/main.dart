// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_console/otel_console.dart';

/// Captures console output as OpenTelemetry log records. Run all of main
/// inside [OTelConsole.capture]: output before it, or from another
/// isolate, is not captured.
Future<void> main() => OTelConsole.capture(() async {
      await OTel.initialize(serviceName: 'otel-console-example');

      // On the console as before, and an INFO record with log.iostream stdout.
      print('Service started');
      stdout.writeln('Listening on port 8080');

      // On standard error as before, and a WARN record with log.iostream stderr.
      stderr.writeln('Config file not found; using defaults');

      // On the console only: not a log record.
      OTelConsole.runUncaptured(() => print('health check ok'));

      // Your own error handler writes to the original console, never `print`,
      // so a failing export can't report itself through the capture.
      OTelAPI.setErrorHandler(
        (error, stackTrace) => OTelConsole.writeError('OpenTelemetry: $error'),
      );

      await OTel.shutdown();
    });
