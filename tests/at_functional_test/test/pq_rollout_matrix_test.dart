// Sixteen cells, each two client startups against a live atServer.
@Timeout(Duration(minutes: 30))
library;

import 'dart:async'
    show Completer, StreamSubscription, TimeoutException, unawaited;
import 'dart:convert' show LineSplitter, jsonDecode, utf8;
import 'dart:io';

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
/// So the envelope grid is a `now`/`rollout1`/`rollout2` 3×3 inside the 4×4.
void main() {
  final senderAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;
  final receiverAtSign =
      ConfigUtil.getYaml()['atSign']['secondAtSign'] as String;
  const namespace = 'wavi';

  /// `published` is the control arm and the other three are this tree. A stage
  /// asked of the wrong build is refused by the build itself rather than
  /// silently approximated, which is what stops the published column agreeing
  /// with `now` for the wrong reason.
  const stages = ['published', 'now', 'rollout1', 'rollout2'];
  String armFor(String stage) => stage == 'published' ? 'published' : 'current';

  final matrixRoot =
      Directory('${Directory.current.path}/../pq_matrix').absolute;
  final workRoot = Directory('${Directory.current.path}/test/hive/pqmatrix');
  final baselineKeys = Directory('${workRoot.path}/baseline');

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

    // The keyfile the current arm's clients read. The published arm has no
    // parameter to hand one to, which is the asymmetry the matrix is built
    // around rather than an oversight.
    final built = await Process.run(
        'dart', ['run', 'test/build_test_atkeys.dart', baselineKeys.path],
        workingDirectory: Directory.current.path);
    expect(built.exitCode, 0,
        reason: 'could not build the baseline keyfiles:\n'
            '${built.stdout}\n${built.stderr}');
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

    Future<String> storageFor(String role, String atSign) async {
      // The runId is in the path, not just the stage pair. UC-G1.14 runs a
      // now/now cell of its own and compares its keyfile against a
      // rollout1/rollout1 one; if a cell's directory were keyed on the stages
      // alone, a second run of the same pair would overwrite the first and the
      // comparison would be of one file with itself.
      final dir = Directory('${workRoot.path}/$cell-$runId/$role');
      dir.createSync(recursive: true);
      // A fresh keyfile per cell, so a rollout-2 mint does not leak into the
      // next cell's baseline.
      final baseline = File('${baselineKeys.path}/${atSign}_key.atKeys');
      // Not a silent skip: every stage's client is handed the same starting
      // key material, and a cell that quietly started without any would be a
      // cell measuring an inert client while reporting a pass.
      expect(baseline.existsSync(), isTrue,
          reason: 'no baseline keyfile at ${baseline.path} — '
              'build_test_atkeys.dart names its output differently than this '
              'driver expects');
      baseline.copySync('${dir.path}/$atSign.atKeys');
      return dir.path;
    }

    Future<Process> spawn(String role, String stage, String atSign,
        String peer, String storage) {
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
        ],
        workingDirectory: '${matrixRoot.path}/${armFor(stage)}',
      );
    }

    final senderStorage = await storageFor('sender', senderAtSign);
    final receiver = await spawn('receiver', receiverStage, receiverAtSign,
        senderAtSign, await storageFor('receiver', receiverAtSign));
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
              '${parsed.body['type']}: ${parsed.body['message']}');
          if (!ready.isCompleted) ready.completeError(failure);
          if (!result.isCompleted) result.completeError(failure);
      }
    });
    unawaited(receiver.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(receiverNoise.add));

    try {
      await ready.future.timeout(const Duration(minutes: 3),
          onTimeout: () => throw TimeoutException(
              'receiver ($receiverStage) never became ready. stderr:\n'
              '${receiverNoise.take(40).join('\n')}'));

      final sender = await spawn('sender', senderStage, senderAtSign,
          receiverAtSign, senderStorage);
      final senderOut = <String>[];
      final senderNoise = <String>[];
      final sent = Completer<Map<String, Object?>>();
      final senderLines = sender.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        senderOut.add(line);
        final parsed = _parseLine(line);
        if (parsed == null) return;
        if (parsed.verb == 'SENT' && !sent.isCompleted) {
          sent.complete(parsed.body);
        }
        if (parsed.verb == 'FAILED' && !sent.isCompleted) {
          sent.completeError(StateError('sender ($senderStage) failed: '
              '${parsed.body['type']}: ${parsed.body['message']}'));
        }
      });
      unawaited(sender.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(senderNoise.add));

      final sentBody = await sent.future.timeout(const Duration(minutes: 3),
          onTimeout: () => throw TimeoutException(
              'sender ($senderStage) never reported. stderr:\n'
              '${senderNoise.take(40).join('\n')}'));
      await sender.exitCode;
      await senderLines.cancel();

      final resultBody = await result.future.timeout(const Duration(minutes: 3),
          onTimeout: () => throw TimeoutException(
              'receiver ($receiverStage) never reported a result. stderr:\n'
              '${receiverNoise.take(40).join('\n')}'));
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
    // two — so a rollout-2 sender emits ML-DSA-65 alone and a rollout-1
    // receiver, which signs RSA-2048, must still verify it. That is the whole
    // claim: verification is ungated, so a swap needs no overlap to be safe.
    // These nine cells are what turns that ruling into a measurement.
    const armStages = ['now', 'rollout1', 'rollout2'];

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
    expect(verdicts['rollout2 → rollout2']!['algs'], ['ML-DSA-65'],
        reason: 'a rollout-2 sender mints an ML-DSA-65 signing key and signs '
            'with it alone. If this is RSA the stage never reached the signer '
            'and every cell above is comparing a case with itself');
    expect(verdicts['now → now']!['algs'], isNot(contains('ML-DSA-65')),
        reason: 'a now sender files no signing key of its own and signs with '
            'its APKAM authentication key, so it must NOT emit ML-DSA-65 — '
            'the control that makes the assertion above discriminate');

    // The cell the ruling is actually about: strongest signer, weakest
    // verifier. Called out separately from the loop because it is the one a
    // reader comes here to check.
    expect(verdicts['rollout2 → rollout1']!['verified'], true,
        reason: 'a receiver that signs RSA-2048 must verify an ML-DSA-65 '
            'envelope. This is the cell an overlapping ladder would have '
            'existed to rescue, and decisions 108 rules it needs no rescue');
    expect(verdicts['rollout2 → now']!['verified'], true,
        reason: 'and so must a receiver that files no signing key at all');

    // Each signature names exactly one — the ladder swaps, so nothing this
    // harness runs should ever produce two. A second entry here would mean a
    // stage started overlapping, which is a design change, not a passing test.
    for (final entry in verdicts.entries) {
      expect((entry.value['algs'] as List).length, 1,
          reason: '${entry.key}: no rollout stage names two algorithms, so no '
              'envelope from one should carry two signatures. Two means the '
              'in-use set gained a member and decisions 108 needs revisiting');
    }
  });

  test('UC-G1.14 · rollout 1 is invisible to a deployed peer', () async {
    // Every cell runs here rather than reading what the matrix loop left
    // behind: a test that depends on another test having run first passes or
    // fails on declaration order, which is not a property of the code.
    //
    // The receiver is `published` throughout — at_client 3.14.0, resolved from
    // pub.dev. That is the whole row. The question is not what this tree
    // believes it published, it is what a build we cannot change makes of it.
    final asNow = await runCell(senderStage: 'now', receiverStage: 'published');
    final asRollout1 =
        await runCell(senderStage: 'rollout1', receiverStage: 'published');

    Map<String, Object?> verdict(Map<String, Object?> result) =>
        (result['peerApsk'] as Map).cast<String, Object?>();

    final nowVerdict = verdict(asNow.result);
    final rollout1Verdict = verdict(asRollout1.result);

    // The baseline: what a deployed peer does with a `now` sender today.
    expect(nowVerdict['fetched'], true, reason: '${nowVerdict['error']}');
    expect(nowVerdict['rsa'], true,
        reason: 'the released reader must parse a now sender\'s _apsk as an '
            'RSA public key. If this fails the run says nothing about rollout '
            '1, because the baseline it is measured against is broken');

    // The row's claim.
    expect(rollout1Verdict['fetched'], true,
        reason: '${rollout1Verdict['error']}');
    expect(rollout1Verdict['rsa'], true,
        reason: 'a rollout-1 sender advertises its own freshly minted RSA-2048 '
            'SIGNING key where now advertises its AUTHENTICATION key. Both are '
            'a single active rsa2048 entry, so both spell as the bare string, '
            'and at_client 3.14.0 cannot tell the two stages apart');

    // Positive control 1: the stage actually moved the key. Without it every
    // assertion above passes for a harness in which rollout 1 did nothing at
    // all — which is what this row asserted, and got, until 2026-08-14.
    expect(rollout1Verdict['value'], isNot(nowVerdict['value']),
        reason: 'rollout 1 must publish a DIFFERENT key from now — its signing '
            'key rather than its authentication key. Byte-identity here means '
            'the stage is not being applied and this row is comparing a case '
            'with itself');

    // Positive control 2: `rsa: true` is capable of being false. Rollout 2
    // advertises the array, which no released reader takes — so the two
    // assertions above are measuring something rather than always passing.
    final asRollout2 =
        await runCell(senderStage: 'rollout2', receiverStage: 'published');
    final rollout2Verdict = verdict(asRollout2.result);
    expect(rollout2Verdict['rsa'], false,
        reason: 'rollout 2 publishes the JSON advertisement, which is the one '
            'shape a released reader cannot take. If that parses as RSA then '
            'the parse discriminates nothing and rollout 1\'s green is empty');

    File keyfile(String storage) => File('$storage/$senderAtSign.atKeys');
    expect(keyfile(asRollout2.senderStorage).readAsBytesSync(),
        isNot(keyfile(asNow.senderStorage).readAsBytesSync()),
        reason: 'and rollout 2 mints a signing key and files it, so its '
            'keyfile must differ from now\'s — the check that a stage reaches '
            'the keyfile at all');
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
