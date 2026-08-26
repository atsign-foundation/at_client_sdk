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
  Future<
      ({
        AtKeys keys,
        String enrollmentId,
        bool authenticated,
        String keysFilePath
      })> enrolAt(SigningAlgoType signingAlgo, String label) async {
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
      authenticated: authenticated,
      keysFilePath: apkamKeysFilePath
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

  /// ⛔ **The arm that was missing, and its absence is why the defect shipped.**
  ///
  /// The test above ends at `authenticated == true`, and that is at_auth's own
  /// connection reporting success — a connection built before the client
  /// exists. The client is built afterwards, retrofits itself, and every verb
  /// runs over a DIFFERENT connection. So a legacy enrolment could authenticate
  /// and then be unable to do anything, with nothing in this pack noticing.
  ///
  /// `at_activate list` is the reported reproduction, run here as the shipped
  /// binary path rather than as a hand-built call: it builds its own client
  /// through `createAtClient`, which names no posture and so runs at the SDK
  /// default, and then sends `enroll:list` with `auth: true`.
  ///
  /// **The retrofit is asserted, not assumed.** A green from a run where the
  /// retrofit never happened would say nothing at all, so the keyfile is read
  /// on both sides: legacy shape before, and typed ML-DSA material under a
  /// second enrolment id after. That second read is this test's positive
  /// control, and it is the thing that fails first if the atServer stops
  /// auto-approving self-enrolments.
  test('a legacy enrolment that retrofits at start can still run a verb',
      () async {
    final legacy = await enrolAt(SigningAlgoType.rsa2048, 'retrofitverb');

    expect(legacy.authenticated, isTrue,
        reason: 'the precondition: this enrolment authenticates before '
            'anything retrofits it. Without it a red below could be an '
            'enrolment that was never usable');
    expect(legacy.keys.authenticationAlgorithmFor(legacy.enrollmentId), isNull,
        reason: 'the other precondition: an rsa2048 enrolment keeps its '
            'keypair in the flat fields and files no typed authentication '
            'material. Typed material here means the retrofit already ran and '
            'the comparison below has nothing left to vary');

    // The reported command, on the retrofitted keyfile.
    expect(
        await auth_cli.wrappedMain([
          'list', '-a', atSign, //
          '-r', 'vip.ve.atsign.zone', //
          '-k', legacy.keysFilePath,
        ]),
        0,
        reason: 'at_activate list authenticates and then sends enroll:list '
            'over the client\'s own connection. A client that retrofitted '
            'during its init runs as the new enrolment and must sign with the '
            'new enrolment\'s key; signing with the one at_auth resolved '
            'before the move reaches at_chops as "this PKAM key is ~1218 '
            'bytes, and an ML-DSA-65 secret key is 4032" and the verb never '
            'goes out');

    // The positive control: the keyfile really did move, so the green above is
    // about a retrofitted client rather than about one that stayed put.
    final after =
        await FileAtKeysIo(filePath: (_) => legacy.keysFilePath).read(atSign);
    final retrofittedIds =
        after.enrollmentIds.where((id) => id != legacy.enrollmentId).toSet();
    expect(retrofittedIds, isNotEmpty,
        reason: 'the SDK default posture asks for mldsa65 and this enrolment '
            'holds rsa2048, so the client must have retrofitted onto a second '
            'enrolment and written its material here. Nothing new in the '
            'keyfile means no retrofit ran, and the assertion above then '
            'proves only that an unretrofitted client works');
    for (final id in retrofittedIds) {
      expect(after.authenticationAlgorithmFor(id), SigningAlgoType.mldsa65,
          reason: 'the retrofit exists to move the authentication key, so the '
              'enrolment it created has to hold ML-DSA-65 material');
    }

    // ⚠️ **Reported 2026-08-26 from a live ephemeral environment**: a
    // retrofitted atSign never publishes its own namespace advertisement, so
    // it can SEND post-quantum and cannot RECEIVE. It does not reproduce on
    // at_client's own routes — `pq_retrofitted_scope_test.dart` in the
    // functional pack retrofits both in-process and cold from a keyfile, at
    // pqReady and at pqActive, and publishes one every time, with the negative
    // control proven. The CLI route is the difference that is left, and this
    // is where it can be observed.
    //
    // Read off the atServer with the master keys rather than through the
    // retrofitted client: the question is what the atSign PUBLISHED, and a
    // client that failed to publish would answer from its own cache.
    final published = await auth_cli.wrappedMain([
      'list', '-a', atSign, '-r', 'vip.ve.atsign.zone', //
      '-k', masterKeysFilePath,
    ]);
    expect(published, 0, reason: 'the master keys must still work');

    final nskey = await AtOnboardingServiceImpl(
        atSign, _preference(atSign, masterKeysFilePath));
    expect(await nskey.authenticate(), isTrue);
    final record = await nskey.atLookUp!.executeCommand(
        'llookup:public:__nskey.e2etest$atSign\n',
        auth: true);
    stdout.writeln('##CLI## nskey after retrofit: '
        '${record?.substring(0, record.length.clamp(0, 80))}');
    expect(record, startsWith('data:'),
        reason: 'REPORTED DEFECT: the retrofitted enrolment is authorised for '
            'e2etest, so the atSign must publish public:__nskey.e2etest — '
            'without it no peer can seal anything to this atSign and it can '
            'send post-quantum without being able to receive');
  }, timeout: Timeout(Duration(minutes: 6)));
}

AtOnboardingPreference _preference(String atSign, String atKeysFilePath) =>
    AtOnboardingPreference()
      ..namespace = 'buzz'
      ..atKeysFilePath = atKeysFilePath
      ..appName = 'buzz'
      ..deviceName = 'iphone'
      ..rootDomain = 'vip.ve.atsign.zone';
