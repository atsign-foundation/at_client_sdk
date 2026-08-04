// The substrate and the chain are deliberately marked @experimental and will
// be reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

/// The approval chain link: the enrollment that approved a device signs that
/// device's APKAM public key, so a verifier can walk upward from any key to
/// the atSign's signing root without an approval graph being published
/// anywhere.
///
/// The awkward part the design has to work around is that the signer is not a
/// permitted writer: `_apsk` takes writes only from its own enrollment's
/// connection. So the parent signs, conveys, and the child publishes.
void main() {
  const atSign = '@alice';
  late Map<String, String> remoteData;
  // The link rides appMetadata, so this fixture has to round-trip metadata as
  // well as values — shared across clients, since the parent writes the record
  // the child later reads.
  late Map<String, Metadata> remoteMetadata;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
  });

  MockAtClient client(String enrollmentId) => buildRemoteBackedMockClient(
      atSign: atSign,
      enrollmentId: enrollmentId,
      remoteData: remoteData,
      remoteMetadata: remoteMetadata);

  /// A registered enrollment: its `_apsk` is published, so anything it signs
  /// can be verified and it can itself be vouched for.
  Future<AtClientSecretSharing> registered(MockAtClient c) async {
    final sharing = AtClientSecretSharing.forClient(c);
    await sharing.register();
    return sharing;
  }

  test('the signed link names the child and the key that was published',
      () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    await registered(client('child-1'));

    final link =
        await PqSigningChain.signLinkFor(parentClient, parent, 'child-1');

    expect(link, isNotNull);
    final payload = link!['payload'] as Map;
    expect(payload['childEnrollmentId'], 'child-1');
    expect(payload['apkamPublicKey'],
        remoteData[PqSigningChain.apskUri(atSign, 'child-1')],
        reason: 'the key signed has to be the one the atServer published, or '
            'a verifier resolving _apsk would be checking a signature over a '
            'different key than the one it holds');
    expect(link['enrollmentId'], 'parent-1',
        reason: 'the envelope names its signer, which is what lets a verifier '
            'walk upward without any approval graph being published');
  });

  test('a link for an enrollment with no published key is skipped, not fatal',
      () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);

    final link =
        await PqSigningChain.signLinkFor(parentClient, parent, 'never-existed');

    expect(link, isNull,
        reason: 'the approval has already happened on the atServer by this '
            'point, so failing here would abort a completed enrollment over '
            'an additive field; an unsigned enrollment is tolerated');
  });

  test('the child publishes the link onto its own key, value untouched',
      () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    final childClient = client('child-1');
    await registered(childClient);

    final uri = PqSigningChain.apskUri(atSign, 'child-1');
    final publishedKey = remoteData[uri];

    final link =
        await PqSigningChain.signLinkFor(parentClient, parent, 'child-1');
    await PqSigningChain.publishLink(childClient, 'child-1', link!);

    expect(remoteData[uri], publishedKey,
        reason: 'the link is additive metadata — rewriting the record must '
            'not disturb the signing key every verifier resolves');

    final read = await PqSigningChain.readLink(childClient, 'child-1');
    expect(read, isNotNull);
    expect(read!['enrollmentId'], 'parent-1');
  });

  test('a published link verifies against the parent it names', () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    final childClient = client('child-1');
    await registered(childClient);

    final link =
        await PqSigningChain.signLinkFor(parentClient, parent, 'child-1');
    await PqSigningChain.publishLink(childClient, 'child-1', link!);

    final read = await PqSigningChain.readLink(childClient, 'child-1');

    // A third party verifying: it resolves the signer from the envelope's own
    // claim and checks against that enrollment's published _apsk.
    final verifier = AtClientSecretSharing.forClient(client('verifier-1'));
    await expectLater(
        verifier.verifyEnvelopeSignature(read!, signerAtSign: atSign),
        completes);
  });

  test('a link forged onto another enrollment fails verification', () async {
    final impostorClient = client('impostor-1');
    final impostor = await registered(impostorClient);
    final childClient = client('child-1');
    await registered(childClient);

    // The impostor signs a perfectly well-formed link for child-1 — anyone
    // can — but then claims it came from parent-1.
    final link =
        await PqSigningChain.signLinkFor(impostorClient, impostor, 'child-1');
    await registered(client('parent-1'));
    final forged = Map<String, Object?>.from(link!)
      ..['enrollmentId'] = 'parent-1';

    final verifier = AtClientSecretSharing.forClient(client('verifier-1'));
    await expectLater(
        verifier.verifyEnvelopeSignature(forged, signerAtSign: atSign),
        throwsA(isA<Exception>()),
        reason: 'the chain is only self-describing because a claimed parent '
            'is checked against that parent\'s own published key — otherwise '
            'any enrollment could name any other as its approver');
  });
}
