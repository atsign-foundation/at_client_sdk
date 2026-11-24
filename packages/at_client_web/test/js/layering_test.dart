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
      'lib/src/session/at_client_session.dart',
      'lib/src/collections/at_collection_adapter.dart',
      'lib/src/log_text.dart',
      'lib/src/session/session_options.dart',
      'lib/src/session/session_namespace.dart',
    ]) {
      expect(_importsInterop(path), isFalse, reason: path);
      expect(_read(path), isNot(contains("package:web/")), reason: path);
    }
  });

  test('the session options import no browser-only library', () {
    final options = _read('lib/src/session/session_options.dart');
    expect(options, isNot(contains('at_lookup_web')));
    expect(options, isNot(contains('web_passkey_entry')));
  });

  test('the bridge opens sessions through one private function and no opener',
      () {
    final bridge = _read('lib/src/js/bridge.dart');
    expect(
        RegExp(r'Future<Session> _openSession\(').allMatches(bridge).length, 1);
    for (final call in ['portalSession(', 'passkeyLogin(']) {
      expect(RegExp(RegExp.escape(call)).allMatches(bridge).length, 1,
          reason: call);
    }
    expect(bridge, isNot(contains('SessionOpener')));
    expect([
      for (final f in Directory('lib/src/session').listSync().whereType<File>())
        if (f.path.contains('opener')) f.path
    ], isEmpty);
  });

  test('only the session compiles the subscribe regex', () {
    expect(_read('lib/src/js/bridge.dart'), isNot(contains('RegExp(')));
    expect(
        RegExp(r'RegExp\(regex\)')
            .allMatches(_read('lib/src/session/at_client_session.dart'))
            .length,
        1);
  });

  test('the session and the adapter raise structured exceptions, not text', () {
    final finishedText = [
      // A collection exception whose second argument is a string literal.
      RegExp(r"CollectionException\(\s*[\w.]+,\s*'"),
      // An argument exception whose first argument reads as a sentence.
      RegExp(r"InvalidArgumentException\(\s*'[^']*\s"),
    ];
    for (final path in [
      'lib/src/session/at_client_session.dart',
      'lib/src/session/session_namespace.dart',
      'lib/src/collections/at_collection_adapter.dart',
    ]) {
      for (final pattern in finishedText) {
        expect(pattern.hasMatch(_read(path)), isFalse,
            reason: '$path carries message text for JS');
      }
    }
  });
}
