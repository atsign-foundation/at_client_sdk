import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart' show FileAtKeysIo;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart' show PqPosture;
import 'package:at_commons/at_commons.dart' show EnrollmentStatus;
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/test_keys_dir.dart';

/// An app enrolling through `at_onboarding_cli` can be post-quantum from
/// birth — asserted against a real atServer, not against the client's own
/// belief.
///
/// Until `AtEnrollmentRequest` carried a `signingAlgo`, it could not. The OTP
/// enrolment path minted RSA-2048 unconditionally, so on an atSign whose
/// deployment had moved to post-quantum every install created an
/// RSA-authenticating enrollment which the client then retrofitted away on its
/// first start: a discarded enrollment per install, and an RSA credential live
/// for the atServer's grace window on an atSign that believed it had left RSA
/// behind. `--posture` was accepted by `enroll` the whole time and changed
/// nothing about the key that was minted.
///
/// **The load-bearing assertion is the authentication, not the keyfile.** PKAM
/// is record-authoritative: the atServer judges a signature against the
/// algorithm on the enrollment record, and the record is written from what the
/// enrol request carried. A client holding ML-DSA-65 material that
/// authenticates successfully has therefore proved the algorithm reached the
/// server — which reading its own keyfile back could never show.
///
/// ⚠️ **One-shot server state.** CRAM activation works once per atSign per
/// virtualenv, so `@curtly` is this file's alone. It is claimed by nothing else
/// in the repo — checked before it was chosen — and borrowing an atSign another
/// file onboards makes that file fail rather than this one.
void main() {
  final String atSign = AtUtils.fixAtSign('@curtly');
  final String masterKeysFilePath = testKeysFile(atSign);
  final logger = AtSignLogger('PqNativeEnroll');

  setUpAll(() async {
    final onboardingService = AtOnboardingServiceImpl(
        atSign,
        _preference(atSign, masterKeysFilePath)
          ..cramSecret = cramKeyMap[atSign]);
    expect(await onboardingService.onboard(), true,
        reason: 'CRAM onboarding of $atSign failed. It is one-shot per '
            'virtualenv, so if this is not the first run against this VE, '
            'recycle it before reading anything into the failure');

    // A semi-permanent passcode, so each enrolment below does not need its own
    // freshly fetched OTP — the same shape the other CLI command tests use.
    expect(
        await auth_cli.wrappedMain([
          'spp', '-s', 'ABC123', //
          '-a', atSign, '-r', 'vip.ve.atsign.zone', //
          '-k', masterKeysFilePath,
        ]),
        0);
  });

  /// Enrols one app under [signingAlgo], approves it **through the CLI**, and
  /// reports what the keyfile holds and whether authenticating as it worked.
  Future<({AtKeys keys, String enrollmentId, bool authenticated})> enrolAt(
      SigningAlgoType signingAlgo, String label) async {
    final apkamKeysFilePath = testKeysFile(atSign, suffix: label);
    final service = AtOnboardingServiceImpl(
        atSign, _preference(atSign, apkamKeysFilePath));

    final response = await service.sendEnrollRequest(
        'buzz', label, 'ABC123', {'e2etest': 'rw'},
        signingAlgo: signingAlgo);
    final enrollmentId = response.enrollmentId;
    expect(response.enrollStatus, EnrollmentStatus.pending);
    logger.info('$label: submitted $enrollmentId as ${signingAlgo.name}');

    // Approved by the real CLI, so the approver half of this is the shipped
    // code path rather than a hand-built call.
    expect(
        await auth_cli.wrappedMain([
          'approve', '-a', atSign, //
          '-r', 'vip.ve.atsign.zone', //
          '-i', enrollmentId, '-k', masterKeysFilePath,
        ]),
        0);

    await service.awaitApproval(response);
    await service.createAtKeysFile(response,
        atKeysFile: File(apkamKeysFilePath));

    final keys =
        await FileAtKeysIo(filePath: (_) => apkamKeysFilePath).read(atSign);

    // A FRESH service: an AtOnboardingService binds to the enrollment it last
    // authenticated as, so reusing one across enrolments fetches keys it is
    // not authorized to read.
    final authenticated = await AtOnboardingServiceImpl(
            atSign, _preference(atSign, apkamKeysFilePath))
        .authenticate(enrollmentId: enrollmentId);

    stdout.writeln('##CLI## $label (${signingAlgo.name}): id=$enrollmentId '
        'keyfileAlgo=${keys.authenticationAlgorithmFor(enrollmentId)} '
        'authenticated=$authenticated');
    return (
      keys: keys,
      enrollmentId: enrollmentId,
      authenticated: authenticated
    );
  }

  test('an enrolment submitted as ML-DSA-65 is recorded and authenticates as '
      'ML-DSA-65, while the RSA default still does what it always did',
      () async {
    final native = await enrolAt(
        PqPosture.pqActive.authenticationKeyAlgorithm, 'pqnative');

    expect(native.keys.authenticationAlgorithmFor(native.enrollmentId),
        SigningAlgoType.mldsa65,
        reason: 'the enrolment was submitted as mldsa65, so the keyfile must '
            'hold ML-DSA-65 typed authentication material under that id. '
            'Nothing there means the algorithm never reached the wire and the '
            'atServer recorded the absent-field default');

    // The flat fields hold the SAME keypair, and that is deliberate: one
    // enrollment, named by the keyfile's own enrollmentId, so flat and typed
    // resolve to one key. What must not happen is them naming DIFFERENT
    // enrollments, which is a retrofitted keyfile and not this.
    // ignore: deprecated_member_use
    expect(native.keys.apkamPublicKey, isNotNull,
        reason: 'the flat fields carry this enrollment\'s keypair too, so the '
            'approval handshake can build one AtChops holding both it and the '
            'symmetric key');

    // The assertion about the SERVER rather than about this process.
    expect(native.authenticated, isTrue,
        reason: 'authenticating as the enrolled id failed while the client '
            'holds ML-DSA-65 material. PKAM is judged against the algorithm on '
            'the enrollment RECORD, so this is the atServer disagreeing — the '
            'request reached it without an algorithm, or with the wrong one');

    // The control. Without it, "recorded as mldsa65" would pass just as well
    // for a build that recorded mldsa65 for every enrolment.
    final legacy = await enrolAt(SigningAlgoType.rsa2048, 'legacyalgo');

    expect(legacy.keys.authenticationAlgorithmFor(legacy.enrollmentId), isNull,
        reason: 'an rsa2048 enrolment keeps its APKAM keypair in the FLAT '
            'fields and files no typed authentication material — the shape '
            'every published reader expects. Typed material here would mean '
            'the algorithm is being applied to a request that did not ask');
    // ignore: deprecated_member_use
    expect(legacy.keys.apkamPublicKey, isNotNull,
        reason: 'the rsa2048 arm must populate the flat fields');
    expect(legacy.authenticated, isTrue,
        reason: 'the rsa2048 arm must still authenticate, or this file is '
            'measuring a broken enrolment path rather than an algorithm');
  }, timeout: Timeout(Duration(minutes: 6)));
}

AtOnboardingPreference _preference(String atSign, String atKeysFilePath) =>
    AtOnboardingPreference()
      ..namespace = 'buzz'
      ..atKeysFilePath = atKeysFilePath
      ..appName = 'buzz'
      ..deviceName = 'iphone'
      ..rootDomain = 'vip.ve.atsign.zone';
