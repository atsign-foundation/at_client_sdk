// Worked example: receiving live docker stats published by
// `dockerstats_publish.dart`. Prints one line per arriving sample so
// you can verify publisher ↔ receiver round-trip without spinning up
// the Flutter app.
//
// Run:
//   dart run bin/dockerstats_subscribe.dart -a @bob
//
// Pair with the publisher in another terminal (publisher's
// --other-at-signs must include this subscriber's atSign):
//   dart run bin/dockerstats_publish.dart \
//       -a @alice --other-at-signs @bob -P 2s --simulate
//
// Mirrors the receive-side wiring of the Flutter dashboard at
// `packages/at_client_flutter/examples/dockerstats/`.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/dockerstats/models.dart';

const String applicationNamespace = 'dockerstats.demos';
const Duration sampleExpiration = Duration(minutes: 5);

void main(List<String> args) async {
  final ap = _buildParser();
  final ArgResults parsed;
  try {
    parsed = ap.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(ap.usage);
    exit(64);
  }
  if (parsed['help'] == true) {
    stdout.writeln(ap.usage);
    return;
  }

  // Optional bounded-run flags. With both, the subscriber stops as
  // soon as it has either received [expect] samples or waited
  // [expectTimeout]. Designed for closed-loop verification against
  // the publisher's `--cycles` flag.
  final expectStr = parsed['expect'] as String?;
  final int? expectCount = expectStr == null ? null : int.tryParse(expectStr);
  if (expectStr != null && (expectCount == null || expectCount <= 0)) {
    stderr.writeln('--expect must be a positive integer');
    exit(64);
  }
  final expectTimeout = _parseDuration(parsed['expect-timeout'] as String);

  stdout.writeln('Connecting...');
  final cliBase = await CLIBase.fromCommandLineArgs(args, parser: ap);
  final atClient = cliBase.atClient;
  stdout.writeln('Connected as ${atClient.atSign}');

  AtCollection.registerFactory<HostNode>(
    HostNode.fromJson,
    typeTag: 'HostNode',
  );
  AtCollection.registerFactory<AtsignOnHost>(
    AtsignOnHost.fromJson,
    typeTag: 'AtsignOnHost',
  );
  AtCollection.registerFactory<StatSample>(
    StatSample.fromJson,
    typeTag: 'StatSample',
  );

  final nodes = await atClient.collection<HostNode>(
    '$collectionRootName.$applicationNamespace',
    sampleExpiration,
    eventsFromLocalSecondary: true,
  );

  // ---------------------------------------------------------------------
  // Subscribe.

  // Graceful shutdown plumbing — installed BEFORE the listener so
  // --expect can complete the same Completer the signal handlers do.
  final stop = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }

  var samplesSeen = 0;
  final sub = nodes.subUpdates.listen((e) async {
    if (e.subName != subSamplesName || e.ancestry.length != 2) return;
    try {
      // [AtCollection.getDescendant] walks the
      //   nodes → atsigns → samples
      // chain in one call. Cheaper than the hand-coded version since
      // every link is the same lookup logic — and it's the canonical
      // way to read deeply-nested sub-items, so this stays correct
      // even if the SDK's internal lookup mechanics shift.
      final item = await nodes.getDescendant<StatSample>(
        ancestry: e.ancestry,
        id: e.id,
        owner: e.owner,
        leafExpiration: sampleExpiration,
        leafFromJson: StatSample.fromJson,
        leafTypeTag: 'StatSample',
      );
      if (item == null) {
        // Parent CItem not yet synced or chain incomplete — will
        // retry on the next event for the same pair (e.g. the next
        // sample arriving moments later).
        return;
      }
      final s = item.obj;
      samplesSeen++;
      stdout.writeln(_formatSample(s, samplesSeen));
      // Closed-loop early-exit: once we've seen the expected count,
      // signal the main loop to stop. The publisher and subscriber
      // can then be treated as a hermetic pair under test.
      if (expectCount != null &&
          samplesSeen >= expectCount &&
          !stop.isCompleted) {
        stop.complete();
      }
    } catch (err, st) {
      stderr.writeln('${DateTime.now()} | fetch failed: $err\n$st');
    }
  });

  stdout.writeln(
    '${DateTime.now()} | listening for stats on $applicationNamespace',
  );

  if (expectCount != null) {
    // Race the expected-count completion against the timeout.
    Timer? timeout;
    timeout = Timer(expectTimeout, () {
      if (!stop.isCompleted) stop.complete();
    });
    await stop.future;
    timeout.cancel();
  } else {
    await stop.future;
  }
  await sub.cancel();
  stdout.writeln(
    '${DateTime.now()} | shutting down ($samplesSeen sample(s) received)',
  );
  if (expectCount != null) {
    final hit = samplesSeen >= expectCount;
    stdout.writeln(
      '${DateTime.now()} | expect=$expectCount actual=$samplesSeen '
      '${hit ? "OK" : "MISSING ${expectCount - samplesSeen}"}',
    );
    exit(hit ? 0 : 1);
  }
  exit(0);
}

