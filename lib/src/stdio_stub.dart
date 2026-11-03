// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// Without dart:io there is no standard error: the root zone's print.
void writeOriginalError(String line) => Zone.root.print(line);

/// Without dart:io there is no `stdout` or `stderr` to capture.
R runWithStdio<R>(
  R Function() body,
  void Function(String line, LogIostream stream, Severity severity) emit,
) =>
    body();
