import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        AtEnrollmentResponse,
        CryptographicMaterial,
        CryptographicMaterialRole,
        InMemoryAtKeysIo,
        KeyEntryStatus,
        CryptographicMaterialStatus;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart'
    show EnrollmentUpdateRequest, EnrollmentUpdater;
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show EnrollmentDirectory, KeyPackageStatus, NamespaceMember;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/secret_sharing/key_package_minting.dart'
    show KeyPackageMinting;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/test_keypairs.dart';
import 'test_utils/ml_dsa_keyfile.dart';

class MockAtClient extends Mock implements AtClient {}

/// Answers `listForNamespace` from [members], or throws [failure].
class _Directory implements EnrollmentDirectory {
  List<NamespaceMember> members = [];
  Object? failure;
  final asked = <String>[];

  @override
  Future<List<NamespaceMember>> listForNamespace(String namespace,
      {Set<String> excludeEnrollmentIds = const {}}) async {
    asked.add(namespace);
    if (failure != null) throw failure!;
    return members;
  }

  @override
  Future<DateTime?> lastRevokedAt(String namespace) async => null;
}

class MockEnrollmentUpdater extends Mock implements EnrollmentUpdater {}

/// An enrollment amending its own advertised key package.
///
/// Ordering is the property that matters most: an encapsulation key advertised
/// before its private half is filed makes every sender reading the
/// advertisement in that window seal data to a key nobody holds, and those
/// writes are durable — [heldWhenPublished] is what lets a test tell the two
/// orders apart rather than merely observe that both happened.
void main() {
  const atSign = '@alice';
  const enrollmentId = 'enroll-a';

  late MockAtClient atClient;
  late MockEnrollmentUpdater enrollment;
  late MockAtLookUp atLookUp;
  late RsaKeyPair apkamPair;
  late InMemoryAtKeysIo keysIo;

  late List<EnrollmentUpdateRequest> updates;

  /// The kpids the keyfile held when each update was sent, so a test can tell
  /// "advertised, then filed" from "filed, then advertised".
  late List<Set<String>> heldWhenPublished;

  Future<List<CryptographicMaterial>> encMaterials(
      {String part = CryptographicMaterialRole.publicEncapsulation}) async {
    final keys = await keysIo.read(atSign);
    // NOTE: not scoped by enrollment id — an enrollment's first package is
    // filed untagged and anything minted later is tagged.
    return keys.keys.where((m) => m.role == part).toList();
  }

  Future<Set<String>> heldKpids() async =>
      (await encMaterials()).map((m) => m.keyId).toSet();

  /// The key package the last `enroll:update` advertised, verified against
  /// `_apsk` the way a peer does before sealing anything to it.
  ///
  /// The enrollment holds no signing key of its own in these rows, so `_apsk`
  /// is the bare APKAM public key.
  Future<KeyPackage> advertised() async {
    final envelope = SignedEnvelope.fromJson(
        updates.last.metadata!['keyPackage'] as Map<String, dynamic>);
    await verifyEnvelope(envelope,
        signerPublicKey: apkamPair.atPublicKey.publicKey,
        expecting: EnvelopeType.keyPackage);
    return KeyPackage.fromPayload(envelope.payload, enrollmentId: enrollmentId);
  }

  /// Files an already-held encapsulation keypair, as an enrollment created
  /// under [algorithm] would carry.
  ///
  /// [tagged] defaults to false because a first key package is filed before
  /// the atServer has assigned an enrollment id, so an untagged pair is the
  /// ordinary state of a freshly created enrollment; a tagged one appears
  /// only once something re-files it under the id.
  Future<String> fileHeldKey(String algorithm,
      {bool tagged = false,
      CryptographicMaterialStatus status =
          CryptographicMaterialStatus.active}) async {
    final kem = SecretSharingAlgos.kemFor(algorithm)!;
    final seed = kem.newSeed();
    final pair = await kem.keyPairFromSeed(seed);
    final kpid = PackageKey.computeKid(base64Encode(pair.publicKey));
    final materialAlgo = SecretSharingAlgos.materialAlgoFor(algorithm)!;
    await keysIo.update(atSign.toAtsign(), (keys) {
      keys.addKey(CryptographicMaterial(
        enrollmentId: tagged ? enrollmentId : null,
        keyId: kpid,
        role: CryptographicMaterialRole.publicEncapsulation,
        algorithm: materialAlgo,
        bytes: AtBytes(pair.publicKey),
        createdAt: DateTime.now().toUtc(),
        status: status,
      ));
      keys.addKey(CryptographicMaterial(
        enrollmentId: tagged ? enrollmentId : null,
        keyId: kpid,
        role: CryptographicMaterialRole.privateDecapsulation,
        algorithm: materialAlgo,
        bytes: AtBytes(seed),
        createdAt: DateTime.now().toUtc(),
        status: status,
      ));
      return true;
    });
    return kpid;
  }

  void configure(List<String> algorithms) {
    when(() => atClient.getPreferences())
        .thenReturn(AtClientPreference(keyEstablishmentAlgorithms: algorithms));
  }

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(EnrollmentUpdateRequest(
        enrollmentId: 'fallback', metadata: const {'a': 'b'}));
    registerFallbackValue(MockAtLookUp());
  });

  setUp(() async {
    apkamPair = pkamKeyPairFor(atSign, enrollmentId);
    // Flat, as an OTP-enrolled rsa2048 keyfile is: the enrollment's typed
    // section starts empty, and filling it is what the minter does.
    keysIo = keysHoldingApkam(atSign, null, apkamPair);
    updates = [];
    heldWhenPublished = [];

    atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.atKeysIo).thenReturn(keysIo);
    configure(const [SecretSharingAlgos.xWing]);

    final remoteSecondary = MockRemoteSecondary();
    atLookUp = MockAtLookUp();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);

    enrollment = MockEnrollmentUpdater();
    when(() => enrollment.update(any(), any())).thenAnswer((i) async {
      updates.add(i.positionalArguments[0] as EnrollmentUpdateRequest);
      heldWhenPublished.add(await heldKpids());
      return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved);
    });
  });

  KeyPackageMinting minter() =>
      KeyPackageMinting(atClient, updater: enrollment);

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
      // NOTE: a minted key that cannot be filed is one peers seal to and this
      // client can never open.
      when(() => atClient.atKeysIo).thenReturn(null);
      configure(const [SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, isEmpty);
      expect(updates, isEmpty);
    });

    test('an unenrolled client mints nothing', () async {
      // NOTE: enroll:update is self-only, so a client that can name no
      // enrollment can name no record to amend.
      when(() => atClient.enrollmentId).thenReturn(null);
      configure(const [SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, isEmpty);
      expect(updates, isEmpty);
      expect(await heldKpids(), isEmpty,
          reason: 'nothing may be filed either: a key this client cannot '
              'advertise is one no sender can reach');
    });
  });

  test('a stop that lands during the reconcile sends no update', () async {
    await fileHeldKey(SecretSharingAlgos.xWing);
    configure(const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);
    final remoteSecondary = MockRemoteSecondary();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    var stopped = false;
    when(() => remoteSecondary.atLookUp).thenAnswer((_) {
      if (stopped) throw AtClientStoppedException('stopped');
      return atLookUp;
    });
    // NOTE: the stop lands at the reconcile's first read of the enrollment
    // id, after anything that could have read the lookup up front.
    when(() => atClient.enrollmentId).thenAnswer((_) {
      stopped = true;
      return enrollmentId;
    });

    await expectLater(minter().reconcileKeyPackage(),
        throwsA(isA<AtClientStoppedException>()));

    expect(updates, isEmpty,
        reason: 'a lookup read before the stop would still reach the '
            'atServer, opening a new connection for a stopped client');
  });

  group('gaining a key', () {
    test('a second algorithm is minted, filed and advertised beside the first',
        () async {
      final first = await fileHeldKey(SecretSharingAlgos.xWing);
      configure(const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, [SecretSharingAlgos.mlKem1024]);
      expect(reconciled.retired, isEmpty);

      final package = await advertised();
      expect(package.keys.map((k) => k.alg).toSet(),
          {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024});
      expect(
          package.keys.every((k) => k.status == KeyEntryStatus.active), isTrue);
      expect(package.keys.map((k) => k.kid), contains(first),
          reason: 'the key already advertised keeps its address — an '
              'enrollment that gained a key has not moved');
      expect(await heldKpids(), hasLength(2));
    });

    test('an amendment conveys nothing over the wire', () async {
      // NOTE: `put` is stubbed to record rather than left unstubbed — an
      // unstubbed call throws, and the failure would name the mock rather
      // than a conveyance.
      final written = <String>[];
      when(() => atClient.put(any(), any())).thenAnswer((i) async {
        written.add((i.positionalArguments[0] as AtKey).toString());
        return true;
      });

      await fileHeldKey(SecretSharingAlgos.xWing);
      configure(const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();

      expect(reconciled.minted, [SecretSharingAlgos.mlKem1024],
          reason: 'the control: the amendment must actually have happened, or '
              'writing nothing is not evidence of anything');
      expect(written, isEmpty,
          reason: 'an amendment files locally and advertises through '
              'enroll:update — it must not write a record. A conveyance here '
              'would re-seal to a holder that already has the plaintext');
    });

    test('the private half is filed BEFORE the advertisement goes out',
        () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      configure(const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      expect(heldWhenPublished, hasLength(1));
      final advertisedKids =
          (await advertised()).keys.map((k) => k.kid).toSet();
      expect(heldWhenPublished.single, containsAll(advertisedKids),
          reason: 'every kid the advertisement names was already in the '
              'keyfile at the moment it was sent');
    });

    test('the minted private half re-derives the advertised public key',
        () async {
      // NOTE: a filed seed that does not reproduce the advertised key is an
      // address this client answers at and cannot open, and it looks healthy
      // until the first secret arrives.
      configure(const [SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      final privates = await encMaterials(
          part: CryptographicMaterialRole.privateDecapsulation);
      final seed = Uint8List.fromList(privates.single.bytes.bytes);
      final pair =
          await SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!
              .keyPairFromSeed(seed);

      expect(
          base64Encode(pair.publicKey), (await advertised()).keys.single.pub);
    });

    test('the advertisement is signed by the key _apsk names', () async {
      // NOTE: advertised() throws unless the signature verifies, so reaching
      // a package at all is the assertion.
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
      // NOTE: presence is asserted before status, so dropping the entry fails
      // by name rather than crashing on a null.
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

    test('a keyfile status this build cannot read is republished verbatim',
        () async {
      // NOTE: the advertisement is rewritten whole on every reconcile, so a
      // status token this build cannot read must cross unchanged rather than
      // be narrowed to one of the two values it knows.
      final unreadable = await fileHeldKey(SecretSharingAlgos.xWing,
          status: CryptographicMaterialStatus.of('revoked'));
      final live = await fileHeldKey(SecretSharingAlgos.mlKem1024);
      configure(const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

      final reconciled = await minter().reconcileKeyPackage();
      expect(reconciled.minted, [SecretSharingAlgos.xWing]);
      expect(reconciled.retired, isEmpty,
          reason: 'nothing was withdrawn by this run - the key was already '
              'carrying a status of its own');

      final package = await advertised();
      final byKid = {for (final k in package.keys) k.kid: k};
      expect(byKid.keys, contains(unreadable));
      expect(byKid[unreadable]!.status, 'revoked',
          reason: 'raw literal: the token the keyfile holds is the token the '
              'record gets, so an older build cannot weaken it');
      expect(byKid[unreadable]!.offeredForNewOperations, isFalse);
      expect(byKid[live]!.status, KeyEntryStatus.active);
      expect(package.bestKeyFor(const [SecretSharingAlgos.xWing])!.kid,
          isNot(unreadable),
          reason: 'and nothing new is sealed to it - the freshly minted '
              'X-Wing key is the address for that algorithm now');
    });

    test('the retired private half is retained, so old envelopes still open',
        () async {
      final leaving = await fileHeldKey(SecretSharingAlgos.xWing);
      await fileHeldKey(SecretSharingAlgos.mlKem1024);
      configure(const [SecretSharingAlgos.mlKem1024]);

      await minter().reconcileKeyPackage();

      final privates = await encMaterials(
          part: CryptographicMaterialRole.privateDecapsulation);
      final retired = privates.firstWhere((m) => m.keyId == leaving);
      expect(retired.status, CryptographicMaterialStatus.retired);
      expect(retired.bytes.bytes, isNotEmpty,
          reason: 'retirement withdraws a key from service; it never removes '
              'the bytes, which are the only thing that opens what was '
              'already sealed to it');
    });

    test('a swap mints the incoming key before retiring the outgoing one',
        () async {
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

  group('a published package that no longer verifies', () {
    late _Directory directory;

    KeyPackageMinting checking() =>
        KeyPackageMinting(atClient, updater: enrollment, directory: directory);

    NamespaceMember member(String id, KeyPackageStatus status) =>
        NamespaceMember(
            enrollmentId: id, access: 'rw', keyPackageStatus: status);

    setUp(() {
      directory = _Directory();
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing])
        ..namespace = 'buzz');
    });

    test('is signed again with the same keys, under the key _apsk names',
        () async {
      final kpid = await fileHeldKey(SecretSharingAlgos.xWing);
      directory.members = [member(enrollmentId, KeyPackageStatus.rejected)];

      final reconciled = await checking().reconcileKeyPackage();

      expect(directory.asked, ['buzz'],
          reason: 'read through the client\'s own namespace, where its '
              'package is registered');
      expect(updates, hasLength(1),
          reason: 'a package every peer refuses leaves the enrollment '
              'unreachable, so it is republished rather than left');
      expect((await advertised()).keys.map((k) => k.kid), [kpid],
          reason: 'the same key, now under a signature that verifies — '
              'advertised() throws unless it does');
      expect(await heldKpids(), {kpid}, reason: 'nothing is minted');
      expect(reconciled.minted, isEmpty);
      expect(reconciled.retired, isEmpty);
    });

    test('a stop that lands before the re-sign sends nothing', () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      directory.members = [member(enrollmentId, KeyPackageStatus.rejected)];
      final remoteSecondary = MockRemoteSecondary();
      when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
      when(() => remoteSecondary.atLookUp)
          .thenThrow(AtClientStoppedException('stopped'));

      await expectLater(checking().reconcileKeyPackage(),
          throwsA(isA<AtClientStoppedException>()));

      expect(updates, isEmpty);
    });

    test('control: a package that verifies is left alone', () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      directory.members = [member(enrollmentId, KeyPackageStatus.present)];

      await checking().reconcileKeyPackage();

      expect(directory.asked, ['buzz']);
      expect(updates, isEmpty);
    });

    test('a package that could not be checked is left alone', () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      directory.members = [member(enrollmentId, KeyPackageStatus.unverified)];

      await checking().reconcileKeyPackage();

      expect(updates, isEmpty,
          reason: 'unverified means its _apsk could not be fetched, which '
              'says nothing about the signature');
    });

    test('another enrollment\'s rejected package is not this one\'s to sign',
        () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      directory.members = [
        member('someone-else', KeyPackageStatus.rejected),
        member(enrollmentId, KeyPackageStatus.present),
      ];

      await checking().reconcileKeyPackage();

      expect(updates, isEmpty);
    });

    test('a failed read does not fail the reconcile', () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      directory.failure = StateError('the atServer did not answer');

      final reconciled = await checking().reconcileKeyPackage();

      expect(updates, isEmpty);
      expect(reconciled.minted, isEmpty);
    });

    test(
        'a client naming no namespace checks through one its enrollment is '
        'granted', () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      configure(const [SecretSharingAlgos.xWing]);
      final enrollments = MockEnrollmentService();
      when(() => atClient.enrollmentService).thenReturn(enrollments);
      when(() => enrollments.fetchEnrollmentRequests(
              enrollmentListParams: any(named: 'enrollmentListParams')))
          .thenAnswer((_) async => [
                Enrollment()
                  ..enrollmentId = enrollmentId
                  ..namespace = {'__manage': 'rw', 'wavi': 'rw'}
              ]);
      directory.members = [member(enrollmentId, KeyPackageStatus.rejected)];

      await checking().reconcileKeyPackage();

      expect(directory.asked, ['wavi'],
          reason: 'a package is listed under every namespace its enrollment '
              'may read, and `__manage` is not a namespace data lives in');
      expect(updates, hasLength(1));
    });

    test('a client with no namespace anywhere does not check', () async {
      await fileHeldKey(SecretSharingAlgos.xWing);
      configure(const [SecretSharingAlgos.xWing]);
      final enrollments = MockEnrollmentService();
      when(() => atClient.enrollmentService).thenReturn(enrollments);
      when(() => enrollments.fetchEnrollmentRequests(
              enrollmentListParams: any(named: 'enrollmentListParams')))
          .thenAnswer((_) async => [
                Enrollment()
                  ..enrollmentId = enrollmentId
                  ..namespace = {'__manage': 'rw'}
              ]);
      directory.members = [member(enrollmentId, KeyPackageStatus.rejected)];

      await checking().reconcileKeyPackage();

      expect(directory.asked, isEmpty);
      expect(updates, isEmpty);
    });
  });
}
