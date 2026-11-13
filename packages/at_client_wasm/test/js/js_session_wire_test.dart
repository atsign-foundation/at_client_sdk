import 'dart:convert';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:at_client_wasm/src/js/js_session.dart';
import 'package:test/test.dart';

import '../session/wire_fakes.dart';
import '../test_utils.dart';

void main() {
  late Wire wire;
  late AtClientJsSession session;

  setUp(() async {
    wire = Wire();
    final client = await portalSession(
        atSign: '@alice',
        app: 'wavi',
        keys: classicalAtKeys(),
        transport: (
          lookUps: wire.lookUps,
          finder: FixedSecondaryAddressFinder('atserver.test', 1)
        ));
    session = AtClientJsSession(client, namespace: 'wavi');
  });

  tearDown(() async {
    await session.close();
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
  });

  test('put sends one update for <key>.<namespace>@<atSign>', () async {
    wire.answer = (command) => command.startsWith('update') ? 'data:1' : null;

    await session.put(const JsKey('k'), 'v');

    expect(wire.commands.where((c) => c.startsWith('update')).single,
        contains('k.wavi@alice'));
  });

  test('get of a key the atServer does not hold is null', () async {
    // at_lookup throws the atServer's AT0015 as a KeyNotFoundException and
    // AtClientImpl.get rethrows it as an AtKeyNotFoundException.
    wire.answer = (command) => throw KeyNotFoundException('absent');

    expect(await session.get(const JsKey('absent')), isNull);
    expect(wire.commands, contains(contains('absent')));
  });

  test('put of bytes then get returns equal bytes', () async {
    final bytes = Uint8List.fromList([0, 1, 2, 250, 251, 255, 128, 7, 9]);
    String? stored;
    String? iv;
    wire.answer = (command) {
      if (command.startsWith('update')) {
        iv = RegExp(r'ivNonce:([^:]+)').firstMatch(command)?.group(1);
        stored = command.substring(command.lastIndexOf(' ') + 1).trim();
        return 'data:1';
      }
      if (command.startsWith('llookup') || command.startsWith('lookup')) {
        return 'data:${jsonEncode({
              'key': '@alice:k.wavi@alice',
              'data': stored,
              'metaData': {'isBinary': true, 'isEncrypted': true, 'ivNonce': iv}
            })}';
      }
      return null;
    };

    await session.put(const JsKey('k'), bytes);
    final got = await session.get(const JsKey('k'));

    expect(got, isA<Uint8List>());
    expect(got, bytes);
  });
}
