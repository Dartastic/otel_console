// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// Writes [line] to the process's real standard error: the one the root
/// zone sees, outside every `IOOverrides` zone, including the capture's.
void writeOriginalError(String line) =>
    Zone.root.run(() => stderr).writeln(line);

/// Runs [body] with `stdout` and `stderr` replaced by sinks that write
/// through to the current ones and emit each complete line.
R runWithStdio<R>(
  R Function() body,
  void Function(String line, LogIostream stream, Severity severity) emit,
) {
  final out = _CapturingStdout(
    stdout,
    (line) => emit(line, LogIostream.stdout, Severity.INFO),
  );
  final err = _CapturingStdout(
    stderr,
    (line) => emit(line, LogIostream.stderr, Severity.WARN),
  );
  return IOOverrides.runZoned(body, stdout: () => out, stderr: () => err);
}

/// A [Stdout] that writes everything to [_target] unchanged and passes
/// each complete line to [_onLine]. A partial line waits for its end, or
/// for [flush] or [close].
class _CapturingStdout implements Stdout {
  _CapturingStdout(this._target, this._onLine);

  final Stdout _target;
  final void Function(String line) _onLine;
  final StringBuffer _pending = StringBuffer();

  void _text(String text) {
    var start = 0;
    for (var i = text.indexOf('\n'); i >= 0; i = text.indexOf('\n', start)) {
      _pending.write(text.substring(start, i));
      _line();
      start = i + 1;
    }
    _pending.write(text.substring(start));
  }

  void _line() {
    var line = _pending.toString();
    _pending.clear();
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.isNotEmpty) _onLine(line);
  }

  void _bytes(List<int> data) {
    try {
      _text(
        encoding is Utf8Codec
            ? const Utf8Decoder(allowMalformed: true).convert(data)
            : encoding.decode(data),
      );
    } catch (error, stackTrace) {
      OTelErrorHandling.report(error, stackTrace);
    }
  }

  void _flushPending() {
    if (_pending.isNotEmpty) _line();
  }

  @override
  void write(Object? object) {
    _target.write(object);
    _text('$object');
  }

  @override
  void writeln([Object? object = '']) {
    _target.writeln(object);
    _text('$object\n');
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _target.writeAll(objects, separator);
    _text(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    _target.writeCharCode(charCode);
    _text(String.fromCharCode(charCode));
  }

  @override
  void add(List<int> data) {
    _target.add(data);
    _bytes(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) => _target.addStream(
        stream.map((data) {
          _bytes(data);
          return data;
        }),
      );

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _target.addError(error, stackTrace);

  @override
  Future<void> flush() {
    _flushPending();
    return _target.flush();
  }

  @override
  Future<void> close() {
    _flushPending();
    return _target.close();
  }

  @override
  Future<void> get done => _target.done;

  @override
  Encoding get encoding => _target.encoding;

  @override
  set encoding(Encoding encoding) => _target.encoding = encoding;

  @override
  String get lineTerminator => _target.lineTerminator;

  @override
  set lineTerminator(String lineTerminator) =>
      _target.lineTerminator = lineTerminator;

  @override
  bool get hasTerminal => _target.hasTerminal;

  @override
  int get terminalColumns => _target.terminalColumns;

  @override
  int get terminalLines => _target.terminalLines;

  @override
  bool get supportsAnsiEscapes => _target.supportsAnsiEscapes;

  @override
  IOSink get nonBlocking => _target.nonBlocking;
}