Duration _parseDuration(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return const Duration(seconds: 60);
  final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m|h)?$').firstMatch(s);
  if (m == null) {
    throw FormatException('Bad duration "$raw" — try 30s / 2m');
  }
  final value = double.parse(m.group(1)!);
  switch (m.group(2) ?? 's') {
    case 'ms':
      return Duration(milliseconds: value.round());
    case 's':
      return Duration(milliseconds: (value * 1000).round());
    case 'm':
      return Duration(milliseconds: (value * 60 * 1000).round());
    case 'h':
      return Duration(milliseconds: (value * 3600 * 1000).round());
  }
  return Duration(seconds: value.round());
}

String _formatSample(StatSample s, int n) {
  final ts = DateTime.fromMillisecondsSinceEpoch(s.millis).toIso8601String();
  final memMib = (s.memUsage / (1024 * 1024)).toStringAsFixed(1);
  final memLimMib = (s.memLimit / (1024 * 1024)).toStringAsFixed(0);
  final netMib = ((s.netRx + s.netTx) / (1024 * 1024)).toStringAsFixed(2);
  final blkMib = ((s.blkRead + s.blkWrite) / (1024 * 1024)).toStringAsFixed(2);
  return '#$n  $ts  '
      '${s.hostname}/${s.atSign}  ${s.containerName}  '
      'cpu=${s.cpuPct.toStringAsFixed(1)}%  '
      'mem=$memMib/${memLimMib}MiB (${s.memPct.toStringAsFixed(1)}%)  '
      'net=${netMib}MiB  blk=${blkMib}MiB  '
      'pids=${s.pidsCount}  restart=${s.restartCount}';
}

ArgParser _buildParser() {
  final cols = stdout.hasTerminal ? stdout.terminalColumns : null;
  return ArgParser(usageLineLength: cols)
    ..addFlag('help', negatable: false, help: 'Show this help')
    ..addOption(
      'atsign',
      abbr: 'a',
      mandatory: true,
      help: 'The atSign to subscribe as',
    )
    ..addOption(
      'expect',
      help:
          'Closed-loop verification: exit with status 0 once this many '
          'samples have been received, or status 1 on --expect-timeout. '
          'Pair with the publisher\'s --cycles flag.',
    )
    ..addOption(
      'expect-timeout',
      defaultsTo: '60s',
      help:
          'Time to wait for --expect to be reached before exiting '
          'with status 1.',
    )
    ..addOption(
      'namespace',
      abbr: 'n',
      defaultsTo: applicationNamespace,
      hide: true,
      help: 'Namespace',
    )
    ..addOption('key-file', abbr: 'k', hide: true)
    ..addOption('home-dir', hide: true)
    ..addOption('storage-dir', abbr: 's', hide: true)
    ..addOption(
      'root-server',
      aliases: const ['root-domain'],
      abbr: 'r',
      defaultsTo: 'root.atsign.org:64',
      hide: true,
    )
    ..addFlag('never-sync', negatable: false, hide: true)
    ..addOption('max-connect-attempts', defaultsTo: '20', hide: true)
    ..addOption(
      'pass-phrase',
      aliases: const ['passPhrase'],
      abbr: 'P',
      hide: true,
    )
    ..addOption('legacy-root-domain', hide: true)
    ..addFlag('verbose', abbr: 'v', negatable: false);
}
