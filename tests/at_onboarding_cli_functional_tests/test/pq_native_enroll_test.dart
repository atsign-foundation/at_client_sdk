import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart' show FileAtKeysIo;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart'
    show Atsign, AtsignLifecycle, PqPosture;
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/at_client_cache.dart';
import 'utils/lifecycle.dart';
import 'utils/test_keys_dir.dart';
import 'utils/virtualenv_ports.dart';

/// Proves that an app enrolling through `at_onboarding_cli` can be
/// post-quantum from birth, against a real atServer rather than against the
/// client's own belief.
///
/// ⚠️ One-shot server state: CRAM activation works once per atSign per
/// virtualenv, so `@curtly` is this file's alone.
void main() {
  final String atSign = AtUtils.fixAtSign('@curtly');
  final String masterKeysFilePath = testKeysFile(atSign);
  final logger = AtSignLogger('PqNativeEnroll');

  setUpAll(() async {
    // CRAM activation is one-shot per virtualenv: if this is not the first
    // run against this VE, recycle it before reading anything into a failure
    // here.
    await activateThroughCli(
        atSign,
        _preference(atSign, masterKeysFilePath)
          ..cramSecret = cramKeyMap[atSign]);

    // NOTE: every CLI command below builds its own client through
    // `createAtClient`, which mints a fresh storage path per call, and each
    // enrolment builds its own service for the same atSign. Without this
    // eviction they all run against the client the onboard left in the cache.
    await evictCachedAtClients();

    // A semi-permanent passcode, so each enrolment below does not need its own
    // freshly fetched OTP.
    expect(
        await runCliCommand([
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
    final preference = _preference(atSign, apkamKeysFilePath);

    final pending = await Atsign(atSign).enroll(
        otp: 'ABC123',
        app: 'buzz',
        device: label,
        namespaces: {'e2etest': 'rw'},
        keys: keyfileOf(preference),
        preference: preference,
        signingAlgo: signingAlgo);
    final enrollmentId = pending.enrollmentId;
    logger.info('$label: submitted $enrollmentId as ${signingAlgo.name}');

    // Approved by the real CLI, so the approver half of this is the shipped
    // code path rather than a hand-built call.
    expect(
        await runCliCommand([
          'approve', '-a', atSign, //
          '-r', 'vip.ve.atsign.zone', //
          '-i', enrollmentId, '-k', masterKeysFilePath,
        ]),
        0);

    // The approval completes the keyfile.
    await pending.awaitApproval();

    final keys =
        await FileAtKeysIo(filePath: (_) => apkamKeysFilePath).read(atSign);

    // A FRESH service, its client stopped afterwards: a client stays live in
    // this process until stopped, and a second open for the atSign is refused
    // while one is. At the legacy posture deliberately — authenticate()
    // builds a client, and at the SDK default that client retrofits an
    // rsa2048 enrolment on the spot, revoking the enrolment this helper hands
    // back.
    await evictCachedAtClients();
    final reader = AtOnboardingServiceImpl(atSign,
        _preference(atSign, apkamKeysFilePath, posture: PqPosture.legacy));
    final authenticated = await reader.authenticate();
    await reader.atClient?.stop();

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

  test(
      'an enrolment submitted as ML-DSA-65 is recorded and authenticates as '
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

    // ignore: deprecated_member_use
    expect(native.keys.apkamPublicKey, isNull,
        reason: 'a PQ-native keyfile keeps its APKAM in the typed section, as '
            'an activation does, so a reader that cannot handle a PQ '
            'enrollment fails loudly rather than signing an ML-DSA key with '
            'the RSA routine');

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

  // `authenticated == true` is a client opened at the legacy posture, which
  // retrofits nothing. `at_activate list` runs the shipped binary path: it
  // builds its own client through `createAtClient`, which names no posture
  // and so runs at the SDK default, retrofits the enrolment on the spot, and
  // then sends `enroll:list` with `auth: true` over the retrofitted client's
  // connection.
  //
  // The retrofit is asserted rather than assumed — the keyfile is read on both
  // sides, legacy shape before and typed ML-DSA material under a second
  // enrolment id after. That second read is the positive control, and it fails
  // first if the atServer stops auto-approving self-enrolments.
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

    // The verb, run on the retrofitted keyfile.
    expect(
        await runCliCommand([
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

    // ⚠️ A retrofitted atSign that never publishes its own namespace
    // advertisement can SEND post-quantum and cannot RECEIVE. at_client's own
    // routes publish one every time, so the CLI route is where the failure can
    // be observed.
    //
    // Read off the atServer with the master keys rather than through the
    // retrofitted client: the question is what the atSign PUBLISHED, and a
    // client that failed to publish would answer from its own cache.
    final published = await runCliCommand([
      'list', '-a', atSign, '-r', 'vip.ve.atsign.zone', //
      '-k', masterKeysFilePath,
    ]);
    expect(published, 0, reason: 'the master keys must still work');

    await evictCachedAtClients();
    final nskey = AtOnboardingServiceImpl(
        atSign, _preference(atSign, masterKeysFilePath));
    expect(await nskey.authenticate(), isTrue);
    final record = await nskey.atClient!
        .getRemoteSecondary()!
        .executeCommand('llookup:public:__nskey.e2etest$atSign\n', auth: true);
    stdout.writeln('##CLI## nskey after retrofit: '
        '${record?.substring(0, record.length.clamp(0, 80))}');
    expect(record, startsWith('data:'),
        reason: 'REPORTED DEFECT: the retrofitted enrolment is authorised for '
            'e2etest, so the atSign must publish public:__nskey.e2etest — '
            'without it no peer can seal anything to this atSign and it can '
            'send post-quantum without being able to receive');
  }, timeout: Timeout(Duration(minutes: 6)));
}

AtOnboardingPreference _preference(String atSign, String atKeysFilePath,
        {PqPosture? posture}) =>
    (posture == null
        ? AtOnboardingPreference()
        : AtOnboardingPreference(posture: posture))
      ..namespace = 'buzz'
      ..atKeysFilePath = atKeysFilePath
      ..appName = 'buzz'
      ..deviceName = 'iphone'
      ..rootDomain = 'vip.ve.atsign.zone'
      ..rootPort = virtualenvRootPort;
