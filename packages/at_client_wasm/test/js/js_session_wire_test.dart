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
}
