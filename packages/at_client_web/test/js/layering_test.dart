@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

String _read(String path) => File(path).readAsStringSync();

bool _importsInterop(String path) =>
    RegExp(r"^import 'dart:js_interop[^']*';", multiLine: true)
        .hasMatch(_read(path));

void main() {
  test('the bridge is the only file in lib/src/js that imports dart:js_interop',
      () {
    final files = Directory('lib/src/js')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.dart'))
        .toList();
    expect([
      for (final f in files)
        if (_importsInterop(f)) f.split('/').last
    ], [
      'bridge.dart'
    ]);
  });

  test('the session, adapter and shared text layers take typed Dart', () {
    for (final path in [
      'lib/src/js/js_session.dart',
      'lib/src/collections/js_collections_adapter.dart',
      'lib/src/log_text.dart',
      'lib/src/session/session_opener.dart',
      'lib/src/session/keys_session_opener.dart',
      'lib/src/session/passkey_session_opener.dart',
      'lib/src/session/session_namespace.dart',
    ]) {
      expect(_importsInterop(path), isFalse, reason: path);
      expect(_read(path), isNot(contains("package:web/")), reason: path);
    }
  });

  test('the session opener files import no browser-only library', () {
    for (final path in [
      'lib/src/session/session_opener.dart',
      'lib/src/session/keys_session_opener.dart',
      'lib/src/session/passkey_session_opener.dart',
    ]) {
      expect(_read(path), isNot(contains('at_lookup_web')), reason: path);
      expect(_read(path), isNot(contains('web_passkey_entry')), reason: path);
    }
  });

  test('the bridge opens sessions only through the SessionOpener interface',
      () {
    final bridge = _read('lib/src/js/bridge.dart');
    for (final name in [
      'session_transport',
      'passkey_login',
      'portalSession('
    ]) {
      expect(bridge, isNot(contains(name)), reason: name);
    }
  });
}
