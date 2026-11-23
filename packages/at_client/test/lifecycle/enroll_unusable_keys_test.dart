import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator, AtLookupMuxable;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/recorded_logs.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// An atDirectory that records each atSign it is asked for and answers none.
class _RecordingAtDirectory implements SecondaryAddressFinder {
  final List<String> asked = [];

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    asked.add(atSign);
    throw SecondaryNotFoundException('asked for $atSign');
  }
}

/// A failure whose text has a control character and a second line.
class _WriteRefused implements Exception {
  @override
  String toString() => 'the platform refused the write\u001b[0m\nsecond line';
}

/// An in-memory AtKeys store whose every write fails with [error], an
/// [Error].
class _StoreFailingWithError extends InMemoryAtKeysIo {
  final error = StateError('the store has a defect');

  @override
  Future<void> write(String atsign, AtKeys atKeys) async => throw error;
}

/// An in-memory AtKeys store whose every write fails with [_WriteRefused].
class _StoreRefusingWrites extends InMemoryAtKeysIo {
  @override
  Future<void> write(String atsign, AtKeys atKeys) async =>
      throw _WriteRefused();
}

/// `Atsign.enroll` checks the AtKeys store before it sends the request, and
/// names a request it sent and could not file.
///
/// Catalogue: features/at_client/enroll_checks_store.feature
///
/// An enroll that must send nothing is given a `lookUps` that records every
/// connection it is asked to build and an atDirectory that records every
/// atSign it is asked for. One that sends is given an atServer double that
/// accepts the request.
void main() {
  const atSign = '@alice🛠';
  const otherAtSign = '@bob🛠';
  final canChmod = !Platform.isWindows &&
      (Process.runSync('id', ['-u']).stdout as String).trim() != '0';
  late Directory dir;
  late String path;
  late List<String> built;
  late _RecordingAtDirectory atDirectory;
  final logs = RecordedLogs();

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    logs.installOn(level: 'warning');
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('enroll_unusable_keys_');
    path = '${dir.path}/keys/${atSign}_key.atKeys';
    built = [];
    atDirectory = _RecordingAtDirectory();
  });

  tearDown(() {
    if (!Platform.isWindows) Process.runSync('chmod', ['-R', 'u+w', dir.path]);
    dir.deleteSync(recursive: true);
  });

  /// Records each connection it is asked to build, and builds none.
  AtLookupMuxable recordingLookUps(
      {required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder}) {
    built.add(atSign);
    throw StateError('no connection was expected for $atSign');
  }

  /// An atServer that accepts each request as [id], recording in [sent] each
  /// `enroll:` command it is sent and running [onEnroll] before it answers.
  MockAtLookupImpl acceptingAtServer(List<String> sent,
      {String id = 'e-1', Future<void> Function()? onEnroll}) {
    final lookUp = MockAtLookupImpl();
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      if (command.startsWith('enroll:')) {
        sent.add(command);
        await onEnroll?.call();
        return 'data:${jsonEncode({'enrollmentId': id, 'status': 'pending'})}';
      }
      throw StateError('the atServer double has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
        return 'data:${demo.encryptionPublicKeyMap[atSign]!}';
      }
      throw StateError('the atServer double has no answer for: '
          '${(builder as VerbBuilder).buildCommand()}');
    });
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(lookUp.stop).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return lookUp;
  }

  /// [atSign]'s enrollment into [keys], sent on [atLookUp] when given and
  /// otherwise on a connection [recordingLookUps] refuses to build.
  Future<PendingEnrollment> enroll(String atSign, WrittenAtKeysIo keys,
          {AtLookupMuxable? atLookUp}) =>
      Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: 'phone',
          namespaces: {'wavi': 'rw'},
          keys: keys,
          preference: AtClientPreference()
            ..rootDomain = InternetAddress.loopbackIPv4.address
            ..rootPort = 1
            ..namespace = 'lifecycle',
          lookUps: recordingLookUps,
          secondaryAddressFinder: atDirectory,
          atLookUp: atLookUp);

  void expectNothingSent() {
    expect(built, isEmpty, reason: 'no connection is built');
    expect(atDirectory.asked, isEmpty, reason: 'the atDirectory is not asked');
  }

  CryptographicMaterial material(
          CryptographicMaterialRole role, CryptographicMaterialStatus status) =>
      CryptographicMaterial(
          keyId: 'apkam:e-bob:1',
          enrollmentId: 'e-bob',
          role: role,
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
          bytes: AtBytes.fromString(base64Encode(List.filled(32, 3))),
          createdAt: DateTime.now().toUtc(),
          status: status);

  test('An enroll refuses keys it cannot read, before anything is sent',
      () async {
    for (final (text, reason) in [
      ('{"not json SECRET', 'it is not valid JSON'),
      ('{"version": "SECRET"}', 'Expected integer in version'),
    ]) {
      built.clear();
      atDirectory.asked.clear();
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

      await expectLater(
          enroll(atSign, FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<AtKeysUnusableException>()
              .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
              .having((e) => e.source, 'source', path)
              .having(
                  (e) => e.message,
                  'message',
                  allOf(
                      startsWith('The keys for $atSign in the AtKeys store '
                          '($path) could not be read: $reason'),
                      isNot(contains('SECRET'))))),
          reason: 'a keyfile holding "$text" is refused as unreadable, '
              'holding none of its contents');
      expectNothingSent();
    }
  });

  test(
      'An enroll refuses keys recorded for another Atsign, before anything '
      'is sent', () async {
    final live = AtKeys(atsign: Atsign(otherAtSign))
      ..addKey(material(CryptographicMaterialRole.privateAuthentication,
          CryptographicMaterialStatus.active))
      ..addKey(material(CryptographicMaterialRole.publicAuthentication,
          CryptographicMaterialStatus.active))
      ..recordEnrollmentSnapshot('e-bob', appName: 'buzz', deviceName: 'phone');
    final pending = AtKeys(atsign: Atsign(otherAtSign))
      ..addKey(material(CryptographicMaterialRole.privateAuthentication,
          CryptographicMaterialStatus.pending))
      ..recordEnrollmentSnapshot('e-bob', appName: 'buzz', deviceName: 'phone');
    final cases = <String, Future<void> Function()>{
      "@bob's live keys": () =>
          FileAtKeysIo(filePath: (_) => path).write(otherAtSign, live),
      "@bob's pending enrollment": () =>
          FileAtKeysIo(filePath: (_) => path).write(otherAtSign, pending),
      // NOTE: no writer leaves a typed document holding nothing, so it is
      // written by hand.
      'nothing': () async => File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'version': 1,
          'atsign': otherAtSign,
          'keys': <Object>[],
          'enrollments': <Object>[],
        })),
    };
    for (final MapEntry(key: held, value: fileIt) in cases.entries) {
      built.clear();
      atDirectory.asked.clear();
      if (File(path).existsSync()) File(path).deleteSync();
      await fileIt();
      expect((await FileAtKeysIo(filePath: (_) => path).read(atSign)).atsign,
          Atsign(otherAtSign),
          reason: 'the control: the keyfile holding $held records @bob');
      final before = File(path).readAsBytesSync();

      await expectLater(
          enroll(atSign, FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<AtKeysUnusableException>()
              .having(
                  (e) => e.cause, 'cause', AtKeysUnusableCause.anotherAtsign)
              .having((e) => e.source, 'source', path)
              .having(
                  (e) => e.message,
                  'message',
                  'The keys in the AtKeys store ($path) are for $otherAtSign, '
                      'not $atSign.')),
          reason: 'a keyfile recorded for @bob holding $held is refused as '
              "another Atsign's");
      expect(File(path).readAsBytesSync(), before,
          reason: 'the store holding $held is unchanged');
      expectNothingSent();
    }
  });

  test(
      'An enroll refuses an AtKeys store it cannot write, before anything is '
      'sent', () async {
    final keys = Directory('${dir.path}/keys')..createSync();
    Process.runSync('chmod', ['555', keys.path]);

    await expectLater(
        enroll(atSign, FileAtKeysIo(filePath: (_) => path)),
        throwsA(isA<FileSystemException>()
            .having((e) => e.path, 'path', path)
            .having((e) => e.message, 'message',
                startsWith('Cannot write the atKeys file'))),
        reason: "the store's refusal names the keyfile's path");
    expect(File(path).existsSync(), isFalse, reason: 'nothing is written');
    expectNothingSent();
  }, skip: canChmod ? null : 'needs a directory chmod can make unwritable');

  group(
      'A request that was sent and cannot be filed names the enrollment it '
      'sent', () {
    test(
        'a keyfile for @alice that a denial left empty, in a directory that '
        'cannot be written', () async {
      final keys = FileAtKeysIo(filePath: (_) => path);
      final first = await enroll(atSign, keys,
          atLookUp: acceptingAtServer([], id: 'e-0'));
      // NOTE: a cancel empties the keyfile as a denial does.
      await first.cancel();
      expect((await keys.read(atSign)).pendingEnrollmentIds, isEmpty,
          reason: 'the control: the keyfile holds no request');
      final before = File(path).readAsBytesSync();
      Process.runSync('chmod', ['555', File(path).parent.path]);
      final sent = <String>[];

      await expectLater(
          enroll(atSign, keys, atLookUp: acceptingAtServer(sent)),
          throwsA(isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              allOf(
                  startsWith('the atSign\'s manager can deny enrollment "e-1" '
                      'of $atSign, which is not filed: filing it in the '
                      'AtKeys store ($path) failed: '),
                  contains('Cannot create the lock'),
                  isNot(contains('\n'))))),
          reason: 'the refusal names the enrollment it sent');
      expect(sent, hasLength(1), reason: 'the request was sent');
      expect(File(path).readAsBytesSync(), before,
          reason: 'the store is unchanged');
    }, skip: canChmod ? null : 'needs a directory chmod can make unwritable');

    test('an AtKeys store for @alice whose write fails', () async {
      final keys = _StoreRefusingWrites();
      final sent = <String>[];

      await expectLater(
          enroll(atSign, keys, atLookUp: acceptingAtServer(sent)),
          throwsA(isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              'the atSign\'s manager can deny enrollment "e-1" of $atSign, '
                  'which is not filed: filing it in the AtKeys store failed: '
                  r'the platform refused the write\u001b[0m')),
          reason: 'the refusal names the enrollment it sent, and the first '
              "line of the store's failure, escaped");
      expect(sent, hasLength(1), reason: 'the request was sent');
      await expectLater(
          () => keys.read(atSign), throwsA(isA<AtKeysSourceAbsentException>()),
          reason: 'the store is unchanged');
    });
  });

  test(
      'An Error while filing a sent request is rethrown, and logged naming the '
      'enrollment', () async {
    final keys = _StoreFailingWithError();
    final sent = <String>[];

    await expectLater(enroll(atSign, keys, atLookUp: acceptingAtServer(sent)),
        throwsA(same(keys.error)),
        reason: 'the Error is rethrown as it is');
    expect(sent, hasLength(1), reason: 'the request was sent');
    expect(
        logs.at('SEVERE'),
        contains('enrollment "e-1" of $atSign was sent and is not filed in '
            'the AtKeys store, because of a defect: Bad state: the store has '
            'a defect'),
        reason: 'the severe log names the sent enrollment');
    await expectLater(
        () => keys.read(atSign), throwsA(isA<AtKeysSourceAbsentException>()),
        reason: 'the store is unchanged');
  });

  test(
      'Given no keys for @alice yet, when live keys are written while the '
      'request is being sent, then it is not filed and the live keys stay',
      () async {
    final keys = InMemoryAtKeysIo();
    final live = AtKeys.legacy(
        apkamPublicKey: demo.pkamPublicKeyMap[atSign]!,
        apkamPrivateKey: demo.pkamPrivateKeyMap[atSign]!);
    final sent = <String>[];

    await expectLater(
        enroll(atSign, keys,
            atLookUp: acceptingAtServer(sent,
                onEnroll: () => keys.write(atSign, live))),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e.message,
            'message',
            'the atSign\'s manager can deny enrollment "e-1" of $atSign, '
                'which is not filed: $atSign gained live keys in the AtKeys '
                'store while it was being sent')),
        reason: 'the refusal reaches the caller as it is, not wrapped as a '
            'failure of the filing');
    expect(sent, hasLength(1), reason: 'the request was sent');
    final stored = await keys.read(atSign);
    expect(stored.holdsAuthenticationMaterial, isTrue);
    expect(stored.pendingEnrollmentIds, isEmpty);
  });
}
