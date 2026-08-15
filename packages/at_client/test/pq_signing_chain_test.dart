// The substrate and the chain are deliberately marked @experimental and will
// be reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope, signableTextOf;
import 'package:at_client/at_client_mixins.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/envelope_tamper.dart';
import 'test_utils/remote_backed_client.dart';

/// [envelope] with its signature replaced by one that cannot verify.
///
/// Reaches inside the `signatures` array, which the type now makes the only
/// way to write it: before [SignedEnvelope] existed, spreading a top-level
/// `'signature'` member over a Map was the obvious spelling, and it left the
/// real signature untouched in the entry the verifier reads — so the forgery
/// verified and the test passed for the absence of a forgery.
SignedEnvelope withForgedSignature(SignedEnvelope envelope) =>
    envelope.withEntryMember('signature', b64u('forged'));

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
    final payload = link!.payload as Map;
    expect(payload['childEnrollmentId'], 'child-1');
    expect(payload['apkamPublicKey'],
        remoteData[PqSigningChain.apskUri(atSign, 'child-1')],
        reason: 'the key signed has to be the one the atServer published, or '
            'a verifier resolving _apsk would be checking a signature over a '
            'different key than the one it holds');
    expect(link.signerEnrollmentId, 'parent-1',
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
    expect(read!.signerEnrollmentId, 'parent-1');
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
        AtClientSecretSharing child, SignedEnvelope link) async {
      await child.secretStore.putSecret(
          Secret(
              namespace: 'buzz',
              name: PqSigningChain.linkSecretName,
              value: PqSigningChain.encodeLink(link.toJson())),
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
      expect(published, link,
          reason: 'the link published is the one conveyed, byte for byte');
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

    test('replaces an existing link with a DIFFERENT one conveyed later',
        () async {
      // The arm that catches an already-published check comparing the wrong
      // thing. The signature lives inside the envelope's `signatures` array,
      // so a check reading a top-level `['signature']` gets null from both
      // sides, matches every time, and skips the write — and the skip is the
      // same `return false` as "already published", so nothing looks wrong.
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      final child = await registered(childClient);

      final first =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await convey(child, first!);
      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);

      // A second, genuinely different link for the same child: another
      // privileged enrollment re-vouches for it.
      final otherClient = client('parent-2');
      final other = await registered(otherClient);
      final second =
          await PqSigningChain(otherClient).signLinkFor(other, 'child-1');
      expect(second, isNot(first),
          reason: 'differential guard: if the two links were equal this test '
              'would compare a case with itself and pass either way');
      await convey(child, second!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue,
          reason: 'a different link is new work, not a repeat');
      expect(await PqSigningChain(childClient).readLink('child-1'), second);
    });

    test('writes nothing when the same link is conveyed twice', () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await convey(child, link!);
      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);

      await convey(child, link);
      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'the other half of the pair above: republishing the same '
              'link on every start would rewrite the record for nothing');
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
      await convey(child, withForgedSignature(link!));

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

  group('the child consuming a conveyed ROOT link', () {
    // This path had no test at all. It is the flavour a scoped enrollment
    // gets — it cannot hold the root private, so a privileged holder signs
    // and conveys, exactly as with a chain link — and it shares the
    // already-published check with that one.

    Future<void> conveyRoot(
        AtClientSecretSharing child, Map<String, Object?> link) async {
      await child.secretStore.putSecret(
          Secret(
              namespace: 'buzz',
              name: PqSigningChain.rootLinkSecretName,
              value: PqSigningChain.encodeLink(link)),
          allowReservedName: true);
    }

    Future<({Uint8List publicKey, Uint8List secretKey})> publishRoot() async {
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      remoteData['public:${PqSigningRoot.recordName}$atSign'] =
          jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(pair.publicKey))
      ]));
      return pair;
    }

    /// Publishes a record advertising [active] beside a retired [retired].
    Future<void> publishRotatedRoot({
      required Uint8List active,
      required Uint8List retired,
    }) async {
      remoteData['public:${PqSigningRoot.recordName}$atSign'] =
          jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(active)),
        ApskSigningKey.forPublicKey(
            alg: PqSigningRoot.rootKeyAlgo,
            pub: base64Encode(retired),
            status: KeyEntryStatus.retired),
      ]));
    }

    test('a link signed under a RETIRED root still verifies', () async {
      // The whole reason a retired entry stays advertised: what it signed goes
      // on verifying. Checking only the active entry would turn every link
      // written before a rotation into `broken` — reported as tampering — the
      // moment a successor appeared.
      final predecessor = await MlDsa65PureDartAlgo().generateKeyPair();
      final successor = await MlDsa65PureDartAlgo().generateKeyPair();
      final holder = client('priv-1');
      final childClient = client('child-1');
      final child = await registered(childClient);

      // Signed while the predecessor was the only root, then the record moves
      // on: the successor is active and the predecessor is retired beside it.
      final link = await PqSigningChain(holder)
          .signRootLinkFor('child-1', rootPrivate: predecessor.secretKey);
      await publishRotatedRoot(
          active: successor.publicKey, retired: predecessor.publicKey);
      await conveyRoot(child, link!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue,
          reason: 'the conveyance verifier tries every advertised root, so a '
              'link signed under the retired one is still stamped');
      final result =
          await PqSigningChain(childClient).verifyChain(child, 'child-1');
      expect(result.verdict, ChainVerdict.anchored,
          reason: 'and the chain verifier reaches the same conclusion — these '
              'are two separate verifiers of one shape, and the plan row named '
              'only one. Reason if not: ${result.reason}');
    });

    test('a link signed under a root the record never advertised is broken',
        () async {
      // The differential: same code path, same two-entry record, a signer the
      // record does not vouch for. Without this, "tries every advertised root"
      // and "accepts anything" look identical.
      final stranger = await MlDsa65PureDartAlgo().generateKeyPair();
      final successor = await MlDsa65PureDartAlgo().generateKeyPair();
      final predecessor = await MlDsa65PureDartAlgo().generateKeyPair();
      final holder = client('priv-1');
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link = await PqSigningChain(holder)
          .signRootLinkFor('child-1', rootPrivate: stranger.secretKey);
      await publishRotatedRoot(
          active: successor.publicKey, retired: predecessor.publicKey);
      await conveyRoot(child, link!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'trying every advertised root is not the same as trying '
              'every root');
    });

    test('publishes a conveyed root link, and not the same one twice',
        () async {
      final pair = await publishRoot();
      final holder = client('priv-1');
      final childClient = client('child-1');
      final child = await registered(childClient);

      final link = await PqSigningChain(holder)
          .signRootLinkFor('child-1', rootPrivate: pair.secretKey);
      await conveyRoot(child, link!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);
      expect(await PqSigningChain(childClient).readRootLink('child-1'), link);

      await conveyRoot(child, link);
      expect(await PqSigningChain(childClient).publishPendingLink(), isFalse,
          reason: 'this runs at every start, so republishing an unchanged '
              'link would rewrite the record for nothing');
    });

    test('replaces an existing root link with a different one', () async {
      final pair = await publishRoot();
      final holder = client('priv-1');
      final childClient = client('child-1');
      final child = await registered(childClient);

      final first = await PqSigningChain(holder)
          .signRootLinkFor('child-1', rootPrivate: pair.secretKey);
      await conveyRoot(child, first!);
      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);

      // ML-DSA signing is hedged, so re-signing the same payload yields a
      // genuinely different link — which is the differential this needs, and
      // the reason it does not have to manufacture one.
      final second = await PqSigningChain(holder)
          .signRootLinkFor('child-1', rootPrivate: pair.secretKey);
      expect(second, isNot(first),
          reason: 'differential guard: two identical links would compare a '
              'case with itself and pass either way');
      await conveyRoot(child, second!);

      expect(await PqSigningChain(childClient).publishPendingLink(), isTrue);
      expect(await PqSigningChain(childClient).readRootLink('child-1'), second);
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
      remoteData['public:${PqSigningRoot.recordName}$atSign'] =
          jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(pair.publicKey))
      ]));
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

    // A second copy of the test above used to sit here, re-signing the same
    // payload in the JWS shape to prove the walk climbed both wrappers. There
    // is one shape now, so it was the preceding test twice over.

    test('reports broken, not chained, for a link that does not verify',
        () async {
      final parentClient = client('parent-1');
      final parent = await registered(parentClient);
      final childClient = client('child-1');
      await registered(childClient);

      final link =
          await PqSigningChain(parentClient).signLinkFor(parent, 'child-1');
      await PqSigningChain(childClient)
          .publishLink('child-1', withForgedSignature(link!));

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
    // can — but then claims it came from parent-1. The claim lives inside the
    // protected header, so this is not a relabel: it edits bytes the
    // signature covers.
    final link =
        await PqSigningChain(impostorClient).signLinkFor(impostor, 'child-1');
    await registered(client('parent-1'));
    final forged =
        link!.claiming({...link.signature.header, 'kid': 'parent-1'});

    final verifier = AtClientSecretSharing.forClient(client('verifier-1'));
    await expectLater(
        verifier.verifyEnvelopeSignature(forged, signerAtSign: atSign),
        throwsA(isA<Exception>()),
        reason: 'a claimed parent is checked against that parent\'s own '
            'published key, and the claim is under the signature besides — '
            'otherwise any enrollment could name any other as its approver');
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
