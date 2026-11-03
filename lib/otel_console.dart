// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Captures `print`, `stdout` and `stderr` into the OpenTelemetry logs
/// signal without looping, and gives OpenTelemetry's own reports the
/// original console.
library;

export 'src/otel_console.dart';
