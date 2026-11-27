import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator, AtLookupMuxable;
import 'package:test/test.dart';

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

/// `Atsign.resumeEnrollment` refuses keys it cannot use as `Atsign.open`
/// does, before any connection.
///
/// Catalogue: features/at_client/pending_enrollment_cancel.feature
///
/// A resume that must make no connection is given a `lookUps` that records
/// every connection it is asked to build and an atDirectory that records
/// every atSign it is asked for.
void main() {
  const atSign = '@alice';
  const otherAtSign = '@bob';
  late Directory dir;
  late String path;
  late List<String> built;
  late _RecordingAtDirectory atDirectory;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('resume_unusable_keys_');
    path = '${dir.path}/keys/${atSign}_key.atKeys';
    built = [];
    atDirectory = _RecordingAtDirectory();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Records each connection it is asked to build, and builds none.
  AtLookupMuxable recordingLookUps(
      {required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder}) {
    built.add(atSign);
    throw StateError('no connection was expected for $atSign');
  }

  /// [atSign]'s resume of the enrollment the keyfile at the test's path holds.
  Future<PendingEnrollment?> resume(String atSign) =>
      Atsign(atSign).resumeEnrollment(
          keys: FileAtKeysIo(filePath: (_) => path),
          preference: AtClientPreference()
            ..rootDomain = InternetAddress.loopbackIPv4.address
            ..rootPort = 1,
          lookUps: recordingLookUps,
          secondaryAddressFinder: atDirectory);

  void expectNoConnection() {
    expect(built, isEmpty, reason: 'no connection is built');
    expect(atDirectory.asked, isEmpty, reason: 'the atDirectory is not asked');
  }

  test('A resume refuses keys it cannot read, as open does', () async {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('{"not json');

    await expectLater(
        resume(atSign),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
            .having((e) => e.source, 'source', path)
            .having((e) => e.error, 'error', isA<AtKeysFormatException>())
            .having(
                (e) => e.message,
                'message',
                startsWith('The keys for $atSign in the AtKeys store ($path) '
                    'could not be read: it is not valid JSON'))),
        reason: 'it throws AtKeysUnusableException with cause unreadable, '
            'naming the AtKeys store');
    expectNoConnection();
  });

  test('A resume refuses keys recorded for another Atsign', () async {
    await FileAtKeysIo(filePath: (_) => path).write(
        otherAtSign,
        AtKeys(atsign: Atsign(otherAtSign))
          ..addKey(CryptographicMaterial(
              keyId: 'apkam:e-bob:1',
              enrollmentId: 'e-bob',
              role: CryptographicMaterialRole.privateAuthentication,
              algorithm: CryptographicMaterialAlgorithm.rsa2048,
              bytes: AtBytes.fromString(base64Encode(List.filled(32, 3))),
              createdAt: DateTime.now().toUtc(),
              status: CryptographicMaterialStatus.pending))
          ..recordEnrollmentSnapshot('e-bob',
              appName: 'buzz', deviceName: 'phone'));
    expect((await resume(otherAtSign))?.enrollmentId, 'e-bob',
        reason: "the control: the keyfile holds @bob's pending enrollment, "
            'which a resume for @bob finds');
    final before = File(path).readAsBytesSync();

    await expectLater(
        resume(atSign),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.anotherAtsign)
            .having((e) => e.source, 'source', path)
            .having(
                (e) => e.message,
                'message',
                'The keys in the AtKeys store ($path) are for $otherAtSign, '
                    'not $atSign.')),
        reason: 'it throws AtKeysUnusableException with cause anotherAtsign');
    expect(File(path).readAsBytesSync(), before,
        reason: 'the store is unchanged');
    expectNoConnection();
  });
}
