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
    eventsFromLocalSecondary: false,
  );

  // ---------------------------------------------------------------------
  // Subscribe.

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
    } catch (err, st) {
      stderr.writeln('${DateTime.now()} | fetch failed: $err\n$st');
    }
  });

  stdout.writeln(
    '${DateTime.now()} | listening for stats on $applicationNamespace',
  );

  // Graceful shutdown.
  final stop = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  await sub.cancel();
  stdout.writeln(
    '${DateTime.now()} | shutting down ($samplesSeen sample(s) received)',
  );
  exit(0);
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
