import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        AtEnrollmentResponse,
        AtKeys,
        AtKeysMaterial,
        CryptographicKeyType,
        EnrollmentUpdateRequest,
        InMemoryAtKeysIo,
        KeyEntryStatus,
        KeyPartStatus;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/secret_sharing/key_package_minting.dart'
    show KeyPackageMinting;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

/// KE-2's writer: an enrollment amending its own advertised key package.
///
/// **The ordering assertion is the one that matters most, and it points the
/// opposite way to `SigningKeyMinting`'s.** An encapsulation key advertised
/// before its private half is filed makes every sender reading the
/// advertisement in that window seal data to a key nobody holds — durable
/// writes that no later repair opens. So the private half must be in the
/// keyfile *before* the `enroll:update` goes out, and
/// [heldWhenPublished] is what lets a test tell the two orders apart rather
/// than merely observing that both happened.
void main() {
  const atSign = '@alice';
  const enrollmentId = 'enroll-a';

  late MockAtClient atClient;
  late MockAtEnrollment enrollment;
  late MockAtLookUp atLookUp;
  late AtChops atChops;
  late InMemoryAtKeysIo keysIo;

  /// Every `enroll:update` the minter sent.
  late List<EnrollmentUpdateRequest> updates;

  /// The kpids the keyfile held when each update was sent, so a test can tell
  /// "advertised, then filed" from "filed, then advertised".
  late List<Set<String>> heldWhenPublished;

  Future<List<AtKeysMaterial>> encMaterials(
      {String part = CryptographicKeyType.publicEncapsulation}) async {
    final keys = await keysIo.read(atSign);
    return keys.keys
        .where((m) => m.enrollmentId == enrollmentId && m.keyPartType == part)
        .toList();
  }

  Future<Set<String>> heldKpids() async =>
      (await encMaterials()).map((m) => m.keyId).toSet();

  /// The key package the last `enroll:update` advertised, **after verifying
  /// its signature the way a peer does**.
  ///
  /// Verification is not a bonus assertion here, it is the point: a peer
  /// checks the package against the enrollment's `_apsk` before sealing
  /// anything to it, so a package that does not verify is one nobody acts on
  /// — and a test that read the payload directly would pass for a package the
  /// whole ecosystem would ignore. The enrollment holds no signing key of its
  /// own in these rows, so `_apsk` is the bare APKAM public key.
  Future<KeyPackage> advertised() async {
    final envelope = SignedEnvelope.fromJson(
        updates.last.metadata!['keyPackage'] as Map<String, dynamic>);
    await verifyEnvelope(envelope,
        signerPublicKey:
            atChops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey,
        expecting: EnvelopeType.keyPackage);
    return KeyPackage.fromPayload(envelope.payload,
        enrollmentId: enrollmentId);
  }

  /// Files an already-held encapsulation keypair, as an enrollment created
  /// under [algorithm] would carry.
  Future<String> fileHeldKey(String algorithm) async {
    final kem = SecretSharingAlgos.kemFor(algorithm)!;
    final seed = kem.newSeed();
    final pair = await kem.keyPairFromSeed(seed);
    final kpid = PackageKey.computeKid(base64Encode(pair.publicKey));
    final materialAlgo = SecretSharingAlgos.materialAlgoFor(algorithm)!;
    await keysIo.update(atSign.toAtsign(), (keys) {
      keys.addKey(AtKeysMaterial(
        enrollmentId: enrollmentId,
        keyId: kpid,
        keyPartType: CryptographicKeyType.publicEncapsulation,
        keyAlgorithmType: materialAlgo,
        bytes: AtBytes(pair.publicKey),
        createdAt: DateTime.now().toUtc(),
      ));
      keys.addKey(AtKeysMaterial(
        enrollmentId: enrollmentId,
        keyId: kpid,
        keyPartType: CryptographicKeyType.privateDecapsulation,
        keyAlgorithmType: materialAlgo,
        bytes: AtBytes(seed),
        createdAt: DateTime.now().toUtc(),
      ));
      return true;
    });
    return kpid;
  }

  void configure(List<String> algorithms) {
    when(() => atClient.getPreferences()).thenReturn(
        AtClientPreference(keyEstablishmentAlgorithms: algorithms));
  }

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(EnrollmentUpdateRequest(
        enrollmentId: 'fallback', metadata: const {'a': 'b'}));
    registerFallbackValue(MockAtLookUp());
  });

  setUp(() async {
    atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys(atsign: atSign.toAtsign()));
    updates = [];
    heldWhenPublished = [];

    atClient = MockAtClient();
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.atKeysIo).thenReturn(keysIo);
    configure(const [SecretSharingAlgos.xWing]);

    final remoteSecondary = MockRemoteSecondary();
    atLookUp = MockAtLookUp();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

    enrollment = MockAtEnrollment();
    when(() => enrollment.update(any(), any())).thenAnswer((i) async {
      updates.add(i.positionalArguments[0] as EnrollmentUpdateRequest);
      heldWhenPublished.add(await heldKpids());
      return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved);
    });
  });

  KeyPackageMinting minter() =>
      KeyPackageMinting(atClient, enrollment: enrollment);

  group('what it does not do', () {
    test('an enrollment already holding what the list names does nothing',
        () async {
      await fileHeldKey(SecretSharingAlgos.xWing);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, isEmpty);
      expect(reconciled.retired, isEmpty);
      expect(updates, isEmpty,
          reason: 'this is every start after the first, and a package '
              'republished on each one is a durable record rewritten to say '
              'what it already says');
    });

    test('a client with no key source mints nothing', () async {
      // A minted key that cannot be filed is one peers seal to and this
      // client can never open — the exact data loss the file-first order
      // exists to prevent, arriving by another route.
      when(() => atClient.atKeysIo).thenReturn(null);
      configure(const [SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, isEmpty);
      expect(updates, isEmpty);
    });

    test('an unenrolled client mints nothing', () async {
      // enroll:update is self-only, so a `primary` connection has no
      // enrollment record whose metadata it could amend.
      when(() => atLookUp.enrollmentId).thenReturn(null);
      configure(const [SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, isEmpty);
      expect(updates, isEmpty);
      expect(await heldKpids(), isEmpty,
          reason: 'nothing may be filed either: a key this client cannot '
              'advertise is one no sender can reach');
    });
  });

  group('gaining a key', () {
    test('a second algorithm is minted, filed and advertised beside the first',
        () async {
      final first = await fileHeldKey(SecretSharingAlgos.xWing);
      configure(
          const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, [SecretSharingAlgos.mlKem1024]);
      expect(reconciled.retired, isEmpty);

      final package = await advertised();
      expect(package.keys.map((k) => k.alg).toSet(),
          {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024});
      expect(package.keys.every((k) => k.status == KeyEntryStatus.active),
          isTrue);
      expect(package.keys.map((k) => k.kid), contains(first),
          reason: 'the key already advertised keeps its address — an '
              'enrollment that gained a key has not moved');
      expect(await heldKpids(), hasLength(2));
    });

    test('the private half is filed BEFORE the advertisement goes out',
        () async {
      // The property this whole class is ordered around. Publishing first
      // would let a sender reading the advertisement in the window seal to a
      // key whose decapsulation half does not exist yet — and those writes
      // are durable, so nothing later opens them.
      await fileHeldKey(SecretSharingAlgos.xWing);
      configure(
          const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      expect(heldWhenPublished, hasLength(1));
      final advertisedKids = (await advertised()).keys.map((k) => k.kid).toSet();
      expect(heldWhenPublished.single, containsAll(advertisedKids),
          reason: 'every kid the advertisement names was already in the '
              'keyfile at the moment it was sent');
    });

    test('the minted private half re-derives the advertised public key',
        () async {
      // A filed seed that does not reproduce the advertised key is an address
      // this client answers at and cannot open — indistinguishable from a
      // healthy enrollment until the first secret arrives.
      configure(const [SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      final privates =
          await encMaterials(part: CryptographicKeyType.privateDecapsulation);
      final seed = Uint8List.fromList(privates.single.bytes.bytes);
      final pair = await SecretSharingAlgos.kemFor(
              SecretSharingAlgos.mlKem1024)!
          .keyPairFromSeed(seed);

      expect(base64Encode(pair.publicKey), (await advertised()).keys.single.pub);
    });

    test('the advertisement is signed by the key _apsk names', () async {
      // advertised() verifies against the APKAM public key and throws if the
      // signature does not check out, so reaching a package at all is the
      // assertion. A peer verifies exactly this way before sealing anything,
      // so a package signed by some other key is one nobody acts on.
      configure(const [SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      expect((await advertised()).keys, hasLength(1));
    });

    test('only metadata is named, so the grant cannot widen', () async {
      configure(const [SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      final request = updates.single;
      expect(request.enrollmentId, enrollmentId);
      expect(request.metadata!.keys, ['keyPackage']);
      expect(request.apkamPublicKey, isNull);
      expect(request.signingKeys, isNull);
      expect(request.apskLegacy, isNull);
    });
  });

  group('losing a key', () {
    test('an algorithm that left the list is retired, not dropped', () async {
      final leaving = await fileHeldKey(SecretSharingAlgos.xWing);
      final staying = await fileHeldKey(SecretSharingAlgos.mlKem1024);
      configure(const [SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.retired, [SecretSharingAlgos.xWing]);
      expect(reconciled.minted, isEmpty);

      final package = await advertised();
      final byKid = {for (final k in package.keys) k.kid: k};
      // Presence asserted before status, so dropping the entry fails with
      // "the retired key is missing" rather than a null-check crash that
      // names nothing. The publish rewrites the record whole, so an omitted
      // entry IS a withdrawal — the exact mistake this row exists to catch.
      expect(byKid.keys, contains(leaving),
          reason: 'a retired key stays listed: the advertisement is rewritten '
              'whole, so dropping the entry withdraws it and strands every '
              'envelope still in flight to that address');
      expect(byKid[leaving]!.status, KeyEntryStatus.retired,
          reason: 'listed AS retired, so a peer holding an envelope in flight '
              'can see whose key it was');
      expect(byKid.keys, contains(staying));
      expect(byKid[staying]!.status, KeyEntryStatus.active);
      expect(package.bestKeyFor(SecretSharingAlgos.keyAlgos)!.kid, staying,
          reason: 'nothing new is sealed to a retired key');
    });

    test('the retired private half is retained, so old envelopes still open',
        () async {
      final leaving = await fileHeldKey(SecretSharingAlgos.xWing);
      await fileHeldKey(SecretSharingAlgos.mlKem1024);
      configure(const [SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      final privates =
          await encMaterials(part: CryptographicKeyType.privateDecapsulation);
      final retired = privates.firstWhere((m) => m.keyId == leaving);
      expect(retired.status, KeyPartStatus.retired);
      expect(retired.bytes.bytes, isNotEmpty,
          reason: 'retirement withdraws a key from service; it never removes '
              'the bytes, which are the only thing that opens what was '
              'already sealed to it');
    });

    test('a swap mints the incoming key before retiring the outgoing one',
        () async {
      // The single-step migration, which is what a deployment that edits the
      // list in one go actually does. The enrollment must never pass through
      // a state advertising no active key.
      final outgoing = await fileHeldKey(SecretSharingAlgos.xWing);
      configure(const [SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, [SecretSharingAlgos.mlKem1024]);
      expect(reconciled.retired, [SecretSharingAlgos.xWing]);

      final package = await advertised();
      expect(package.keys.where((k) => k.status == KeyEntryStatus.active),
          hasLength(1),
          reason: 'exactly one active key at every observable moment');
      expect(package.keys.map((k) => k.kid), contains(outgoing),
          reason: 'the outgoing key is retired, not removed — a swap must not '
              'strand what was already sealed to the key it replaces');
      expect(package.keys.firstWhere((k) => k.kid == outgoing).status,
          KeyEntryStatus.retired);
    });
  });
}
