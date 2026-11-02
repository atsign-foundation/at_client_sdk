import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole,
        CryptographicMaterialStatus;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/hive_store.dart';
import '../test_utils/recorded_logs.dart';
import '../test_utils/transport.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// An in-memory key store that runs [beforeUpdate] once, ahead of its next
/// update.
class _StoreAwaitingOnce extends InMemoryAtKeysIo {
  Future<void> Function()? beforeUpdate;

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    final hook = beforeUpdate;
    beforeUpdate = null;
    if (hook != null) await hook();
    return super.update(atsign, mutate);
  }
}

/// `Atsign.enroll`, `PendingEnrollment` and `resumeEnrollment`: the key store
/// named at submission is the resume record, approval completes it, and a
/// denial empties it.
///
/// The atServer is a mocked lookup that answers by verb, and the approver is
/// modelled faithfully: it unwraps the symmetric key the request RSA-wrapped
/// to the atSign's encryption public key and seals the atSign's secrets under
/// it, which is what the handshake then opens. Legacy key exchange only; the
/// pq mode, whose approver seals to a key package, is `enroll_pq_test.dart`.
void main() {
  const atSign = '@alice🛠';
  const enrollmentId = 'e-1';
  final encryptionPublicKey = demo.encryptionPublicKeyMap[atSign]!;
  final encryptionPrivateKey = demo.encryptionPrivateKeyMap[atSign]!;
  final selfEncryptionKey = demo.aesKeyMap[atSign]!;
  late Directory dir;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('enroll_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<AtClientPreference> preference() async => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = await refusedPort()
    ..hiveStoragePath = dir.path
    ..namespace = 'lifecycle';

  /// The atServer and the manager's approving client in one double.
  ///
  /// [decide] answers each PKAM attempt after submission: `true` approves,
  /// and an exception is the atServer's refusal, `AT0026` for not-yet-decided
  /// and `AT0025` for denied.
  ///
  /// [onKeyFetch] runs as the handshake fetches the last secret the approval
  /// released, and the first [keyFetchesUnanswered] of those fetches get an
  /// empty answer. A poll after [AtLookUp.stop] is refused, as a stopped
  /// connection refuses everything.
  MockAtLookupImpl atServer(
      {required Future<bool> Function(int attempt) decide,
      void Function()? onKeyFetch,
      int keyFetchesUnanswered = 0}) {
    final lookUp = MockAtLookupImpl();
    String? wrappedSymmetricKey;
    var attempts = 0;
    var stopped = false;
    var unanswered = keyFetchesUnanswered;

    /// What a real approver does with the request: unwrap the symmetric key
    /// with the atSign's encryption private key, and seal a secret under it.
    Future<Map<String, String>> sealed(String secret) async {
      final symmetricKey = utf8.decode((RsaEncryptionAlgo()
            ..atPrivateKey = AtPrivateKey.fromString(encryptionPrivateKey))
          .decrypt(base64Decode(wrappedSymmetricKey!)));
      final iv = InitialisationVector.random(16);
      final bytes = await AESEncryptionAlgo(AESKey(symmetricKey))
          .encrypt(Uint8List.fromList(utf8.encode(secret)), iv: iv);
      return {
        'value': base64Encode(bytes),
        'iv': base64Encode(iv.ivBytes),
      };
    }

    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      if (command.startsWith('enroll:')) {
        final json = jsonDecode(command.substring(
            command.indexOf('{'), command.lastIndexOf('}') + 1));
        wrappedSymmetricKey = json['encryptedAPKAMSymmetricKey'] as String;
        return 'data:${jsonEncode({
              'enrollmentId': enrollmentId,
              'status': 'pending'
            })}';
      }
      if (command.startsWith(
          'keys:get:keyName:$enrollmentId.default_enc_private_key')) {
        return 'data:${jsonEncode(await sealed(encryptionPrivateKey))}';
      }
      if (command
          .startsWith('keys:get:keyName:$enrollmentId.default_self_enc_key')) {
        onKeyFetch?.call();
        if (unanswered > 0) {
          unanswered--;
          return '';
        }
        return 'data:${jsonEncode(await sealed(selfEncryptionKey))}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
        return 'data:$encryptionPublicKey';
      }
      throw StateError('the mocked atServer has no answer for: '
          '${(builder as VerbBuilder).buildCommand()}');
    });
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async {
      if (stopped) throw StoppedException('the connection was stopped');
      return decide(++attempts);
    });
    when(lookUp.stop).thenAnswer((_) async => stopped = true);
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return lookUp;
  }

  Future<PendingEnrollment> submit(
          InMemoryAtKeysIo store, MockAtLookupImpl server,
          {String device = 'phone'}) async =>
      Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: device,
          namespaces: {'wavi': 'rw'},
          keys: store,
          preference: await preference(),
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: await refusingAtDirectory(),
          atLookUp: server);

  test('submission files the minted keys as pending in the store named',
      () async {
    final store = InMemoryAtKeysIo();
    final pending = await submit(store, atServer(decide: (_) async => true));

    expect(pending.enrollmentId, enrollmentId);
    expect(pending.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, [enrollmentId]);
    expect(stored.holdsAuthenticationMaterial, isFalse,
        reason: 'a keypair the atServer has not accepted authenticates as '
            'nobody, and no published reader finds a flat APKAM keypair');
    final snapshot = stored.enrollmentInfo(enrollmentId)!;
    expect((snapshot.appName, snapshot.deviceName), ('wavi', 'phone'));
    expect(snapshot.namespaces, {'wavi': 'rw'});
    // ignore: deprecated_member_use
    expect(stored.apkamSymmetricKey, isNotNull,
        reason: 'a legacy request carries its own symmetric key, which the '
            'handshake needs after approval');
  });

  test(
      'a file store takes the pending document, and the completed keyfile '
      'reads back with the atSign\'s encryption keypair', () async {
    // The file store is the population: it self-encrypts the flat legacy
    // fields under a key this device is only given at approval, so a pending
    // document that put anything in them could not be written at all.
    final path = '${dir.path}/${atSign}_key.atKeys';
    final store = FileAtKeysIo(filePath: (_) => path);
    final server = atServer(decide: (_) async => true);

    final pending = await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'wavi',
        device: 'phone',
        namespaces: {'wavi': 'rw'},
        keys: store,
        preference: await preference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: server);
    expect(File(path).existsSync(), isTrue,
        reason: 'the submission is on disk before anyone approves it');
    expect((await store.read(atSign)).pendingEnrollmentIds, [enrollmentId]);

    final client = await pending.client(await preference(),
        retryInterval: const Duration(milliseconds: 10),
        storage: hiveStoreFor(pending.atSign, await preference()));

    final completed = await store.read(atSign);
    expect(completed.enrollmentToAuthenticateAs(), enrollmentId);
    expect(
        completed.encryptionKeyPair?.atPublicKey.publicKey, encryptionPublicKey,
        reason: 'the public key the submission fetched survives to the '
            'completed keyfile, beside the private key the approver sealed');
    expect(completed.toJson()['aesEncryptPublicKey'], encryptionPublicKey,
        reason: 'in the flat field a legacy reader looks for, under the '
            'name the keyfile format gives it');
    await client.stop();
  });

  test('open refuses a store that holds only a pending enrollment', () async {
    final store = InMemoryAtKeysIo();
    await submit(store, atServer(decide: (_) async => true));

    await expectLater(
        () async => Atsign(atSign).open(
            keys: store,
            preference: await preference(),
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            storage: hiveStoreFor(Atsign(atSign), await preference())),
        throwsA(isA<AtEnrollmentPendingException>()
            .having((e) => e.pendingEnrollmentIds, 'pending', [enrollmentId])));
  });

  test('resumeEnrollment finds the request by app and device, and only that',
      () async {
    final store = InMemoryAtKeysIo();
    await submit(store, atServer(decide: (_) async => true));
    final pref = await preference();

    final resumed = await Atsign(atSign).resumeEnrollment(
        app: 'wavi',
        device: 'phone',
        keys: store,
        preference: pref,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref));
    expect(resumed?.enrollmentId, enrollmentId);
    expect(resumed?.signingAlgo, SigningAlgoType.rsa2048);
    expect(resumed?.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);

    expect(
        await Atsign(atSign).resumeEnrollment(
            app: 'wavi',
            device: 'tablet',
            keys: store,
            preference: pref,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: atDirectoryOf(pref)),
        isNull,
        reason: 'another device\'s request is not this one');
    expect(
        await Atsign(atSign).resumeEnrollment(
            app: 'wavi',
            device: 'phone',
            keys: InMemoryAtKeysIo(),
            preference: pref,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: atDirectoryOf(pref)),
        isNull,
        reason: 'and a store holding nothing resumes nothing');
  });

  test(
      'a second request for the same app and device is refused in favour of '
      'resuming', () async {
    final store = InMemoryAtKeysIo();
    final server = atServer(decide: (_) async => true);
    await submit(store, server);

    await expectLater(
        () => submit(store, server),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e.message, 'message', contains('resumeEnrollment'))));
  });

  test(
      'approval completes the store, moves the keys to active, and opens a '
      'client', () async {
    final store = InMemoryAtKeysIo();
    // Not yet decided on the first poll, approved on the second: the wait is
    // exercised, not skipped.
    final server = atServer(
        decide: (attempt) async => attempt == 1
            ? throw UnAuthenticatedException(
                'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed')
            : true);
    final pending = await submit(store, server);

    final client = await pending.client(await preference(),
        retryInterval: const Duration(milliseconds: 10),
        storage: hiveStoreFor(pending.atSign, await preference()));

    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, isEmpty);
    expect(stored.authenticatableEnrollmentIds, isEmpty,
        reason: 'an rsa2048 enrollment holds no typed authentication material '
            'once approved; the flat fields are its credential, as every '
            'published reader and the self-retrofit expect');
    expect(stored.authenticationAlgorithmFor(enrollmentId), isNull);
    expect(stored.enrollmentToAuthenticateAs(), enrollmentId);
    // ignore: deprecated_member_use
    expect(stored.defaultEncryptionPrivateKey?.toString(), encryptionPrivateKey,
        reason: 'the secret the approver sealed, opened by the handshake');
    // ignore: deprecated_member_use
    expect(stored.defaultSelfEncryptionKey?.toString(), selfEncryptionKey);
    // ignore: deprecated_member_use
    expect(stored.apkamPrivateKey, isNotNull,
        reason: 'an rsa2048 keypair is copied into the flat fields too, so the '
            'completed keyfile reads as a legacy one would');
    // ignore: deprecated_member_use
    expect(stored.apkamPublicKey, isNotNull,
        reason: 'both halves of the keypair are copied');
    expect(stored.enrollmentInfo(enrollmentId)?.namespaces, {'wavi': 'rw'},
        reason: 'the snapshot filed at submission survives the completion');

    expect(client.enrollmentId, enrollmentId);
    expect(client.connection.current.isOnline, isTrue);
    await client.stop();
  });

  test(
      'a denial removes the pending keys, throws, and leaves the store ready '
      'for the next request', () async {
    final store = InMemoryAtKeysIo();
    final denying = atServer(
        decide: (_) async => throw UnAuthenticatedException(
            'Failed connecting to $atSign. error:AT0025:Apkam Auth Denied'));
    final pending = await submit(store, denying);

    await expectLater(
        () async => pending.client(await preference(),
            retryInterval: const Duration(milliseconds: 10),
            storage: hiveStoreFor(pending.atSign, await preference())),
        throwsA(isA<AtEnrollmentException>()
            .having((e) => e.message, 'message', contains('denied'))));

    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, isEmpty);
    expect(stored.enrollmentIds, isEmpty,
        reason: 'the slot and its snapshot are gone, not retired');
    expect(stored.holdsAuthenticationMaterial, isFalse);
    expect(stored.storedEnrollmentId, isNull,
        reason: 'the flat id the submission filed goes with the request');
    expect(stored.enrollmentSymmetricKey, isNull,
        reason: 'and so does its symmetric key, the store holding nothing '
            'else');

    // The emptied store takes the next request, which mints new keys.
    final again = await submit(store, atServer(decide: (_) async => true));
    expect(
        (await store.read(atSign)).pendingEnrollmentIds, [again.enrollmentId]);
  });

  test(
      'a denial whose pending keys the store cannot remove still throws the '
      'denial', () async {
    final store = _UpdateFailingStore();
    final pending = await submit(
        store,
        atServer(
            decide: (_) async => throw UnAuthenticatedException(
                'Failed connecting to $atSign. error:AT0025:Apkam Auth '
                'Denied')));
    store.failing = true;

    await expectLater(
        () => pending.awaitApproval(
            retryInterval: const Duration(milliseconds: 10)),
        throwsA(isA<AtEnrollmentException>()
            .having((e) => e.message, 'message', contains('denied'))));
  });

  test('a denial empties a file store too, which then takes the next request',
      () async {
    // The file store validates every rewrite against what it held; the
    // in-memory double does not, so it is the population for this.
    final path = '${dir.path}/${atSign}_key.atKeys';
    final store = FileAtKeysIo(filePath: (_) => path);
    final denying = atServer(
        decide: (_) async => throw UnAuthenticatedException(
            'Failed connecting to $atSign. error:AT0025:Apkam Auth Denied'));
    final pending = await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'wavi',
        device: 'phone',
        namespaces: {'wavi': 'rw'},
        keys: store,
        preference: await preference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: denying);

    await expectLater(
        () => pending.awaitApproval(
            retryInterval: const Duration(milliseconds: 10)),
        throwsA(isA<AtEnrollmentException>()));

    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, isEmpty,
        reason: 'the denied request is gone from the file on disk');
    expect(stored.enrollmentIds, isEmpty);

    final again = await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'wavi',
        device: 'phone',
        namespaces: {'wavi': 'rw'},
        keys: store,
        preference: await preference(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: atServer(decide: (_) async => true));
    expect(
        (await store.read(atSign)).pendingEnrollmentIds, [again.enrollmentId]);
  });

  test(
      'a failure other than a denial after the atServer approved leaves the '
      'pending keys, and a later wait completes them', () async {
    final store = InMemoryAtKeysIo();
    final pending = await submit(
        store, atServer(decide: (_) async => true, keyFetchesUnanswered: 1));

    await expectLater(
        pending.awaitApproval(retryInterval: const Duration(milliseconds: 10)),
        throwsA(isA<AtEnrollmentException>()
            .having((e) => e.message, 'message', isNot(contains('denied')))));
    expect((await store.read(atSign)).pendingEnrollmentIds, [enrollmentId],
        reason: 'only a denial removes the pending keys');

    await pending.awaitApproval(
        retryInterval: const Duration(milliseconds: 10));

    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, isEmpty);
    expect(stored.enrollmentToAuthenticateAs(), enrollmentId);
  });

  /// The `enroll:request` a submission under [posture] puts on the wire, as
  /// the atServer would decode it. Only the submission runs: the request is
  /// what decides how the symmetric key travels and what the enrollment
  /// advertises, and the atServer parks it pending.
  Future<Map<String, dynamic>> submittedUnder(PqPosture posture,
      {EnrollmentKeyExchangeMode? keyExchangeMode,
      SigningAlgoType? signingAlgo}) async {
    final lookUp = MockAtLookupImpl();
    final sent = <String>[];
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
      if (command.startsWith('enroll:request:')) {
        return 'data:${jsonEncode({
              'enrollmentId': 'shape-1',
              'status': 'pending'
            })}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
        return 'data:$encryptionPublicKey';
      }
      throw StateError('the mocked atServer has no answer for: '
          '${(builder as VerbBuilder).buildCommand()}');
    });
    when(() => lookUp.close()).thenAnswer((_) async {});

    await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'wavi',
        device: 'phone',
        namespaces: {'wavi': 'rw'},
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(posture: posture)
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = 1
          ..namespace = 'lifecycle',
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        keyExchangeMode: keyExchangeMode,
        signingAlgo: signingAlgo,
        atLookUp: lookUp);

    final command = sent.where((c) => c.startsWith('enroll:request:')).single;
    return jsonDecode(command.substring(
            command.indexOf('{'), command.lastIndexOf('}') + 1))
        as Map<String, dynamic>;
  }

  group('the posture decides the shape of the request', () {
    test(
        'legacy wraps the symmetric key, carries no key package, and '
        'advertises its authentication key', () async {
      final request = await submittedUnder(PqPosture.legacy);

      expect(request['signingAlgo'], 'rsa2048');
      expect(request['encryptedAPKAMSymmetricKey'], isNotNull,
          reason: 'the approver unwraps the key this request carries');
      expect(request['metadata'], isNull,
          reason: 'no key package: nothing is sealed to this enrollment');
      expect(request['apskLegacy'], request['apkamPublicKey'],
          reason: 'a legacy posture names no data signing algorithm, so the '
              'authentication key does both jobs');
      expect(request['apsk'], isNull);
    });

    test(
        'pqReady carries a key package instead of a wrapped key, and '
        'advertises an rsa2048 signing key of its own', () async {
      final request = await submittedUnder(PqPosture.pqReady);

      expect(request['signingAlgo'], 'mldsa65');
      expect(request['encryptedAPKAMSymmetricKey'], isNull,
          reason: 'nothing RSA-wrapped rides a pq request; the approver seals '
              'to the key package');
      expect(request['metadata']?['keyPackage'], isNotNull);
      expect(request['apskLegacy'], isNotNull);
      expect(request['apskLegacy'], isNot(request['apkamPublicKey']),
          reason: 'the enrollment owns a data signing key from its first '
              'byte, in the bare spelling an un-upgraded peer parses');
    });

    test(
        'pqActive advertises an mldsa65 signing key, in the structured '
        'spelling', () async {
      final request = await submittedUnder(PqPosture.pqActive);

      expect(request['encryptedAPKAMSymmetricKey'], isNull);
      expect(request['metadata']?['keyPackage'], isNotNull);
      expect(request['apskLegacy'], isNull);
      final keys = request['apsk']['keys'] as List;
      expect(keys.single['alg'], 'mldsa65');
      expect(keys.single['pub'], isNot(request['apkamPublicKey']));
    });

    test('a named mode overrides the posture in both directions', () async {
      final legacyUnderPq = await submittedUnder(PqPosture.pqActive,
          keyExchangeMode: EnrollmentKeyExchangeMode.legacy);
      expect(legacyUnderPq['encryptedAPKAMSymmetricKey'], isNotNull,
          reason: 'the escape hatch for a known-legacy approver');
      expect(legacyUnderPq['metadata'], isNull);
      expect((legacyUnderPq['apsk']['keys'] as List).single['alg'], 'mldsa65',
          reason: 'the mode decides how the key travels, not what the '
              'enrollment advertises');

      // NOTE: mldsa65 named too, since the legacy posture's rsa2048 is refused
      // with the pq exchange.
      final pqUnderLegacy = await submittedUnder(PqPosture.legacy,
          keyExchangeMode: EnrollmentKeyExchangeMode.pq,
          signingAlgo: SigningAlgoType.mldsa65);
      expect(pqUnderLegacy['encryptedAPKAMSymmetricKey'], isNull);
      expect(pqUnderLegacy['metadata']?['keyPackage'], isNotNull);
    });
  });

  /// Catalogue: features/at_client/pending_enrollment_cancel.feature
  group("PendingEnrollment's stop() and cancel()", () {
    /// Lets the event loop run until [done] holds, for at most five seconds.
    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the condition did not hold within five seconds');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    Never notYetDecided() => throw UnAuthenticatedException(
        'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed');

    const pollEvery = Duration(milliseconds: 10);

    /// A submission whose handshake connection the pending enrollment builds
    /// itself through its lookUps, rather than one the app supplied.
    Future<PendingEnrollment> submitOwning(
            WrittenAtKeysIo store, MockAtLookupImpl server) async =>
        Atsign(atSign).enroll(
            otp: 'ABC123',
            app: 'wavi',
            device: 'phone',
            namespaces: {'wavi': 'rw'},
            keys: store,
            preference: await preference(),
            lookUps: (
                    {required atSign,
                    required rootDomain,
                    required authenticator,
                    secondaryAddressFinder}) =>
                server,
            secondaryAddressFinder: await refusingAtDirectory());

    Future<AtClient> clientOf(PendingEnrollment pending) async =>
        pending.client(await preference(),
            retryInterval: pollEvery,
            storage: hiveStoreFor(pending.atSign, await preference()));

    test('Cancel ends a wait for approval', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submitOwning(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(allOf(isA<AtEnrollmentCancelledException>(),
              isA<AtEnrollmentException>())));
      await until(() => polls >= 1);

      await pending.cancel();
      await waiting;

      final atCancel = polls;
      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(polls, atCancel, reason: 'no further poll reaches the atServer');
      verify(() => server.stop()).called(1);
    });

    test(
        'Given a handshake connection whose stop fails, when the wait is '
        'cancelled, then the pending keys still leave the store', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      when(() => server.stop())
          .thenAnswer((_) async => throw Exception('the socket is gone'));
      final store = InMemoryAtKeysIo();
      final pending = await submitOwning(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      await until(() => polls >= 1);
      expect((await store.read(atSign)).pendingEnrollmentIds, isNotEmpty,
          reason: 'the precondition');

      await pending.cancel();
      await waiting;

      verify(() => server.stop()).called(1);
      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
    });

    test('Cancel leaves no copy of the pending keys beside a keyfile',
        () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final path = '${dir.path}/${atSign}_key.atKeys';
      final store = FileAtKeysIo(filePath: (_) => path);
      final pending = await submitOwning(store, server);
      final filed = await store.read(atSign);
      final pendingKeys = [
        for (final material in filed.keysForEnrollment(enrollmentId))
          material.bytes.toString(),
        filed.toJson()['apkamSymmetricKey'] as String,
      ];
      expect(pendingKeys, hasLength(greaterThan(2)),
          reason: 'the precondition: the submission filed its keys');
      expect(pendingKeys.every(File(path).readAsStringSync().contains), isTrue,
          reason: 'the control: each pending key is found in the text of '
              'the keyfile that holds it');
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      await until(() => polls >= 1);

      await pending.cancel();
      await waiting;

      expect(File('$path.bak').existsSync(), isTrue,
          reason: 'the file store keeps its copy beside the keyfile');
      for (final copy in [path, '$path.bak']) {
        final text = await File(copy).readAsString();
        for (final key in pendingKeys) {
          expect(text, isNot(contains(key)),
              reason: '$copy holds no pending key');
        }
        expect(
            (await FileAtKeysIo(filePath: (_) => copy).read(atSign))
                .pendingEnrollmentIds,
            isEmpty);
      }
    });

    test('An approval that arrives after cancel writes nothing', () async {
      var polls = 0;
      var approved = false;
      final server = atServer(decide: (_) async {
        polls++;
        return approved ? true : notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, server);
      final waiting = expectLater(
          clientOf(pending), throwsA(isA<AtEnrollmentCancelledException>()));
      await until(() => polls >= 1);

      await pending.cancel();
      await waiting;
      approved = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final stored = await store.read(atSign);
      expect(stored.enrollmentIds, isEmpty);
      expect(stored.holdsAuthenticationMaterial, isFalse);
      expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
          reason: 'no client is opened');
    });

    test('A cancel that lands between the atServer\'s approval and the write',
        () async {
      late PendingEnrollment pending;
      final server = atServer(
          decide: (_) async => true,
          onKeyFetch: () => unawaited(pending.cancel()));
      final store = InMemoryAtKeysIo();
      pending = await submit(store, server);

      await expectLater(pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));

      final stored = await store.read(atSign);
      expect(stored.pendingEnrollmentIds, isEmpty);
      expect(stored.enrollmentIds, isEmpty, reason: 'nothing is written');
      expect(stored.holdsAuthenticationMaterial, isFalse);
    });

    /// An atServer that approves at the first PKAM and holds the next, the
    /// opening client's own, completing [opening] and answering with [answer].
    MockAtLookupImpl approvesThenHolds(
            Completer<void> opening, Completer<bool> answer) =>
        atServer(decide: (attempt) async {
          if (attempt == 1) return true;
          if (!opening.isCompleted) opening.complete();
          return answer.future;
        });

    /// Opens the atSign again on [store], on a connection of its own, and
    /// answers what the open threw rather than throwing it.
    Future<Object> reopen(InMemoryAtKeysIo store) async => Atsign(atSign)
        .open(
            keys: store,
            preference: await preference(),
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: await refusingAtDirectory(),
            atLookUp: atServer(decide: (_) async => true),
            storage: hiveStoreFor(Atsign(atSign), await preference()))
        .then<Object>((client) => client, onError: (Object e) => e);

    /// Ends a wait with [end] while client() opens a client on the approval,
    /// and checks [end] returns once that client has stopped.
    Future<void> endWhileOpening(
        String end, Future<void> Function(PendingEnrollment) call,
        {required TypeMatcher<Exception> thrown}) async {
      final opening = Completer<void>();
      final answer = Completer<bool>();
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, approvesThenHolds(opening, answer));
      final opened = expectLater(
          clientOf(pending),
          throwsA(thrown.having((e) => e.toString(), 'message',
              contains('after its approval was written'))));
      await opening.future;

      final reopened = call(pending).then((_) => reopen(store));
      await pumpEventQueue();
      answer.complete(true);
      await opened;

      final again = await reopened;
      expect(again, isA<AtClient>(),
          reason: '$end returns once the client client() opened has stopped, '
              'so the atSign opens again on the approved keys at once');
      await (again as AtClient).stop();
      expect(pending.approved, isTrue);
      final stored = await store.read(atSign);
      expect(stored.enrollmentToAuthenticateAs(), enrollmentId,
          reason: 'the approved keys stay in the store');
      expect(stored.holdsAuthenticationMaterial, isTrue);
    }

    test('A cancel while client() opens the approved client', () async {
      await endWhileOpening('cancel', (pending) => pending.cancel(),
          thrown: isA<AtEnrollmentCancelledException>());
    });

    test('A second stop or cancel while the first waits for client()',
        () async {
      final opening = Completer<void>();
      final answer = Completer<bool>();
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, approvesThenHolds(opening, answer));
      final opened = expectLater(
          clientOf(pending), throwsA(isA<AtEnrollmentCancelledException>()));
      await opening.future;

      final liveAtReturn = <String, bool>{};
      Future<void> record(String call, Future<void> returned) =>
          returned.then((_) => liveAtReturn[call] =
              AtClientImpl.holdsLiveClientAs(atSign, enrollmentId));
      final calls = [
        record('stop', pending.stop()),
        record('a second stop', pending.stop()),
        record('cancel', pending.cancel()),
        record('a second cancel', pending.cancel()),
      ];
      await pumpEventQueue();
      answer.complete(true);
      await Future.wait(calls);
      await opened;

      expect(
          liveAtReturn,
          {
            'stop': false,
            'a second stop': false,
            'cancel': false,
            'a second cancel': false,
          },
          reason: 'each call returns only once the client client() opened '
              'has stopped');
    });

    /// Calls stop and cancel, in turn, from inside the [inside] that client()
    /// awaits, and checks each returns without waiting for client() to end.
    Future<void> endInsideClient(String inside) async {
      for (final (end, thrown) in [
        ('cancel', isA<AtEnrollmentCancelledException>()),
        ('stop', isA<StoppedException>()),
      ]) {
        final arm = '$end inside a $inside';
        late PendingEnrollment pending;
        var clientEnded = false;
        bool? endedWhenCallReturned;
        Future<void> endInside() async {
          await (end == 'cancel' ? pending.cancel() : pending.stop());
          endedWhenCallReturned ??= clientEnded;
        }

        final store = _StoreAwaitingOnce();
        final server = atServer(decide: (attempt) async {
          // NOTE: the second PKAM is the opening client's own, which client()
          // awaits.
          if (attempt == 2 && inside == 'connection') await endInside();
          return true;
        });
        pending = await submit(store, server);
        if (inside == 'key store') store.beforeUpdate = endInside;

        final outcome = await clientOf(pending)
            .whenComplete(() => clientEnded = true)
            .then<Object>((client) => client, onError: (Object e) => e)
            .timeout(const Duration(seconds: 10), onTimeout: () => 'hung');

        expect(outcome, isNot('hung'),
            reason: '$arm: client() ends; it cannot while the call waits for '
                'it');
        expect(endedWhenCallReturned, isFalse,
            reason: '$arm: the call returns without waiting for client() to '
                'end, which waits on the call');
        expect(outcome, thrown, reason: arm);
        expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
            reason: '$arm: client() stops any client it opened before it '
                'ends');
      }
    }

    test("A stop or cancel awaited inside client()'s own work, in a key store",
        () async {
      await endInsideClient('key store');
    });

    test("A stop or cancel awaited inside client()'s own work, in a connection",
        () async {
      await endInsideClient('connection');
    });

    test('Cancel after approval does nothing', () async {
      final server = atServer(decide: (_) async => true);
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, server);
      final client = await clientOf(pending);

      await pending.cancel();

      expect(AtClientImpl.holdsLiveClient(atSign), isTrue,
          reason: 'the client keeps running');
      expect(client.connection.current.isOnline, isTrue);
      final stored = await store.read(atSign);
      expect(stored.enrollmentToAuthenticateAs(), enrollmentId);
      expect(stored.holdsAuthenticationMaterial, isTrue);
      await client.stop();
    });

    test('A repeat cancel does nothing', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submitOwning(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      await until(() => polls >= 1);
      await pending.cancel();
      await waiting;
      final before = (await store.read(atSign)).toJson();

      await pending.cancel();

      expect((await store.read(atSign)).toJson(), before);
      verify(() => server.stop()).called(1);
    });

    /// A pending enrollment waiting in awaitApproval, in [store], with the
    /// wait's expected end.
    Future<({PendingEnrollment pending, Future<void> waiting})> waitingIn(
        WrittenAtKeysIo store) async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final pending = await submitOwning(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      await until(() => polls >= 1);
      return (pending: pending, waiting: waiting);
    }

    test('A cancel that cannot remove the pending keys throws', () async {
      final store = _UpdateFailingStore();
      final (:pending, :waiting) = await waitingIn(store);
      store.failing = true;

      await expectLater(pending.cancel(), throwsA(isA<FileSystemException>()));
      await waiting;
      expect((await store.read(atSign)).pendingEnrollmentIds, [enrollmentId],
          reason: 'the keys cancel could not remove are still there');
    });

    test('A cancel after one that failed removes the pending keys', () async {
      final store = _UpdateFailingStore();
      final (:pending, :waiting) = await waitingIn(store);
      store.failing = true;
      await expectLater(pending.cancel(), throwsA(isA<FileSystemException>()));
      await waiting;

      store.failing = false;
      await pending.cancel();

      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
    });

    /// Resumes the request in [store] for wavi on phone, over [server].
    Future<PendingEnrollment?> resume(
        InMemoryAtKeysIo store, MockAtLookupImpl server) async {
      final pref = await preference();
      return Atsign(atSign).resumeEnrollment(
          app: 'wavi',
          device: 'phone',
          keys: store,
          preference: pref,
          atLookUp: server,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(pref));
    }

    test('Stop ends a wait and keeps the request', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submitOwning(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<StoppedException>()));
      await until(() => polls >= 1);

      await pending.stop();
      await waiting;

      final atStop = polls;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(polls, atStop, reason: 'no further poll reaches the atServer');
      verify(() => server.stop()).called(1);
      expect((await store.read(atSign)).pendingEnrollmentIds, [enrollmentId]);
    });

    test('A stopped request resumes', () async {
      var polls = 0;
      var approved = false;
      final server = atServer(decide: (_) async {
        polls++;
        return approved ? true : notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<StoppedException>()));
      await until(() => polls >= 1);
      await pending.stop();
      await waiting;

      final resumed = await resume(store, server);
      approved = true;
      await resumed!.awaitApproval(retryInterval: pollEvery);

      expect(resumed.enrollmentId, enrollmentId);
      final stored = await store.read(atSign);
      expect(stored.pendingEnrollmentIds, isEmpty);
      expect(stored.holdsAuthenticationMaterial, isTrue);
    });

    test('Stop leaves a connection the app supplied open', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<StoppedException>()));
      await until(() => polls >= 1);

      await pending.stop();
      await waiting;

      verifyNever(() => server.stop());
      verifyNever(() => server.close());
    });

    test('A repeat stop does nothing', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submitOwning(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<StoppedException>()));
      await until(() => polls >= 1);
      await pending.stop();
      await waiting;
      final before = (await store.read(atSign)).toJson();

      await pending.stop();

      expect((await store.read(atSign)).toJson(), before);
      verify(() => server.stop()).called(1);
    });

    test('Stop before anyone waits', () async {
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, atServer(decide: (_) async => true));

      await pending.stop();

      await expectLater(pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<StoppedException>()));
      expect((await store.read(atSign)).pendingEnrollmentIds, [enrollmentId]);
    });

    test('Cancel after stop abandons', () async {
      final store = InMemoryAtKeysIo();
      final pending =
          await submit(store, atServer(decide: (_) async => notYetDecided()));
      await pending.stop();

      await pending.cancel();

      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
    });

    test(
        'An approval landing as stop does is not written, and the next resume '
        'completes it', () async {
      late PendingEnrollment pending;
      final server = atServer(
          decide: (_) async => true,
          onKeyFetch: () => unawaited(pending.stop()));
      final store = InMemoryAtKeysIo();
      pending = await submit(store, server);

      await expectLater(pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<StoppedException>()));
      expect((await store.read(atSign)).pendingEnrollmentIds, [enrollmentId],
          reason: 'nothing is written, and the request is kept');

      await (await resume(store, server))!
          .awaitApproval(retryInterval: pollEvery);

      final stored = await store.read(atSign);
      expect(stored.pendingEnrollmentIds, isEmpty);
      expect(stored.holdsAuthenticationMaterial, isTrue);
    });

    test('Stop while client() opens the approved client', () async {
      await endWhileOpening('stop', (pending) => pending.stop(),
          thrown: isA<StoppedException>());
    });

    test("An expired request's keys go, as a denial's do", () async {
      final store = InMemoryAtKeysIo();
      final pending = await submit(
          store,
          atServer(
              decide: (_) async => throw UnAuthenticatedException(
                  'Failed connecting to $atSign. error:AT0028:enrollment_id: '
                  '$enrollmentId is expired or invalid')));

      await expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentException>()
              .having((e) => e.message, 'message', contains('expired'))));

      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
    });

    /// A store holding two pending requests for app `wavi`, from devices named
    /// after their enrollment ids, `e-one` and `e-two`.
    AtKeys twoPending() {
      final keys = AtKeys(atsign: Atsign(atSign));
      final keyPair = RsaKeyPair.generate();
      for (final id in ['e-one', 'e-two']) {
        for (final (role, key) in [
          (
            CryptographicMaterialRole.privateAuthentication,
            keyPair.atPrivateKey.privateKey
          ),
          (
            CryptographicMaterialRole.publicAuthentication,
            keyPair.atPublicKey.publicKey
          ),
        ]) {
          keys.addKey(CryptographicMaterial(
              keyId: 'auth:rsa2048:1',
              enrollmentId: id,
              role: role,
              algorithm: CryptographicMaterialAlgorithm.rsa2048,
              bytes: AtBytes.fromString(key),
              createdAt: DateTime.now().toUtc(),
              status: CryptographicMaterialStatus.pending));
        }
        keys.recordEnrollmentSnapshot(id, appName: 'wavi', deviceName: id);
      }
      return keys;
    }

    test('The one pending enrollment resumes with no names', () async {
      final store = InMemoryAtKeysIo();
      await submit(store, atServer(decide: (_) async => true));
      final pref = await preference();

      final resumed = await Atsign(atSign).resumeEnrollment(
          keys: store,
          preference: pref,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(pref));

      expect(resumed?.enrollmentId, enrollmentId);
      expect(resumed?.app, 'wavi');
      expect(resumed?.device, 'phone');
    });

    test(
        'Resuming by one name refuses a store holding several requests it '
        'names', () async {
      final pref = await preference();
      Future<PendingEnrollment?> resume({String? app, String? device}) =>
          Atsign(atSign).resumeEnrollment(
              app: app,
              device: device,
              // ignore: invalid_use_of_visible_for_testing_member
              keys: InMemoryAtKeysIo.holding(atSign, twoPending()),
              preference: pref,
              lookUps: secureSocketLookUps(),
              secondaryAddressFinder: atDirectoryOf(pref));

      await expectLater(
          resume(app: 'wavi'),
          throwsA(isA<AtEnrollmentPendingException>().having(
              (e) => e.pendingEnrollmentIds,
              'pendingEnrollmentIds',
              unorderedEquals(['e-one', 'e-two']))));
      expect(
          (await resume(app: 'wavi', device: 'e-two'))?.enrollmentId, 'e-two');
      expect((await resume(device: 'e-one'))?.enrollmentId, 'e-one');
    });

    test(
        'Given a store holding two pending enrollments, when resumeEnrollment '
        'is given no names, then it throws AtEnrollmentPendingException '
        'naming both', () async {
      final keys = twoPending();
      final pref = await preference();

      await expectLater(
          Atsign(atSign).resumeEnrollment(
              // ignore: invalid_use_of_visible_for_testing_member
              keys: InMemoryAtKeysIo.holding(atSign, keys),
              preference: pref,
              lookUps: secureSocketLookUps(),
              secondaryAddressFinder: atDirectoryOf(pref)),
          throwsA(isA<AtEnrollmentPendingException>().having(
              (e) => e.pendingEnrollmentIds,
              'pendingEnrollmentIds',
              unorderedEquals(['e-one', 'e-two']))));
    });

    test('A connection the app supplied is left open', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, server);
      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      await until(() => polls >= 1);

      await pending.cancel();
      await waiting;

      final atCancel = polls;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(polls, atCancel, reason: 'no further poll runs on it');
      verifyNever(() => server.stop());
      verifyNever(() => server.close());
    });

    test('Cancel before anyone waits', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submit(store, server);

      await pending.cancel();

      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
      await expectLater(pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      expect(polls, 0);
    });

    test(
        'Given a cancel in the same turn as awaitApproval, then no poll '
        'reaches the atServer', () async {
      var polls = 0;
      final server = atServer(decide: (_) async {
        polls++;
        notYetDecided();
      });
      final store = InMemoryAtKeysIo();
      final pending = await submitOwning(store, server);

      final waiting = expectLater(
          pending.awaitApproval(retryInterval: pollEvery),
          throwsA(isA<AtEnrollmentCancelledException>()));
      await pending.cancel();
      await waiting;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(polls, 0, reason: 'no poll runs after cancel, on any connection');
      expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
    });

    group('A cancel and a denial at once', () {
      final logs = RecordedLogs();

      setUp(() {
        logs.records.clear();
        final handler = AtSignLogger.defaultLoggingHandler;
        final level = AtSignLogger.root_level;
        logs.installOn();
        addTearDown(() {
          AtSignLogger.defaultLoggingHandler = handler;
          AtSignLogger.root_level = level;
        });
      });

      Never denied() => throw UnAuthenticatedException(
          'Failed connecting to $atSign. error:AT0025:Apkam Auth Denied');

      Future<void> removedOnce(InMemoryAtKeysIo store) async {
        expect((await store.read(atSign)).pendingEnrollmentIds, isEmpty);
        expect(
            logs
                .at('INFO')
                .where((m) => m.contains('pending keys are removed')),
            hasLength(1),
            reason: 'the pending keys are removed once');
        expect(
            logs.at('WARNING').where((m) => m.contains('could not be removed')),
            isEmpty,
            reason: 'and nothing reports that they could not be');
      }

      test(
          'when cancel lands as the denial is answered, then the wait throws '
          'AtEnrollmentCancelledException and the pending keys are removed '
          'once', () async {
        late PendingEnrollment pending;
        final server = atServer(decide: (_) async {
          unawaited(pending.cancel());
          denied();
        });
        final store = InMemoryAtKeysIo();
        pending = await submit(store, server);

        await expectLater(pending.awaitApproval(retryInterval: pollEvery),
            throwsA(isA<AtEnrollmentCancelledException>()));
        await pending.cancel();

        await removedOnce(store);
      });

      test(
          'when cancel lands while the denial removes the pending keys, then '
          'they are removed once', () async {
        final store = _ReadHookedStore();
        final pending =
            await submit(store, atServer(decide: (_) async => denied()));
        final cancelled = Completer<void>();
        // NOTE: the wait's own read is the first; the denial's removal makes
        // the second.
        store.onRead = (reads) {
          if (reads == 2) cancelled.complete(pending.cancel());
        };

        await expectLater(pending.awaitApproval(retryInterval: pollEvery),
            throwsA(isA<AtEnrollmentException>()));
        expect(cancelled.isCompleted, isTrue,
            reason: 'the precondition: cancel landed during the wait');
        await cancelled.future;

        await removedOnce(store);
      });
    });
  });
}

/// An in-memory store whose updates fail as a keyfile's do when its lock is
/// held elsewhere, while [failing].
class _UpdateFailingStore extends InMemoryAtKeysIo {
  bool failing = false;

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    if (failing) {
      throw FileSystemException(
          'Could not acquire the keyfile lock within 0:00:10.000000. Nothing '
          'was written.');
    }
    return super.update(atsign, mutate);
  }
}

/// An in-memory store that calls [onRead] on every read once it is set, with
/// how many reads it has seen since.
class _ReadHookedStore extends InMemoryAtKeysIo {
  void Function(int reads)? _onRead;
  int _reads = 0;

  set onRead(void Function(int reads) onRead) {
    _reads = 0;
    _onRead = onRead;
  }

  @override
  FutureOr<AtKeys> read(String atsign) {
    _onRead?.call(++_reads);
    return super.read(atsign);
  }
}
