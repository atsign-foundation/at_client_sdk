// Worked example: publishing live docker stats to other atSigns via
// raw notifications (NotificationService.send). Each sample is sent
// as one notification, with the StatSample JSON-encoded into the
// body and the container + host names sanitised into the namespace
// for receiver-side filtering:
//
//   notification key  =  <recipient>:sample.<container>.<host>.dockerstats.demos<publisher>
//   notification body =  jsonEncode(sample.toJson())
//
// Real mode (requires the docker CLI on PATH):
//   dart run bin/dockerstats_publish.dart \
//       -a @alice -P 5s --other-at-signs @bob,@carol
//
// Simulate mode (no docker required — useful for demos / chart UI dev):
//   dart run bin/dockerstats_publish.dart \
//       -a @alice -P 2s --other-at-signs @bob \
//       --simulate --simulate-hosts 3

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/dockerstats/docker_source.dart';
import 'package:at_client_examples/dockerstats/models.dart';
import 'package:at_client_examples/dockerstats/simulator.dart';
import 'package:at_client_examples/dockerstats/stats_source.dart';

const String applicationNamespace = 'dockerstats.demos';

/// Notification expiration (`ttln`). atServer drops notifications that
/// haven't been delivered within this window. High-frequency telemetry,
/// short window — receivers reconnecting after a longer outage just
/// resume from the next live sample rather than replaying old ones.
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

  final pollingInterval = _parseDuration(parsed['polling-interval'] as String);
  final simulate = parsed['simulate'] as bool;
  final simulateHosts =
      int.tryParse((parsed['simulate-hosts'] as String?) ?? '3') ?? 3;
  final simulateAtsigns = _splitCsv(parsed['simulate-atsigns'] as String?);
  final cyclesLimitRaw = parsed['cycles'] as String?;
  final int? cyclesLimit =
      cyclesLimitRaw == null ? null : int.tryParse(cyclesLimitRaw);
  if (cyclesLimitRaw != null && (cyclesLimit == null || cyclesLimit <= 0)) {
    stderr.writeln('--cycles must be a positive integer');
    exit(64);
  }
  final traceEnabled = parsed['trace'] as bool;
  final otherAtSigns =
      _splitCsv(
        parsed['other-at-signs'] as String?,
      ).map((s) => s.trim().toLowerCase().toAtsign()).toSet();
  if (otherAtSigns.isEmpty) {
    stderr.writeln('--other-at-signs must list at least one atSign');
    exit(64);
  }

  // Authenticate. We hand CLIBase our own ArgParser so it reads the
  // values it needs by long-name and our shorter abbreviations
  // (-a / -P / -v) reach the right options without colliding.
  stdout.writeln('Connecting...');
  final cliBase = await CLIBase.fromCommandLineArgs(args, parser: ap);
  final atClient = cliBase.atClient;
  stdout.writeln(
    'Connected as ${atClient.atSign} with'
    ' prefs.namespace=${atClient.getPreferences()?.namespace}',
  );

  // Build the source(s).
  void log(String s) => stdout.writeln('${DateTime.now()} | $s');
  final List<StatsSource> sources;
  if (simulate) {
    sources = SimulatedStatsSource.buildHosts(
      hostsCount: simulateHosts,
      atSigns: simulateAtsigns,
    );
    log(
      'simulate mode: ${sources.length} fake host(s), '
      '${simulateAtsigns.isEmpty ? "auto-named atSigns" : simulateAtsigns.join(",")}',
    );
  } else {
    sources = [
      DockerCliStatsSource(hostname: Platform.localHostname, log: log),
    ];
    log('docker mode: hostname=${Platform.localHostname}');
  }

  log(
    'publishing dockerstats notifications to ${otherAtSigns.join(", ")} '
    'every ${pollingInterval.inMilliseconds}ms '
    '(ttln ${sampleExpiration.inMinutes}m)',
  );

  // Graceful shutdown on SIGINT / SIGTERM. First signal completes
  // the `stop` Completer and the main loop unwinds at the next
  // race-against-stop await. A SECOND SIGINT (or SIGTERM) forces an
  // immediate process exit — the conventional CLI shape for "user is
  // hitting Ctrl-C twice because the graceful path is slower than
  // they're willing to wait".
  final stop = Completer<void>();
  void onSignal() {
    if (!stop.isCompleted) {
      stop.complete();
      stderr.writeln(
        '\n${DateTime.now()} | shutdown signal received — flushing in-flight '
        'work; press Ctrl-C again to force exit',
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

  // Main loop.
  var cyclesCompleted = 0;
  var totalSamples = 0;
  while (!stop.isCompleted) {
    for (final src in sources) {
      if (stop.isCompleted) break;
      try {
        final samples = await src.sample();
        for (final s in samples) {
          if (stop.isCompleted) break;
          await _publishSample(
            s,
            atClient: atClient,
            recipients: otherAtSigns,
            traceEnabled: traceEnabled,
            log: log,
          );
        }
        totalSamples += samples.length;
        log('published ${samples.length} sample(s) from ${src.hostname}');
      } catch (e, st) {
        log('source ${src.hostname} failed: $e');
        log(st.toString());
      }
    }
    if (stop.isCompleted) break;
    cyclesCompleted++;

    if (cyclesLimit != null && cyclesCompleted >= cyclesLimit) {
      log(
        'reached --cycles=$cyclesLimit ($totalSamples sample(s) total); '
        'exiting',
      );
      break;
    }

    await Future.any([Future.delayed(pollingInterval), stop.future]);
  }
  log('shutting down');
  exit(0);
}

// ---------------------------------------------------------------------------
// Publish

/// One [NotificationService.send] per (sample, recipient). The
/// notification namespace is `sample.<container>.<host>.dockerstats.demos`
/// so receivers can filter on a regex that combines the topic prefix
/// (`sample`) and the `dockerstats.demos` suffix without decoding the
/// body. Container and host names are sanitised to fit a namespace
/// segment (lowercase + `[a-z0-9_-]`).
Future<void> _publishSample(
  StatSample s, {
  required AtClient atClient,
  required Set<Atsign> recipients,
  required bool traceEnabled,
  required void Function(String) log,
}) async {
  final containerSeg = sanitiseSegment(s.containerName);
  final hostSeg = sanitiseSegment(s.hostname);
  final ns = 'sample.$containerSeg.$hostSeg.$applicationNamespace';
  final body = jsonEncode(s.toJson());

  for (final to in recipients) {
    final preMs = DateTime.now().microsecondsSinceEpoch;
    if (traceEnabled) {
      log(
        'TRACE pub_pre id=${s.millis} '
        'container=$containerSeg host=$hostSeg to=$to t_us=$preMs',
      );
    }
    try {
      await atClient.notificationService.send(
        to: to,
        idAndNamespace: ns,
        body: body,
        expiration: sampleExpiration,
      );
    } catch (e) {
      log('notify to $to failed: $e');
    }
    if (traceEnabled) {
      final postMs = DateTime.now().microsecondsSinceEpoch;
      log(
        'TRACE pub_post id=${s.millis} '
        'container=$containerSeg host=$hostSeg to=$to '
        't_us=$postMs dt_us=${postMs - preMs}',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Args + helpers

ArgParser _buildParser() {
  final cols = stdout.hasTerminal ? stdout.terminalColumns : null;
  final p =
      ArgParser(usageLineLength: cols)
        ..addFlag('help', negatable: false, help: 'Show this help')
        ..addOption(
          'atsign',
          abbr: 'a',
          mandatory: true,
          help: 'The atSign to publish from',
        )
        ..addOption(
          'namespace',
          abbr: 'n',
          defaultsTo: applicationNamespace,
          hide: true,
          help: 'Application namespace (AtClientPreference.namespace)',
        )
        ..addOption(
          'other-at-signs',
          help: 'Comma-separated atSign(s) to send sample notifications to',
          mandatory: true,
        )
        ..addOption(
          'polling-interval',
          abbr: 'P',
          defaultsTo: '5s',
          help: 'How often to publish stats (e.g. 250ms / 5s / 1m)',
        )
        ..addFlag(
          'simulate',
          negatable: false,
          help: 'Synthesise stats instead of calling the docker CLI',
        )
        ..addOption(
          'simulate-hosts',
          defaultsTo: '3',
          help: 'In simulate mode, how many fake hosts to fan out',
        )
        ..addOption(
          'simulate-atsigns',
          help:
              'Comma-separated atSigns to use on each fake host '
              '(default: 3 auto-named atSigns per host)',
        )
        ..addOption(
          'cycles',
          help:
              'Bounded run: emit exactly this many polling cycles and '
              'exit. Useful for closed-loop verification against a '
              'subscriber. Defaults to unbounded.',
        )
        ..addFlag(
          'trace',
          negatable: false,
          help:
              'Emit per-event TRACE log lines (pub_pre, pub_post). Off by '
              'default.',
        )
        // Standard at_cli_commons knobs, hidden by default.
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
        ..addOption('pass-phrase', aliases: const ['passPhrase'], hide: true)
        ..addOption('legacy-root-domain', hide: true)
        ..addFlag('verbose', abbr: 'v', negatable: false);
  return p;
}

/// Parses durations like `5s`, `250ms`, `1m`, `2h`. Bare integers are
/// interpreted as seconds for ergonomic backward compatibility.
Duration _parseDuration(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return const Duration(seconds: 5);
  final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m|h)?$').firstMatch(s);
  if (m == null) {
    throw FormatException('Bad polling interval "$raw" — try 5s / 250ms / 1m');
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

List<String> _splitCsv(String? raw) {
  if (raw == null) return const [];
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
