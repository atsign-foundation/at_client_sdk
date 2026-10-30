@Tags(['pq'])
library;

import 'dart:convert' show jsonDecode;

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
// ignore: implementation_imports
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A namespace key minted after a client started reaches that client at its
/// first write, from the conveyance record the minter stored before it
/// published.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.6, UC-A3.7
void main() {
  TestUtils.isolateStorage('nskey_fetch_on_miss_live_test');
  late String atSign;
  late AtClient owner;
  final runId = DateTime.now().microsecondsSinceEpoch;
  // NOTE: run-unique, so the minter below mints rather than adopting a key an
  // earlier run published, whose private nobody here holds.
  final namespace = 'fom$runId';

  /// Writes post-quantum and seeds nothing, so a namespace private reaches it
  /// only by conveyance.
  final writesWithoutSeeding = PqPosture(
    authenticationKeyAlgorithm: PqPosture.pqActive.authenticationKeyAlgorithm,
    dataSigningKeyAlgorithms: PqPosture.pqActive.dataSigningKeyAlgorithms,
    seedNamespaceKeys: false,
    keyExchangeMode: PqPosture.pqActive.keyExchangeMode,
    writesPqByDefault: true,
    configuresPqProviders: true,
    disallowLegacyEncryption: PqPosture.pqActive.disallowLegacyEncryption,
    mintLegacyMaterial: PqPosture.pqActive.mintLegacyMaterial,
    sealsToKeyAlgorithms: PqPosture.pqActive.sealsToKeyAlgorithms,
    keyEstablishmentAlgorithms: PqPosture.pqActive.keyEstablishmentAlgorithms,
  );

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    owner = (await TestUtils.initAtClient(atSign, namespace,
            atKeysIo: keysIo, posture: legacyPlusPqProviders))
        .atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  /// An enrollment of the atSign granted `rw` on [namespace] at [posture], its
  /// start finished.
  Future<({EnrolledClient enrolled, InMemoryAtKeysIo keys})> enrol(
      String role, PqPosture posture) async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final enrolled = await enrolAndAuthenticate(
      approver: owner,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: posture)
        ..namespace = namespace,
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: '$role-$runId',
      atKeysIo: io,
      namespaces: {namespace: 'rw'},
      storage: TestUtils.storage,
    );
    await (enrolled.client as AtClientImpl).pqBootstrap!.startupComplete;
    return (enrolled: enrolled, keys: io);
  }

  /// When the atServer created [key], by its own clock.
  Future<DateTime> createdAt(String key) async {
    final meta = await TestUtils.executeCommandAndParse(
        owner, 'llookup:meta:$key',
        auth: true);
    return DateTime.parse(
        (jsonDecode(meta!.trim()) as Map<String, dynamic>)['createdAt']
            as String);
  }

  test(
      'a client that started before the key was minted fetches the record '
      'waiting for it at its first write', () async {
    final reader = await enrol('reader', writesWithoutSeeding);
    // NOTE: the reader's listener is stopped, so no background sweep files the
    // record before the write does: what the write finds missing, it fetches.
    AtClientSecretSharing.forClient(reader.enrolled.client).stopListening();

    await enrol('minter', PqPosture.pqActive);
    final published =
        await PublishedNskeyKeyRing(owner).currentPublic(atSign, namespace);
    expect(published, isNotNull,
        reason: 'the minter seeds at its start, so the namespace has a key');

    final kpid = reader.enrolled.kpid;
    final waiting = [
      for (final key in await owner.getAtKeys(
          regex: EnvelopeAddressing.regexFor(kpid), useRemoteAtServer: true))
        if (key.namespace == namespace) '$key'
    ];
    expect(waiting, isNotEmpty,
        reason: 'the precondition: a conveyance record for the reader is on '
            'the atServer');
    final filing = NskeyPrivateFiling(keysIo: reader.keys, atSign: atSign);
    expect(await filing.read(namespace, published!.nskeyKid), isNull,
        reason: 'the precondition: the reader has filed nothing, so the write '
            'below misses');

    final advertised = await createdAt('public:__nskey.$namespace$atSign');
    for (final record in waiting) {
      expect((await createdAt(record)).isBefore(advertised), isTrue,
          reason: 'the atServer stored the conveyance record $record before '
              'the advertisement, by its own clock, so publishing is the '
              'commit point');
    }

    final key = AtKey()
      ..key = 'fom$runId'
      ..namespace = namespace
      ..sharedBy = atSign;
    expect(await reader.enrolled.client.put(key, 'fetched-on-miss'), isTrue,
        reason: 'the write misses the private, fetches the record and goes on; '
            'without the fetch it asks and fails');
    expect((await reader.enrolled.client.get(key)).value, 'fetched-on-miss');
    expect(await filing.read(namespace, published.nskeyKid), isNotNull,
        reason: 'and the fetch filed the private it carried');
  });
}
