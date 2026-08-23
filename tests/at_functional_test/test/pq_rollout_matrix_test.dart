// Sixteen cells, each two client startups against a live atServer.
@Timeout(Duration(minutes: 30))
@Tags(['pq'])
library;

import 'dart:async' show Completer, StreamSubscription, TimeoutException;
import 'dart:convert' show LineSplitter, jsonDecode, utf8;
import 'dart:io';

// The enrollment key-package surface is @experimental; driving it is the
// point of the per-stage enrolments.
// ignore_for_file: experimental_member_use

import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_auth/at_auth.dart' show AtAuthSession, AtEnrollment, AtEnrollmentRequest, EnrollmentRequestDecision;
import 'package:at_auth/at_auth_io.dart' show FileAtKeysIo;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart' show AtClient;

// ignore: implementation_imports
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_functional_test/src/enrolled_client.dart'
    show enrolAndAuthenticate;
import 'package:at_client/at_client_mixins.dart'
    show AtClientSecretSharing;
import 'package:at_commons/at_commons.dart'
    show AtBytes, AtRootDomain, SecureSocketConfig;
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// UC-G1.14 and the rollout matrix — `docs/projects/pq/acceptance.md` 16.5.
///
/// Sender stage × receiver stage over the **data path**: a real notification,
/// multiple puts and gets. The two halves run as separate processes because
/// they are separate *builds* — the `published` stage is at_client 3.14.0 out
/// of pub.dev, and no single process can hold two versions of one package.
/// `tests/pq_matrix/README.md` describes the layout;
/// `docs/projects/pq/decisions.md` 96 rules it.
///
/// The envelope exchange rides the nine cells where **both** halves are this
/// tree, and is asserted separately below. It cannot be a fourth row and
/// column: a released client and this tree cannot exchange an envelope in
/// either direction under any stage, which is measured, pinned and accepted
/// rather than fixed
/// ([`decisions.md` 95](../../../docs/projects/pq/decisions.md) rulings 2–3).
/// So the envelope grid is a `legacy`/`pqReady`/`pqActive` 3×3 inside the 4×4.
void main() {
  final senderAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;
  final receiverAtSign =
      ConfigUtil.getYaml()['atSign']['secondAtSign'] as String;
  const namespace = 'wavi';

  /// `published` is the control arm and the other three are this tree. A stage
  /// asked of the wrong build is refused by the build itself rather than
  /// silently approximated, which is what stops the published column agreeing
  /// with `legacy` for the wrong reason.
  const stages = ['published', 'legacy', 'pqReady', 'pqActive'];
  String armFor(String stage) => stage == 'published' ? 'published' : 'current';

  final matrixRoot =
      Directory('${Directory.current.path}/../pq_matrix').absolute;
  final workRoot = Directory('${Directory.current.path}/test/hive/pqmatrix');
  final baselineKeys = Directory('${workRoot.path}/baseline');

  /// Each row and column of the matrix is its own enrollment (gkc,
  /// 2026-08-20): the deployment model is app = enrollment = unit, and four
  /// stages sharing `primary` made every stage client rewrite one shared
  /// `_apsk` record in turn — the overwrite the product documents as an
  /// accepted plurality of `primary`, and the race behind UC-G1.15's red.
  /// `published` stays unenrolled: 3.14.0's arm has no keyfile parameter, and
  /// it never writes an `_apsk`, so it cannot contend.
  ///
  /// Keyed by stage; senders are [senderAtSign]'s enrollments, receivers
  /// [receiverAtSign]'s. Filled by `setUpAll`, which also writes each
  /// enrollment's keyfile under `baseline/<stage>-<role>/`.
  final senderEnrollmentIds = <String, String>{};
  final receiverEnrollmentIds = <String, String>{};

  Directory stageKeyDir(String stage, String role) =>
      Directory('${baselineKeys.path}/$stage-$role');

  /// Enrols one stage on [atSign], approves it from [approver], **mints the
  /// stage's signing keys once, here**, and leaves the enrollment's keyfile
  /// in [keyDir].
  ///
  /// The legacy stage gets a legacy-mode (RSA APKAM) enrollment and the pq
  /// stages get pq-mode (ML-DSA APKAM) ones — the same split the postures'
  /// own `authenticationKeyAlgorithm` draws, so each stage's envelope-signing
  /// fallback is the algorithm the stage means. `(appName, deviceName)` is
  /// run-unique: enrollments are one-shot server state, and a second run of
  /// this file against the same virtualenv must not collide with the first's.
  ///
  /// Minting happens ONCE, at enrolment time, never in the cells: each cell
  /// copies a keyfile that already holds the stage's signing key, so no cell
  /// re-mints and the published advertisement is one stable value for the
  /// whole file. Per-cell minting was tried and is wrong twice over — a
  /// re-mint per cell churns the enrollment's advertisement (retired keys
  /// stay advertised, so the record leaves the bare form after the first
  /// re-mint, which is exactly the shape UC-G1.14's released reader cannot
  /// take), and the fire-and-forget startup mint is the race 14.48 records.
  Future<String> enrolStage({
    required AtClient approver,
    required String atSign,
    required String stage,
    required Directory keyDir,
  }) async {
    keyDir.createSync(recursive: true);
    final io = FileAtKeysIo(filePath: (a) => '${keyDir.path}/$a.atKeys');
    final rootDomain =
        AtRootDomain('vip.ve.atsign.zone', TestUtils.rootServerPort);
    final deviceName = 'pqm-$stage-${DateTime.now().microsecondsSinceEpoch}';

    if (stage == 'legacy') {
      // A legacy-mode (RSA APKAM) enrollment, by hand: the shared
      // `enrolAndAuthenticate` is pq-mode only. Legacy mints no signing key,
      // so there is no client to build and nothing to reconcile — the
      // enrollment's advertisement is its RSA APKAM key, published by the
      // atServer at approval, and it never changes.
      final session =
          AtAuthSession(atSign: atSign, rootDomain: rootDomain, atKeysIo: io);
      final otp = (await approver.getOTP()).response;
      final response = await AtEnrollment.create().submit(
        AtEnrollmentRequest(
          session: session,
          appName: 'pqmatrix',
          deviceName: deviceName,
          namespaces: {namespace: 'rw'},
          otp: otp,
        ),
        AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: rootDomain,
          transport: secureSocketTransport(SecureSocketConfig()),
          authenticator: null,
        ),
      );
      // The wrapped symmetric key rides the pending record and the approver
      // relays it — pq approvals mint their own and ignore this argument.
      final pending =
          await approver.enrollmentService!.fetchEnrollmentRequests();
      final wrapped = pending
              .firstWhere((e) => e.enrollmentId == response.enrollmentId)
              .encryptedAPKAMSymmetricKey ??
          '';
      await approver.enrollmentService!
          .approve(EnrollmentRequestDecision.approved(
        atSign: atSign,
        enrollmentId: response.enrollmentId,
        apkamSymmetricKey: AtBytes.fromString(wrapped),
      ));
      await AtEnrollment.create().waitForApproval(response);
      return response.enrollmentId;
    }

    // pq stages: the shared helper runs the real flow and hands back a live
    // client, which is what the one-time mint needs.
    final signingSet = stage == 'pqReady'
        ? const {SigningAlgoType.rsa2048}
        : const {SigningAlgoType.mldsa65};
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign,
          dataSigningKeyAlgorithms: signingSet),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: deviceName,
      atKeysIo: io,
    );
    try {
      final reconciled =
          await SigningKeyMinting(enrolled.client).reconcileSigningKeys();
      // The mechanism assertion for "a stage reaches the keyfile at all",
      // made where the mint now happens. Without it, every cell would run
      // against a keyfile the mint never touched and measure an inert stage.
      expect(reconciled.minted.toSet(), signingSet,
          reason: '$stage/$atSign: the one-time mint did not mint the '
              'stage\'s set');
      expect((await io.read(atSign)).signingKeysFor(enrolled.enrollmentId),
          isNotEmpty,
          reason: '$stage/$atSign: the mint reported success but filed '
              'nothing — cells copied from this keyfile would measure an '
              'inert stage');
    } finally {
      // The cells spawn their own processes for this enrollment; a live
      // driver-side client of the same enrollment running monitors and heals
      // underneath them is the cross-client interference this rebuild
      // removed.
      await enrolled.client.stop();
    }
    return enrolled.enrollmentId;
  }

  setUpAll(() async {
    expect(matrixRoot.existsSync(), isTrue,
        reason: 'the programme pair lives at ${matrixRoot.path}; without it '
            'every cell would fail identically and say nothing about at_client');

    if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
    baselineKeys.createSync(recursive: true);

    // Both arms resolve independently of the workspace — that is the whole
    // point of where they live — so neither is bootstrapped by the workspace's
    // own `pub get`.
    for (final arm in ['scenario', 'published', 'current']) {
      final dir = Directory('${matrixRoot.path}/$arm');
      if (File('${dir.path}/.dart_tool/package_config.json').existsSync()) {
        continue;
      }
      final result =
          await Process.run('dart', ['pub', 'get'], workingDirectory: dir.path);
      expect(result.exitCode, 0,
          reason: 'pub get failed in $arm:\n${result.stdout}\n${result.stderr}');
    }

    // One enrollment per stage per role. Batched per atSign because the
    // approver comes from the singleton AtClientManager, and initialising the
    // second atSign's approver evicts the first's client — so every alice
    // enrolment completes before bob's approver exists.
    final senderApprover =
        (await TestUtils.initAtClient(senderAtSign, namespace)).atClient;
    // A pq-mode approval seals the symmetric key from the approver's own
    // registered key package; an approver without one refuses the approval
    // and says so.
    await AtClientSecretSharing.forClient(senderApprover).register();
    for (final stage in ['legacy', 'pqReady', 'pqActive']) {
      senderEnrollmentIds[stage] = await enrolStage(
          approver: senderApprover,
          atSign: senderAtSign,
          stage: stage,
          keyDir: stageKeyDir(stage, 'sender'));
    }
    final receiverApprover =
        (await TestUtils.initAtClient(receiverAtSign, namespace)).atClient;
    await AtClientSecretSharing.forClient(receiverApprover).register();
    for (final stage in ['legacy', 'pqReady', 'pqActive']) {
      receiverEnrollmentIds[stage] = await enrolStage(
          approver: receiverApprover,
          atSign: receiverAtSign,
          stage: stage,
          keyDir: stageKeyDir(stage, 'receiver'));
    }
  });

  /// Runs one cell and returns what both sides reported.
  ///
  /// The receiver is started first and the sender is not spawned until it has
  /// emitted `READY`. Notification streams are broadcast and do not replay, so
  /// a sender that runs first is a sender whose notification nobody heard —
  /// and the cell would fail on a timeout that says nothing about the stages.
  Future<
      ({
        Map<String, Object?> sent,
        Map<String, Object?> result,
        String senderStorage,
      })> runCell({
    required String senderStage,
    required String receiverStage,
  }) async {
    final cell = '$senderStage-to-$receiverStage';
    // Run-unique, lowercase, alphanumeric: atKey names are lowercased, and two
    // cells sharing a record name would have the later one pass on the
    // earlier one's data.
    final runId = 'c${DateTime.now().microsecondsSinceEpoch}';

    Future<String> storageFor(String role, String stage, String atSign) async {
      // The runId is in the path, not just the stage pair. UC-G1.14 runs a
      // legacy/legacy cell of its own and compares its keyfile against a
      // pqReady/pqReady one; if a cell's directory were keyed on the stages
      // alone, a second run of the same pair would overwrite the first and the
      // comparison would be of one file with itself.
      final dir = Directory('${workRoot.path}/$cell-$runId/$role');
      dir.createSync(recursive: true);
      // The published arm has no keyfile parameter, so its cells get storage
      // and nothing else.
      if (stage == 'published') return dir.path;
      // A fresh copy of the stage's ENROLLED keyfile per cell, so a pqActive
      // mint does not leak into the next cell's starting state. The source is
      // the enrolment setUpAll performed for this stage and role.
      final source = File('${stageKeyDir(stage, role).path}/$atSign.atKeys');
      // Not a silent skip: a cell that quietly started without key material
      // would be a cell measuring an inert client while reporting a pass.
      expect(source.existsSync(), isTrue,
          reason: 'no enrolled keyfile at ${source.path} — setUpAll\'s '
              'enrolment for $stage/$role did not write where this driver '
              'reads');
      source.copySync('${dir.path}/$atSign.atKeys');
      return dir.path;
    }

    // A current-arm client authenticates as its stage's enrollment; the
    // published arm has no enrolment to be, and its absent id reaches the
    // shared code as `primary` — which is what an unenrolled 3.14.0 client
    // genuinely is. The peer's id rides along so the receiver can fetch the
    // sender's `_apsk`: the address is `(atSign, enrollment)`, and a reader
    // handed only the atSign would read a record an enrolled sender never
    // writes.
    String? enrollmentIdFor(String stage, String role) => stage == 'published'
        ? null
        : (role == 'sender' ? senderEnrollmentIds : receiverEnrollmentIds)[
            stage];

    Future<Process> spawn(String role, String stage, String atSign,
        String peer, String storage, {required String? peerEnrollmentId}) {
      final ownEnrollmentId = enrollmentIdFor(stage, role);
      return Process.start(
        'dart',
        [
          'run',
          'bin/$role.dart',
          '--stage', stage,
          '--atsign', atSign,
          '--peer', peer,
          '--run-id', runId,
          '--namespace', namespace,
          '--root-domain', 'vip.ve.atsign.zone',
          '--root-port', '${TestUtils.rootServerPort}',
          '--storage', storage,
          if (ownEnrollmentId != null) ...['--enrollment-id', ownEnrollmentId],
          if (peerEnrollmentId != null) ...[
            '--peer-enrollment-id',
            peerEnrollmentId
          ],
        ],
        workingDirectory: '${matrixRoot.path}/${armFor(stage)}',
      );
    }

    final senderStorage = await storageFor('sender', senderStage, senderAtSign);
    final receiver = await spawn('receiver', receiverStage, receiverAtSign,
        senderAtSign, await storageFor('receiver', receiverStage, receiverAtSign),
        peerEnrollmentId: enrollmentIdFor(senderStage, 'sender'));
    final ready = Completer<Map<String, Object?>>();
    final result = Completer<Map<String, Object?>>();
    final receiverNoise = <String>[];
    late StreamSubscription<String> receiverLines;
    receiverLines = receiver.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final parsed = _parseLine(line);
      if (parsed == null) return;
      switch (parsed.verb) {
        case 'READY':
          if (!ready.isCompleted) ready.complete(parsed.body);
        case 'RESULT':
          if (!result.isCompleted) result.complete(parsed.body);
        case 'FAILED':
          final failure = StateError('receiver ($receiverStage) failed: '
              '${parsed.body['type']}: ${parsed.body['message']}'
              '${parsed.body['during'] == null ? '' : ' (during ${parsed.body['during']})'}'
              '\n${parsed.body['stack']}');
          if (!ready.isCompleted) ready.completeError(failure);
          if (!result.isCompleted) result.completeError(failure);
      }
    });
    final receiverDrained = receiver.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(receiverNoise.add);

    // A child writes its FAILED line to stdout before its stack reaches
    // stderr, so a dump taken when FAILED is parsed is usually empty: let the
    // pipe drain (bounded — the child exits right after writing) before
    // dumping. Timeouts pass through: their arms already carry a dump.
    Future<T> orDumpStderr<T>(Future<T> future, String who,
        Future<void> drained, List<String> noise) async {
      try {
        return await future;
      } on StateError catch (e) {
        await drained.timeout(const Duration(seconds: 10), onTimeout: () {});
        throw StateError('$e\n$who stderr (first 40 lines):\n'
            '${noise.take(40).join('\n')}');
      }
    }

    try {
      await orDumpStderr(
          ready.future.timeout(const Duration(minutes: 3),
              onTimeout: () => throw TimeoutException(
                  'receiver ($receiverStage) never became ready. stderr:\n'
                  '${receiverNoise.take(40).join('\n')}')),
          'receiver ($receiverStage)',
          receiverDrained,
          receiverNoise);

      final sender = await spawn('sender', senderStage, senderAtSign,
          receiverAtSign, senderStorage,
          peerEnrollmentId: enrollmentIdFor(receiverStage, 'receiver'));
      final senderNoise = <String>[];
      final sent = Completer<Map<String, Object?>>();
      final senderLines = sender.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final parsed = _parseLine(line);
        if (parsed == null) return;
        if (parsed.verb == 'SENT' && !sent.isCompleted) {
          sent.complete(parsed.body);
        }
        if (parsed.verb == 'FAILED' && !sent.isCompleted) {
          sent.completeError(StateError('sender ($senderStage) failed: '
              '${parsed.body['type']}: ${parsed.body['message']}'
              '${parsed.body['during'] == null ? '' : ' (during ${parsed.body['during']})'}'
              '\n${parsed.body['stack']}'));
        }
      });
      final senderDrained = sender.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(senderNoise.add);

      final sentBody = await orDumpStderr(
          sent.future.timeout(const Duration(minutes: 3),
              onTimeout: () => throw TimeoutException(
                  'sender ($senderStage) never reported. stderr:\n'
                  '${senderNoise.take(40).join('\n')}')),
          'sender ($senderStage)',
          senderDrained,
          senderNoise);
      await sender.exitCode;
      await senderLines.cancel();

      final resultBody = await orDumpStderr(
          result.future.timeout(const Duration(minutes: 3),
              onTimeout: () => throw TimeoutException(
                  'receiver ($receiverStage) never reported a result. stderr:\n'
                  '${receiverNoise.take(40).join('\n')}')),
          'receiver ($receiverStage)',
          receiverDrained,
          receiverNoise);
      await receiver.exitCode;
      return (
        sent: sentBody,
        result: resultBody,
        senderStorage: senderStorage,
      );
    } finally {
      receiver.kill();
      await receiverLines.cancel();
    }
  }

  for (final senderStage in stages) {
    for (final receiverStage in stages) {
      test('$senderStage sender to $receiverStage receiver', () async {
        final cell =
            await runCell(senderStage: senderStage, receiverStage: receiverStage);

        // Both sides name what they handled, and the assertion is that the
        // receiver read back exactly what the sender wrote. Asserting only
        // "no exception" would pass for a receiver that read nothing at all.
        expect(cell.sent['written'], isNotEmpty,
            reason: 'the sender reported writing nothing');
        expect(cell.result['read'], cell.sent['written'],
            reason: 'the records the receiver read back must be exactly the '
                'ones the sender wrote — a stage cannot change which records '
                'reach a peer');
        expect(cell.result['notification'], isNotNull,
            reason: 'the notification path is part of the cell, not a '
                'nice-to-have: a matrix that only proves put/get would miss a '
                'stage that broke notification delivery');
      });
    }
  }

  test('UC-G1.15 · every rollout stage verifies every other stage\'s envelope',
      () async {
    // The 3×3 the data-path matrix does not reach. Each cell signs an envelope
    // at the sender's stage, leaves it on the atServer, and has the receiver
    // fetch the sender's `_apsk` and verify it with its own build.
    //
    // Under `docs/projects/pq/detail/decisions.md` 108 the ladder SWAPS
    // algorithms rather than overlapping them — no stage's in-use set holds
    // two — so a pqActive sender emits ML-DSA-65 alone and a pqReady
    // receiver, which signs RSA-2048, must still verify it. That is the whole
    // claim: verification is ungated, so a swap needs no overlap to be safe.
    // These nine cells are what turns that ruling into a measurement.
    const armStages = ['legacy', 'pqReady', 'pqActive'];

    final verdicts = <String, Map<String, Object?>>{};
    for (final senderStage in armStages) {
      for (final receiverStage in armStages) {
        final cell = await runCell(
            senderStage: senderStage, receiverStage: receiverStage);

        final sent = (cell.sent['envelope'] as Map?)?.cast<String, Object?>();
        final got = (cell.result['envelope'] as Map?)?.cast<String, Object?>();
        final where = '$senderStage → $receiverStage';

        expect(sent, isNotNull,
            reason: '$where: the sender reported no envelope at all. Every '
                'cell of this grid signs one, so a missing report is the '
                'harness failing rather than a stage behaving differently');
        expect(got, isNotNull, reason: '$where: the receiver reported none');
        expect(got!['verified'], true,
            reason: '$where: verification failed — ${got['errorType']}: '
                '${got['error']}. Under decisions 108 every cell must verify, '
                'because the ladder swaps algorithms and reading is not '
                'staged; a red cell here means a receiver at one stage cannot '
                'read a sender at another, which is the breakage the staging '
                'exists to prevent');
        expect(got['algs'], sent!['algs'],
            reason: '$where: the receiver verified an envelope carrying '
                '${got['algs']} while the sender emitted ${sent['algs']} — '
                'the two processes are not looking at the same document');

        verdicts[where] = got;
      }
    }

    // The mechanism assertion. Without it these nine cells pass exactly as
    // well for a harness in which no stage does anything — the failure this
    // matrix has already had once, in the row below, and the reason that row
    // now carries two positive controls of its own.
    //
    // `algs` is the JOSE name on the wire, so this reads what was actually
    // signed rather than what the stage was asked for.
    expect(verdicts['pqActive → pqActive']!['algs'], ['ML-DSA-65'],
        reason: 'a pqActive sender mints an ML-DSA-65 signing key and signs '
            'with it alone. If this is RSA the stage never reached the signer '
            'and every cell above is comparing a case with itself');
    expect(verdicts['legacy → legacy']!['algs'], isNot(contains('ML-DSA-65')),
        reason: 'a legacy sender files no signing key of its own and signs with '
            'its APKAM authentication key, so it must NOT emit ML-DSA-65 — '
            'the control that makes the assertion above discriminate');

    // The cell the ruling is actually about: strongest signer, weakest
    // verifier. Called out separately from the loop because it is the one a
    // reader comes here to check.
    expect(verdicts['pqActive → pqReady']!['verified'], true,
        reason: 'a receiver that signs RSA-2048 must verify an ML-DSA-65 '
            'envelope. This is the cell an overlapping ladder would have '
            'existed to rescue, and decisions 108 rules it needs no rescue');
    expect(verdicts['pqActive → legacy']!['verified'], true,
        reason: 'and so must a receiver that files no signing key at all');

    // Each signature names exactly one — the ladder swaps, so nothing this
    // harness runs should ever produce two. A second entry here would mean a
    // stage started overlapping, which is a design change, not a passing test.
    for (final entry in verdicts.entries) {
      expect((entry.value['algs'] as List).length, 1,
          reason: '${entry.key}: no posture names two algorithms, so no '
              'envelope from one should carry two signatures. Two means the '
              'in-use set gained a member and decisions 108 needs revisiting');
    }
  });

  test('UC-G1.14 · pqReady is invisible to a deployed peer', () async {
    // Every cell runs here rather than reading what the matrix loop left
    // behind: a test that depends on another test having run first passes or
    // fails on declaration order, which is not a property of the code.
    //
    // The receiver is `published` throughout — at_client 3.14.0, resolved from
    // pub.dev. That is the whole row. The question is not what this tree
    // believes it published, it is what a build we cannot change makes of it.
    final asLegacy = await runCell(senderStage: 'legacy', receiverStage: 'published');
    final asPqReady =
        await runCell(senderStage: 'pqReady', receiverStage: 'published');

    Map<String, Object?> verdict(Map<String, Object?> result) =>
        (result['peerApsk'] as Map).cast<String, Object?>();

    final legacyVerdict = verdict(asLegacy.result);
    final pqReadyVerdict = verdict(asPqReady.result);

    // The baseline: what a deployed peer does with a `legacy` sender today.
    expect(legacyVerdict['fetched'], true, reason: '${legacyVerdict['error']}');
    expect(legacyVerdict['rsa'], true,
        reason: 'the released reader must parse a legacy sender\'s _apsk as an '
            'RSA public key. If this fails the run says nothing about rollout '
            '1, because the baseline it is measured against is broken');

    // The row's claim.
    expect(pqReadyVerdict['fetched'], true,
        reason: '${pqReadyVerdict['error']}');
    expect(pqReadyVerdict['rsa'], true,
        reason: 'a pqReady sender advertises its own freshly minted RSA-2048 '
            'SIGNING key where legacy advertises its AUTHENTICATION key. Both are '
            'a single active rsa2048 entry, so both spell as the bare string, '
            'and at_client 3.14.0 cannot tell the two stages apart. '
            'The record actually held: ${pqReadyVerdict['value']}');

    // Positive control 1: the stage actually moved the key. Without it every
    // assertion above passes for a harness in which pqReady did nothing at
    // all — which is what this row asserted, and got, until 2026-08-14.
    expect(pqReadyVerdict['value'], isNot(legacyVerdict['value']),
        reason: 'pqReady must publish a DIFFERENT key from legacy — its signing '
            'key rather than its authentication key. Byte-identity here means '
            'the stage is not being applied and this row is comparing a case '
            'with itself');

    // Positive control 2: `rsa: true` is capable of being false. pqActive
    // advertises the array, which no released reader takes — so the two
    // assertions above are measuring something rather than always passing.
    final asPqActive =
        await runCell(senderStage: 'pqActive', receiverStage: 'published');
    final pqActiveVerdict = verdict(asPqActive.result);
    expect(pqActiveVerdict['rsa'], false,
        reason: 'pqActive publishes the JSON advertisement, which is the one '
            'shape a released reader cannot take. If that parses as RSA then '
            'the parse discriminates nothing and pqReady\'s green is empty');

    // The "a stage reaches the keyfile at all" check lives in `enrolStage`
    // now: minting happens once, driver-side, and the assertion that the
    // minted key was filed sits beside the mint. A cell-side keyfile
    // comparison stopped measuring anything when cells stopped minting.
  });
}

/// The driver's own copy of the line protocol's read half.
///
/// Deliberately not imported from `pq_matrix_scenario`: that package sits
/// outside the workspace so the published arm can resolve hosted at_client, and
/// path-depending on it from a workspace member would drag it into the
/// workspace's resolution — the exact coupling its location exists to avoid.
/// A protocol change breaks this loudly (no `READY`, then a timeout naming the
/// stage), never silently.
({String verb, Map<String, Object?> body})? _parseLine(String line) {
  const prefix = '##PQM##';
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith('$prefix ')) return null;
  final rest = trimmed.substring(prefix.length + 1);
  final space = rest.indexOf(' ');
  if (space < 0) return null;
  try {
    final body = jsonDecode(rest.substring(space + 1));
    if (body is! Map) return null;
    return (verb: rest.substring(0, space), body: body.cast<String, Object?>());
  } on FormatException {
    return null;
  }
}
