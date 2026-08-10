// The substrate and the chain are deliberately marked @experimental and will
// be reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show envelopePayloadOf, jwsEnvelopeVersion, signEnvelope, signableTextOf;
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
        await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');

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
        await PqSigningChain(parentClient).signLinkFor(parent, 'never-existed');

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
        await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
    await PqSigningChain(childClient).publishLink('child-1', link!);

    expect(remoteData[uri], publishedKey,
        reason: 'the link is additive metadata — rewriting the record must '
            'not disturb the signing key every verifier resolves');

    final read = await PqSigningChain(childClient).readLink('child-1');
    expect(read, isNotNull);
    expect(read!['enrollmentId'], 'parent-1');
  });

  test('a published link verifies against the parent it names', () async {
    final parentClient = client('parent-1');
    final parent = await registered(parentClient);
    final childClient = client('child-1');
    await registered(childClient);

    final link =
        await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
    await PqSigningChain(childClient).publishLink('child-1', link!);

    final read = await PqSigningChain(childClient).readLink('child-1');

    // A third party verifying: it resolves the signer from the envelope's own
    // claim and checks against that enrollment's published _apsk.
    final verifier = AtClientSecretSharing.forClient(client('verifier-1'));
    await expectLater(
        verifier.verifyEnvelopeSignature(read!, signerAtSign: atSign),
        completes);
  });

  group('the child consuming a conveyed link', () {
    /// Puts [link] into [child]'s store the way a substrate sweep would.
    Future<void> convey(
        AtClientSecretSharing child, Map<String, Object?> link) async {
      await child.secretStore.putSecret(
          Secret(
              namespace: 'buzz',
              name: PqSigningChain.linkSecretName,
              value: PqSigningChain.encodeLink(link)),
          allowReservedName: true);
    }

    test('publishes a link conveyed to it', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await convey(child, link!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);
      final published = await PqSigningChain(childClient).readLink('child-1');
      expect(published?['signature'], link['signature']);
    });

    test('reads its own record exactly once while publishing', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await convey(child, link!);

      clearInteractions(childClient);
      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);

      expect(apskGetCount(childClient, atSign, 'child-1'), 1,
          reason: 'the key the link vouches for, the already-published '
              'check and the value republished must come from ONE '
              'snapshot — separate reads let the record change between '
              'them');
    });

    test('writes nothing when nobody vouched for it', () async {
      final childClient = client('child-1');
      await registered(childClient);

      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'this runs at every client start, so an enrollment that '
              'will never have a link must cost nothing');
      expect(await PqSigningChain(childClient).readLink('child-1'), isNull);
    });

    test('refuses a link conveyed for a different enrollment', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      await registered(client('sibling-1'));
      final childClient = client('child-1');
      final child = await registered(childClient);

      // A link genuinely signed by the parent, but vouching for a sibling.
      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'sibling-1');
      await convey(child, link!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'the link says which enrollment it vouches for, and '
              'stamping it on another would advertise a chain hop that was '
              'never made');
      expect(await PqSigningChain(childClient).readLink('child-1'), isNull);
    });

    test('refuses a link whose signature does not verify', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await convey(child, {...link!, 'signature': 'not-the-signature'});

      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'publishing a link no verifier can follow would advertise '
              'this enrollment as chained when it is not');
      expect(await PqSigningChain(childClient).readLink('child-1'), isNull);
    });

    test('is idempotent across restarts', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await convey(child, link!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);
      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'it runs at every start, and rewriting an unchanged record '
              'each time would be traffic for nothing');
    });
  });

  group('anchoring to the signing root', () {
    /// A client holding the root private, as a privileged enrollment does
    /// once it has been conveyed one.
    Future<MockAtClient> rootHolder(String enrollmentId, Uint8List secret,
        {AtKeys? seedInto}) async {
      final c = client(enrollmentId);
      final io = InMemoryAtKeysIo();
      await io.write(atSign, seedInto ?? AtKeys());
      await PqSigningRoot(c, keysIo: io).store(atSign, secret);
      when(() => c.atKeysIo).thenReturn(io);
      await registered(c);
      return c;
    }

    test('a privileged holder anchors itself, and only once', () async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = await rootHolder('priv-1', pair.secretKey);

      expect(
          await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async => true, keysIo: c.atKeysIo),
          isTrue);

      final link = await PqSigningChain(c).readRootLink('priv-1');
      expect(link, isNotNull);
      expect(link!['alg'], PqSigningChain.rootLinkAlgo);

      // The signature is over the same canonical text a verifier rebuilds,
      // checked against the root's public half rather than merely present.
      expect(
          await MlDsa65PureDartAlgo().verifyBytes(
            Uint8List.fromList(utf8.encode(signableTextOf(link['payload']))),
            signature: base64Decode(link['signature'] as String),
            publicKey: pair.publicKey,
          ),
          isTrue);

      expect(
          await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async => true, keysIo: c.atKeysIo),
          isFalse,
          reason: 'this runs at every start, so an anchored enrollment must '
              'not rewrite its record each time');
    });

    test('holding the private is not enough without the privilege', () async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = await rootHolder('priv-1', pair.secretKey);

      expect(
          await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async => false, keysIo: c.atKeysIo),
          isFalse,
          reason: 'only the fully privileged class carries a root link; '
              'possession and privilege should never diverge, and if they do '
              'the grant is what decides');
      expect(await PqSigningChain(c).readRootLink('priv-1'), isNull);
    });

    test('an enrollment holding no root private anchors nothing', () async {
      final c = client('scoped-1');
      final io = InMemoryAtKeysIo();
      await io.write(atSign, AtKeys());
      when(() => c.atKeysIo).thenReturn(io);
      await registered(c);

      var privilegeChecked = false;
      expect(
          await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async {
            privilegeChecked = true;
            return true;
          }, keysIo: io),
          isFalse);
      expect(privilegeChecked, isFalse,
          reason: 'establishing privilege costs a round trip, so the local '
              'possession check has to come first — otherwise every client '
              'pays for it at every start');
    });

    test('reads its own record exactly once while anchoring', () async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = await rootHolder('priv-1', pair.secretKey);

      clearInteractions(c);
      expect(
          await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async => true, keysIo: c.atKeysIo),
          isTrue);

      expect(apskGetCount(c, atSign, 'priv-1'), 1,
          reason: 'the key vouched for, the existing-link check and the '
              'value republished must come from ONE snapshot — separate '
              'reads let the record change between them');
    });

    test('a root link and a chain link coexist on one record', () async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      final c = await rootHolder('priv-1', pair.secretKey);
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);

      final chain =
          await PqSigningChain(parentClient).signLinkFor(parent, 'priv-1');
      await PqSigningChain(c).publishLink('priv-1', chain!);
      await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async => true, keysIo: c.atKeysIo);

      expect(await PqSigningChain(c).readLink('priv-1'), isNotNull,
          reason: 'writing one link must not drop the other — they are '
              'separate fields on one record, and a walk may want either');
      expect(await PqSigningChain(c).readRootLink('priv-1'), isNotNull);
    });
  });

  group('walking the chain', () {
    late MockAtClient verifierClient;
    late AtClientSecretSharing verifier;

    setUp(() async {
      verifierClient = client('verifier-1');
      verifier = AtClientSecretSharing.forClient(verifierClient);
    });

    /// Publishes the atSign's signing root and returns its key pair.
    Future<({Uint8List publicKey, Uint8List secretKey})> publishRoot() async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      remoteData['public:${PqSigningRoot.recordName}$atSign'] = jsonEncode({
        'v': 1,
        'keys': [base64Encode(pair.publicKey)],
        'successor': null
      });
      return pair;
    }

    Future<MockAtClient> anchored(String id, Uint8List secret) async {
      final c = client(id);
      final io = InMemoryAtKeysIo();
      await io.write(atSign, AtKeys());
      await PqSigningRoot(c, keysIo: io).store(atSign, secret);
      when(() => c.atKeysIo).thenReturn(io);
      await registered(c);
      await PqSigningChain(c).publishOwnRootLink(isFullyPrivileged: () async => true, keysIo: io);
      return c;
    }

    test('reports anchored when the walk reaches a verified root link',
        () async {
      final pair = await publishRoot();
      await anchored('priv-1', pair.secretKey);

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'priv-1');

      expect(result.verdict, ChainVerdict.anchored);
      expect(result.path, ['priv-1']);
    });

    test('climbs a chain link to an anchored parent', () async {
      final pair = await publishRoot();
      final parentClient = await anchored('priv-1', pair.secretKey);
      final parent = AtClientSecretSharing.forClient(parentClient);
      final childClient = client('child-1');
      await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await PqSigningChain(childClient).publishLink('child-1', link!);

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'child-1');

      expect(result.verdict, ChainVerdict.anchored);
      expect(result.path, ['child-1', 'priv-1'],
          reason: 'the walk is what makes the chain self-describing: nothing '
              'published the fact that priv-1 approved child-1');
    });

    test('reports unsigned when the enrollment publishes nothing', () async {
      final c = client('lonely-1');
      await registered(c);

      final result = await PqSigningChain(verifierClient).verifyChain(
          verifier, 'lonely-1');

      expect(result.verdict, ChainVerdict.unsigned,
          reason: 'this is the ordinary state during the changeover, and it '
              'must be distinguishable from a link that failed');
    });

    test('reports chained when the walk runs out below the root', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await PqSigningChain(childClient).publishLink('child-1', link!);

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'child-1');

      expect(result.verdict, ChainVerdict.chained);
      expect(result.path, ['child-1', 'parent-1']);
    });

    test('climbs a JWS-wrapped chain link the same way', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      await registered(childClient);

      // The same payload the version-1 link carries, re-signed in the JWS
      // wrapper — what a flipped producer will convey. The walk must read
      // the signer from the protected header's kid and the payload out of
      // base64url, or the chain dead-ends at its first version-2 link.
      final v1 = await PqSigningChain(parentClient).signLinkFor(
          parent, 'child-1');
      final link = signEnvelope(envelopePayloadOf(v1!),
          keys: parent.signingKeys,
          enrollmentId: 'parent-1',
          version: jwsEnvelopeVersion);
      await PqSigningChain(childClient).publishLink('child-1', link);

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'child-1');

      expect(result.verdict, ChainVerdict.chained);
      expect(result.path, ['child-1', 'parent-1']);
    });

    test('reports broken, not chained, for a link that does not verify',
        () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await PqSigningChain(childClient).publishLink('child-1',
          {...link!, 'signature': base64Encode(utf8.encode('forged'))});

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'child-1');

      expect(result.verdict, ChainVerdict.broken,
          reason: 'an absent link means nobody vouched yet; a bad one means '
              'something claimed to and the claim does not hold — folding the '
              'second into the first would hide it');
    });

    test('reports broken for a root link that does not verify', () async {
      await publishRoot();
      // Anchored with a DIFFERENT root private than the one published.
      final other = await MlDsa65PureDartAlgo().generateKeyPair();
      await anchored('priv-1', other.secretKey);

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'priv-1');

      expect(result.verdict, ChainVerdict.broken,
          reason: 'the anchor is only worth anything if it is checked against '
              'the root the atSign actually published');
    });

    test('terminates on a cycle rather than walking forever', () async {
      final a = client('loop-a');
      final sharingA = await registered(a);
      final b = client('loop-b');
      final sharingB = await registered(b);

      // Each vouches for the other: individually well-formed, jointly a ring.
      final linkForB = await PqSigningChain(a).signLinkFor(sharingA, 'loop-b');
      await PqSigningChain(b).publishLink('loop-b', linkForB!);
      final linkForA = await PqSigningChain(b).signLinkFor(sharingB, 'loop-a');
      await PqSigningChain(a).publishLink('loop-a', linkForA!);

      final result =
          await PqSigningChain(verifierClient).verifyChain(verifier, 'loop-a');

      expect(result.verdict, ChainVerdict.broken,
          reason: 'the chain is built from records a compromised enrollment '
              'partly controls, so a ring is an input to expect');
      expect(result.reason, contains('revisits'));
    });
  });

  test('a link forged onto another enrollment fails verification', () async {
    final impostorClient = client('impostor-1');
    final impostor = await registered(impostorClient);
    final childClient = client('child-1');
    await registered(childClient);

    // The impostor signs a perfectly well-formed link for child-1 — anyone
    // can — but then claims it came from parent-1.
    final link =
        await PqSigningChain(impostorClient).signLinkFor(impostor, 'child-1');
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

/// How many of [c]'s remote gets fetched [enrollmentId]'s own `_apsk`.
int apskGetCount(MockAtClient c, String atSign, String enrollmentId) {
  final uri = PqSigningChain.apskUri(atSign, enrollmentId);
  final captured = verify(() => c.get(captureAny(),
          getRequestOptions: any(named: 'getRequestOptions')))
      .captured;
  return captured.where((k) => k.toString() == uri).length;
}
