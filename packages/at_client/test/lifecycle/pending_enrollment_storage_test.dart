import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// `PendingEnrollment.client`: a client it could not build is refused before
/// the approval is waited for, not after the approver has approved.
void main() {
  test(
      'a preference asking for no local store, with none passed, is refused '
      'before the approval is waited for', () async {
    var connectionsBuilt = 0;
    final pending = PendingEnrollment(
        atSign: Atsign('@pendingnone'),
        enrollmentId: 'e1',
        app: 'wavi',
        device: 'laptop',
        namespaces: const {'wavi': 'rw'},
        keys: InMemoryAtKeysIo(),
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

    await expectLater(
        () =>
            pending.client(AtClientPreference()..isLocalStoreRequired = false),
        throwsA(isA<ArgumentError>()));

    expect(connectionsBuilt, 0,
        reason: 'the approval wait opens a connection; refused only once it '
            'returns, the approver has approved an enrollment no client '
            'can open');
  });
}
