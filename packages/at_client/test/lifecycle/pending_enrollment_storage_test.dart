import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// `PendingEnrollment.client`: a client it could not build is refused before
/// the approval is waited for, not after the approver has approved.
void main() {
  test(
      'a preference asking for no local store, with none passed, is refused '
      'before the approval is waited for', () async {
    const atSign = '@alice🛠';
    var connectionsBuilt = 0;
    // NOTE: a real pending enrollment, so a wait that started would get as far
    // as opening a connection.
    final keys = InMemoryAtKeysIo.holding(
        atSign,
        AtKeys(atsign: Atsign(atSign), keysList: [
          for (final (role, key) in [
            (
              CryptographicMaterialRole.privateAuthentication,
              demo.pkamPrivateKeyMap[atSign]!
            ),
            (
              CryptographicMaterialRole.publicAuthentication,
              demo.pkamPublicKeyMap[atSign]!
            ),
          ])
            CryptographicMaterial(
                keyId: 'auth:rsa2048:1',
                enrollmentId: 'e1',
                role: role,
                algorithm: CryptographicMaterialAlgorithm.rsa2048,
                bytes: AtBytes.fromString(key),
                createdAt: DateTime.utc(2026),
                status: CryptographicMaterialStatus.pending),
        ]));
    final pending = PendingEnrollment(
        atSign: Atsign(atSign),
        enrollmentId: 'e1',
        app: 'wavi',
        device: 'laptop',
        namespaces: const {'wavi': 'rw'},
        keys: keys,
        rootDomain: AtRootDomain.atsignDomain,
        signingAlgo: SigningAlgoType.rsa2048,
        keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
        lookUps: ({
          required String atSign,
          required AtRootDomain rootDomain,
          required AtAuthenticator? authenticator,
          SecondaryAddressFinder? secondaryAddressFinder,
          Map<String, dynamic> clientConfig = const {},
        }) {
          connectionsBuilt++;
          throw StateError('no connection is expected');
        });

    Object? refusal;
    try {
      await pending.client(AtClientPreference()..isLocalStoreRequired = false,
          retryInterval: const Duration(milliseconds: 1), maxRetries: 1);
    } catch (e) {
      refusal = e;
    }

    expect(connectionsBuilt, 0,
        reason: 'the approval wait opens a connection; refused only once it '
            'returns, the approver has approved an enrollment no client '
            'can open');
    expect(refusal, isA<ArgumentError>());
  });
}
