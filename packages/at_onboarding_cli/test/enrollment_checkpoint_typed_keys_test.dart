/// A checkpoint has to survive the key material an enrolment actually mints.
///
/// `enroll` saves one so an interrupted enrolment can resume, and the material
/// it saves is whatever the enrolment minted. Once that is TYPED — which it is
/// under any posture whose `authenticationKeyAlgorithm` is post-quantum, and
/// so under the shipped default — `AtKeys.toJson` refuses a document with no
/// `atsign`, because such a document does not say whose keys it holds.
///
/// This went unnoticed because the only post-quantum enrolment test drives
/// `sendEnrollRequest`, which never reaches a checkpoint: the save lives in
/// `enroll`. So `at_activate enroll --posture pqActive` threw here, on a path
/// nothing exercised.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/src/onboard/helpers/enrollment_checkpoint.dart';
import 'package:test/test.dart';

void main() {
  const atSign = '@checkpoint_typed';
  const enrollmentId = 'ckpt-enrollment-1';
  const appName = 'buzz';
  const deviceName = 'pixel';
  const namespaces = {'buzz': 'rw'};

  late Directory tempDir;
  late Directory previousCwd;

  setUp(() {
    // The checkpoint writes to Directory.current, so give it one of its own
    // rather than leaving files in the package root.
    previousCwd = Directory.current;
    tempDir = Directory.systemTemp.createTempSync('enrollment_checkpoint');
    Directory.current = tempDir;
  });

  tearDown(() {
    Directory.current = previousCwd;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// An enrolment response carrying TYPED key material, as a post-quantum
  /// enrolment mints — and with no `atsign` on the keys, which is the state
  /// `sendEnrollRequest` hands back.
  AtEnrollmentResponse typedResponse() {
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      ..enrollmentId = enrollmentId
      ..addKey(CryptographicMaterial(
        keyId: 'apkam:$enrollmentId:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.privateAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 7))),
        createdAt: now,
      ));
    expect(keys.atsign, isNull,
        reason: 'the premise: the response hands back keys naming no atSign, '
            'which is why the checkpoint has to supply one');
    return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.pending)
      ..atAuthKeys = keys;
  }

  test('a checkpoint round-trips typed key material', () async {
    final checkpoint = EnrollmentCheckpoint(atSign);

    await checkpoint.save(
        typedResponse(), appName, deviceName, namespaces);

    final loaded = checkpoint.load(appName, deviceName, namespaces);
    expect(loaded, isNotNull,
        reason: 'a checkpoint that cannot be read back is a checkpoint that '
            'never resumes anything');
    expect(loaded!.enrollmentId, enrollmentId);
    expect(loaded.atAuthKeys?.enrollmentIds, contains(enrollmentId),
        reason: 'the typed enrollment slot is the part that could not be '
            'serialized at all before, so it is the part to read back');
    expect(
        loaded.atAuthKeys?.authenticationAlgorithmFor(enrollmentId),
        SigningAlgoType.mldsa65,
        reason: 'and it must come back as the algorithm it went in as, or a '
            'resumed enrolment authenticates with the wrong routine');
  });

  test('legacy flat material still round-trips', () async {
    // The negative control. Flat material never needed an atSign — it takes
    // AtKeys.toJson's legacy branch — so a change made for typed material must
    // not have disturbed it.
    final checkpoint = EnrollmentCheckpoint(atSign);
    final response = AtEnrollmentResponse(enrollmentId, EnrollmentStatus.pending)
      ..atAuthKeys = (AtKeys()
        ..enrollmentId = enrollmentId
        // AtBytes.fromString base64-decodes, so this is 'flat-public' encoded.
        ..apkamPublicKey = AtBytes.fromString('ZmxhdC1wdWJsaWM='));

    await checkpoint.save(response, appName, deviceName, namespaces);

    final loaded = checkpoint.load(appName, deviceName, namespaces);
    expect(loaded?.atAuthKeys?.apkamPublicKey?.toString(), 'ZmxhdC1wdWJsaWM=');
  });
}
