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
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client_examples/dockerstats/models.dart';

const String applicationNamespace = 'dockerstats.demos';

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
  final traceEnabled = parsed['trace'] as bool;
  final jsonMode = parsed['json'] as bool;

  stdout.writeln('Connecting...');
  final cliBase = await CLIBase.fromCommandLineArgs(args, parser: ap);
  final atClient = cliBase.atClient;
  stdout.writeln('Connected as ${atClient.atSign}');

  // Force the notification listener up front so the first event
  // doesn't race the lazy startup inside subscribe().
  atClient.notificationService.startListening();

  // The publisher's notification key shape is:
  //   <recipient>:sample.<sanitised-container>.<sanitised-host>.dockerstats.demos<publisher>
  // Match exactly that — anchored on this subscriber's own atSign so
  // we don't pick up notifications addressed to anyone else (the
  // monitor stream returns those too on a non-namespace-scoped
  // subscribe).
  final selfFragment = RegExp.escape(atClient.atSign.toString());
  final nsTail = RegExp.escape('.$applicationNamespace');
  final regex = '^$selfFragment:sample\\.[^.]+\\.[^.]+$nsTail@';

  // ---------------------------------------------------------------------
  // Subscribe.

  final stop = Completer<void>();
  void onSignal() {
    if (!stop.isCompleted) {
      stop.complete();
      stderr.writeln(
        '\n${DateTime.now()} | shutdown signal received; '
        'press Ctrl-C again to force exit',
      );
    } else {
      stderr.writeln('${DateTime.now()} | second signal — forcing exit');
      exit(130);
    }
  }

  ProcessSignal.sigint.watch().listen((_) => onSignal());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => onSignal());
  }

  var samplesSeen = 0;
  final sub = atClient.notificationService
      .subscribe(regex: regex, shouldDecrypt: true)
      .listen(
        (n) {
          final value = n.value;
          if (value == null || value.isEmpty) {
            if (traceEnabled) {
              stderr.writeln(
                'TRACE sub_event_empty id=${n.id} from=${n.from} key=${n.key}',
              );
            }
            return;
          }
          StatSample s;
          try {
            s = StatSample.fromJson(jsonDecode(value) as Map<String, dynamic>);
          } catch (e) {
            stderr.writeln(
              '${DateTime.now()} | decode failed for ${n.key} from ${n.from}: $e',
            );
            return;
          }
          samplesSeen++;
          if (traceEnabled) {
            stderr.writeln(
              'TRACE sub_recv id=${s.millis} from=${n.from} '
              'pair=${s.hostname}/${s.containerName} '
              't_us=${DateTime.now().microsecondsSinceEpoch}',
            );
          }
          if (jsonMode) {
            stdout.writeln(value);
          } else {
            stdout.writeln(_formatSample(s, samplesSeen, n.from));
          }
          if (expectCount != null) {
            final hit = samplesSeen >= expectCount;
            stderr.writeln(
              '${DateTime.now()} | expect=$expectCount actual=$samplesSeen '
              '${hit ? "OK" : "MISSING ${expectCount - samplesSeen}"}',
            );
            if (hit && !stop.isCompleted) stop.complete();
          }
        },
        onError: (Object e, StackTrace st) {
          stderr.writeln('${DateTime.now()} | subscribe error: $e');
        },
      );

  stdout.writeln('${DateTime.now()} | listening for stats matching $regex');

  if (expectCount != null) {
    final timeout = Timer(expectTimeout, () {
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

String _formatSample(StatSample s, int n, String from) {
  final ts = DateTime.fromMillisecondsSinceEpoch(s.millis).toIso8601String();
  final memMib = (s.memUsage / (1024 * 1024)).toStringAsFixed(1);
  final memLimMib = (s.memLimit / (1024 * 1024)).toStringAsFixed(0);
  final netMib = ((s.netRx + s.netTx) / (1024 * 1024)).toStringAsFixed(2);
  final blkMib = ((s.blkRead + s.blkWrite) / (1024 * 1024)).toStringAsFixed(2);
  return '#$n  $ts  $from  '
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
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print raw decoded JSON instead of the human-readable format',
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
    ..addFlag(
      'trace',
      negatable: false,
      help:
          'Emit per-event TRACE log lines on stderr (sub_recv, '
          'sub_event_empty). Off by default.',
    )
    ..addOption(
      'namespace',
      abbr: 'n',
      defaultsTo: applicationNamespace,
      hide: true,
      help: 'Application namespace (AtClientPreference.namespace)',
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
