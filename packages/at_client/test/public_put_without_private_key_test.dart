import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/sqlite.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/mocks.dart';

/// A public write is signed with the atSign's encryption private key. A
/// client whose key source and keystore hold none is refused with the
/// transformer's own message, which names what is missing, rather than with
/// the keystore's record name.
void main() {
  const atSign = '@alice🛠';
  const enrollmentId = 'e1';

  Future<AtClient> clientOn(InMemoryAtKeysIo keys) async {
    // An enrolled client asks the atServer about its enrollment before a
    // write, so the mocked remote answers with a record granting the
    // namespace.
    final remote = MockRemoteSecondary();
    when(() =>
            remote.executeCommand(any(that: startsWith('enroll:fetch')),
                auth: any(named: 'auth')))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  'appName': 'unit',
                  'deviceName': 'test',
                  'namespace': {'unit': 'rw'},
                })}');
    final client = await AtClientImpl.create(
        atSign,
        'unit',
        AtClientPreference()
          ..namespace = 'unit'
          ..rootDomain = 'test.atsign.wtf',
        remoteSecondary: remote,
        storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
        atKeysIo: keys);
    client.syncService = MockSyncService();
    return client;
  }

  AtKey publicKey() =>
      AtKey.public('greeting', namespace: 'unit', sharedBy: atSign).build();

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  test(
      'a public put with no encryption private key anywhere is refused, and '
      'says why', () async {
    // Typed APKAM material under the enrollment and nothing else: the shape a
    // post-quantum activation that opted out of legacy material leaves.
    final client = await clientOn(
        keysHoldingApkam(atSign, enrollmentId, RsaKeyPair.generate()));

    await expectLater(
        () => client.putText(publicKey(), 'hello'),
        throwsA(predicate(
            (e) => e.toString().contains('Failed to sign the public data'))),
        reason: 'the refusal names the signing, which is what a caller can act '
            'on; the keystore\'s "privatekey:privatekey does not exist" is not');
  });

  test(
      'control: with the encryption keypair filed, the same put signs and '
      'lands', () async {
    final client = await clientOn(await keyfileHolding(atSign,
        encryptionKeyPair: RsaKeyPair.generate(),
        selfEncryptionKey: AESKey.generate(32).key,
        io: keysHoldingApkam(atSign, enrollmentId, RsaKeyPair.generate())));

    final response = await client.putText(publicKey(), 'hello');
    expect(response.response, isNotEmpty);
  });
}
