import 'dart:async';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// `AtClientImpl.create` against a client of the same principal whose
/// `stop()` has begun: refused while the teardown runs, a new client once it
/// has finished.
void main() {
  const atSign = '@createduringstop';

  AtClientPreference prefs() => AtClientPreference()
    ..namespace = 'wavi'
    ..rootDomain = 'test.atsign.wtf';

  Future<AtClient> create(
          {required RemoteSecondary remote,
          required AtClientStorage storage}) =>
      AtClientImpl.create(atSign, 'wavi', prefs(),
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(prefs()),
          remoteSecondary: remote,
          atKeysIo: noKeysFor(atSign),
          storage: storage);

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
  });

  test('a create() while that client is stopping is refused', () async {
    final storage =
        InMemoryAtClientStorage(atSign: atSign, closedByClient: true);
    final remote = MockRemoteSecondary();
    final reached = Completer<void>();
    final gate = Completer<void>();
    when(() => remote.closeConnection()).thenAnswer((_) async {
      if (!reached.isCompleted) reached.complete();
      await gate.future;
    });
    final client = await create(remote: remote, storage: storage);

    final stopping = client.stop();
    await reached.future;
    Object? outcome;
    try {
      outcome = await create(remote: remote, storage: storage);
    } catch (e) {
      outcome = e;
    }
    gate.complete();
    await stopping;

    expect(
        outcome,
        isA<StateError>()
            .having((e) => e.message, 'message', contains('is stopping')),
        reason: 'a client part way through stop() is refused, not restarted '
            'and handed out');
    expect(AtClientImpl.atClientInstanceMap.values, isNot(contains(client)),
        reason: 'the teardown ran to its end and removed the client');
  });

  test('a create() after stop() has finished builds a new client', () async {
    final first = await create(
        remote: MockRemoteSecondary(),
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true));
    await first.stop();

    final second = await create(
        remote: MockRemoteSecondary(),
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true));

    expect(identical(second, first), isFalse,
        reason: 'a finished stop() leaves nothing cached to hand back');
    expect((second as AtClientImpl).isStopped, isFalse);
  });
}
