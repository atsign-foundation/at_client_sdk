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
/// The envelope exchange is deliberately **not** here. A released client and
/// this tree cannot exchange an envelope in either direction under any stage,
/// which is measured, pinned and accepted rather than fixed
/// ([`decisions.md` 95](../../../docs/projects/pq/decisions.md) rulings 2–3).
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

  test('UC-G1.14 · rollout 1 changes nothing on the wire', () async {
    // Both cells run here rather than reading what the matrix loop left
    // behind: a test that depends on another test having run first passes or
    // fails on declaration order, which is not a property of the code.
    final asNow = await runCell(senderStage: 'now', receiverStage: 'now');
    final asRollout1 =
        await runCell(senderStage: 'rollout1', receiverStage: 'rollout1');

    File keyfile(String storage) => File('$storage/$senderAtSign.atKeys');

    // The differential this row turns on. `rollout1` is reader capability
    // only — it says the fleet's peers have upgraded, and changes nothing this
    // client writes.
    expect(asRollout1.sent['apsk'], asNow.sent['apsk'],
        reason: 'rollout 1 must publish the same _apsk as now, byte for byte. '
            'A difference here means the stage has become a writer gate, '
            'which is what rollout 2 is for');
    expect(keyfile(asRollout1.senderStorage).readAsBytesSync(),
        keyfile(asNow.senderStorage).readAsBytesSync(),
        reason: 'rollout 1 must mint nothing: its in-use signing set is empty, '
            'exactly as now\'s is, so the keyfile it leaves behind is the one '
            'it was given');

    // The positive control. Without it the two assertions above pass for a
    // harness where no stage does anything at all — which is precisely how a
    // rollout-2 arm attached without a key source would read.
    final asRollout2 =
        await runCell(senderStage: 'rollout2', receiverStage: 'rollout2');
    expect(keyfile(asRollout2.senderStorage).readAsBytesSync(),
        isNot(keyfile(asNow.senderStorage).readAsBytesSync()),
        reason: 'rollout 2 mints a signing key and files it, so its keyfile '
            'must differ. If this passes with the two above, the stages are '
            'not being applied and the whole matrix is comparing a case with '
            'itself');
    expect(asRollout2.sent['apsk'], isNot(asNow.sent['apsk']),
        reason: 'rollout 2 advertises the key it minted beside the retained '
            'authentication key, so its _apsk cannot be what now publishes');
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
