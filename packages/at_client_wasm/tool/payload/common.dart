import 'package:at_client/at_client.dart';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The fixed app every payload variant runs: build a client over [storage],
/// write one key and read it back.
///
/// The query-string guard keeps dart2wasm from proving the client unreachable
/// and tree-shaking it away.
Future<void> exercise(AtClientStorage storage) async {
  if (!web.window.location.search.contains('run')) return;
  final client = await buildAtClient(
      atSign: '@payload',
      namespace: 'payload',
      preference: AtClientPreference()..namespace = 'payload',
      storage: storage);
  final key = AtKey.self('k', namespace: 'payload').build();
  await client.put(key, 'v');
  web.console.log((await client.get(key)).value.toString().toJS);
}
