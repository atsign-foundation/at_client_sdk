import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../test_utils/ml_dsa_keyfile.dart';

/// A client is obtainable with no atServer reachable, and serves everything
/// its local storage holds. The client lifecycle's ruling that `open` works
/// offline rests on this; the measurement it records is in
/// `docs/projects/client-lifecycle/design.md`.
void main() {
  const atSign = '@offlineopen';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('offline_open_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  /// A loopback port nothing listens on, so a connect to it is refused at
  /// once rather than left to time out. Bound and released here instead of
  /// picking a number, because a number is a guess about this machine.
  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  test(
      'a client builds, writes and reads with no atServer reachable, and '
      'stops', () async {
    final preference = AtClientPreference()
      ..rootDomain = InternetAddress.loopbackIPv4.address
      ..rootPort = await refusedPort()
      ..hiveStoragePath = dir.path
      ..namespace = 'offline';

    final built = Stopwatch()..start();
    final client = await buildAtClient(
        atSign: atSign,
        namespace: 'offline',
        preference: preference,
        atKeysIo: await typedKeyfile(atSign, enrollmentId: 'primary'));
    built.stop();
    // Generous on purpose: this pins that the build awaits no network round
    // trip, and a build that did would wait out the 30 s connect budget or
    // throw, not land a few seconds late. Measured at 52 to 57 ms.
    expect(built.elapsed, lessThan(const Duration(seconds: 30)),
        reason: 'building a client must not wait on the atServer');

    final lookUp = client.getRemoteSecondary()!.atLookUp as AtLookupMuxable;
    expect(lookUp.isConnectionAvailable(), isFalse,
        reason: 'nothing connected during the build, so the client has no '
            'connection to report as authenticated');

    final key =
        AtKey.self('phone', namespace: 'offline', sharedBy: atSign).build();
    expect(await client.put(key, 'offline value'), isTrue,
        reason: 'a write lands in local storage and queues for sync');
    expect((await client.get(key)).value, 'offline value',
        reason: 'the read is served from local storage');

    await client.stop();
    expect(client.isStopped, isTrue);
  });
}
