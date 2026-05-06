// Worked example: publishing live docker stats to other atSigns via
// AtCollection sub-collections.
//
// Real mode (requires the docker CLI on PATH):
//   dart run bin/dockerstats_publish.dart \
//       -a @alice -P 5s --other-at-signs @bob,@carol
//
// Simulate mode (no docker required — useful for demos / chart UI dev):
//   dart run bin/dockerstats_publish.dart \
//       -a @alice -P 2s --other-at-signs @bob \
//       --simulate --simulate-hosts 3
//
// Tree shape (see lib/dockerstats/models.dart for full doc):
//   nodes  →  <hostId>  →  atsigns  →  <atSignId>  →  samples  →  <millis>
//
// Items expire after 10 minutes by default — receivers see a rolling
// window without any client-side eviction.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/dockerstats/docker_source.dart';
import 'package:at_client_examples/dockerstats/models.dart';
import 'package:at_client_examples/dockerstats/simulator.dart';
import 'package:at_client_examples/dockerstats/stats_source.dart';

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
  final postSyncDelay = _parseDuration(parsed['post-sync-delay'] as String);
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
  stdout.writeln('Connected as ${atClient.atSign}');

  // Domain-object factories. Required up front for sub-collection
  // rehydrate to recognise the wire-format tags.
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
    'sharing dockerstats with ${otherAtSigns.join(", ")} '
    'every ${pollingInterval.inMilliseconds}ms (TTL ${sampleExpiration.inMinutes}m)',
  );

  // Memoised sub-collections so we don't rebuild them per cycle.
  final publisher = _Publisher(
    nodes: nodes,
    otherAtSigns: otherAtSigns,
    log: log,
  );

  // Graceful shutdown on SIGINT / SIGTERM.
  final stop = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }

  // Main loop.
  var cyclesCompleted = 0;
  var totalSamples = 0;
  while (!stop.isCompleted) {
    for (final src in sources) {
      try {
        final samples = await src.sample();
        for (final s in samples) {
          await publisher.publishSample(s);
        }
        totalSamples += samples.length;
        log('published ${samples.length} sample(s) from ${src.hostname}');
      } catch (e, st) {
        log('source ${src.hostname} failed: $e');
        log(st.toString());
      }
    }
    cyclesCompleted++;

    if (cyclesLimit != null && cyclesCompleted >= cyclesLimit) {
      log(
        'reached --cycles=$cyclesLimit ($totalSamples sample(s) total); '
        'flushing sync before exit',
      );
      // Trigger an immediate sync round and wait until the local
      // commit-id reaches the atServer's snapshot. With a write-only
      // publisher, "local caught up to server" means our pushes have
      // landed and been acknowledged. The closed-loop subscriber
      // assertion ("subscriber received exactly $totalSamples
      // samples") is only meaningful once this completes.
      atClient.syncService.sync();
      try {
        await atClient.syncService.waitUntilCaughtUp(
          timeout: const Duration(seconds: 60),
        );
        log('sync caught up; emitted $totalSamples sample(s) total');
      } on TimeoutException {
        log(
          'sync did not catch up within 60s; '
          'subscriber-side count may be lower than $totalSamples',
        );
      }
      // Even after waitUntilCaughtUp returns, in-flight push tasks
      // for the very last batch of writes (specifically the
      // recipient-copy puts inside [_put]) may still be queued in
      // the publisher's sync pipeline waiting to be picked up by the
      // next sync round. waitUntilCaughtUp completes on commitId
      // equality at the time of the call, but the final cycle's
      // recipient writes can still be enqueued behind it. Sleep a
      // beat so they have a chance to flush before we tear the
      // process down. Bounded by --post-sync-delay (default 5s).
      if (postSyncDelay > Duration.zero) {
        log('post-sync settle: waiting ${postSyncDelay.inMilliseconds}ms');
        await Future.delayed(postSyncDelay);
      }
      break;
    }

    await Future.any([Future.delayed(pollingInterval), stop.future]);
  }
  log('shutting down');
  exit(0);
}

// ---------------------------------------------------------------------------
// Publisher — owns the per-host / per-atSign CItem caches.

class _Publisher {
  final AtCollection<HostNode> nodes;
  final Set<Atsign> otherAtSigns;
  final void Function(String) log;

  /// hostId → host CItem. Cached after first ensure to skip the
  /// existence probe on subsequent cycles.
  final Map<String, CItem<HostNode>> _hostItems = {};

  /// hostId → (atsigns sub-collection, atSignId → atSign CItem).
  final Map<String, _HostScopedCaches> _hostScoped = {};

  _Publisher({
    required this.nodes,
    required this.otherAtSigns,
    required this.log,
  });

  Future<void> publishSample(StatSample s) async {
    final hostId = sanitiseSegment(s.hostname);
    final atSignId = sanitiseSegment(s.atSign);

    final hostItem = await _ensureHost(hostId, s.hostname);
    final scoped = _hostScoped.putIfAbsent(
      hostId,
      () => _HostScopedCaches(
        atsigns: nodes.subCollection<AtsignOnHost>(
          parent: hostItem,
          subName: subAtsignsName,
          defaultExpiration: sampleExpiration,
        ),
      ),
    );

    final atItem = await _ensureAtsign(scoped, atSignId, s);

    final samples = scoped.samples.putIfAbsent(
      atSignId,
      () => scoped.atsigns.subCollection<StatSample>(
        parent: atItem,
        subName: subSamplesName,
        defaultExpiration: sampleExpiration,
      ),
    );

    await samples.create(
      id: s.millis.toString(),
      obj: s,
      sharedWith: otherAtSigns,
    );
  }

  Future<CItem<HostNode>> _ensureHost(String hostId, String hostname) async {
    final cached = _hostItems[hostId];
    if (cached != null) return cached;
    final item = await nodes.upsert(
      id: hostId,
      obj: HostNode(
        hostname: hostname,
        firstSeenMs: DateTime.now().millisecondsSinceEpoch,
      ),
      sharedWith: otherAtSigns,
    );
    _hostItems[hostId] = item;
    log('registered host "$hostname" (id=$hostId)');
    return item;
  }

  Future<CItem<AtsignOnHost>> _ensureAtsign(
    _HostScopedCaches scoped,
    String atSignId,
    StatSample s,
  ) async {
    final cached = scoped.atItems[atSignId];
    if (cached != null) return cached;
    final item = await scoped.atsigns.upsert(
      id: atSignId,
      obj: AtsignOnHost(
        atSign: s.atSign,
        hostname: s.hostname,
        firstSeenMs: DateTime.now().millisecondsSinceEpoch,
      ),
      sharedWith: otherAtSigns,
    );
    scoped.atItems[atSignId] = item;
    log('registered atSign "${s.atSign}" on host "${s.hostname}"');
    return item;
  }
}

class _HostScopedCaches {
  final AtCollection<AtsignOnHost> atsigns;
  final Map<String, CItem<AtsignOnHost>> atItems = {};
  final Map<String, AtCollection<StatSample>> samples = {};

  _HostScopedCaches({required this.atsigns});
}

// ---------------------------------------------------------------------------
// Args + helpers

ArgParser _buildParser() {
  final cols = stdout.hasTerminal ? stdout.terminalColumns : null;
  final p =
      ArgParser(usageLineLength: cols)
        ..addFlag('help', negatable: false, help: 'Show this help')
        // Required by CLIBase; long names match what CLIBase reads.
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
          help: 'Namespace',
        )
        ..addOption(
          'other-at-signs',
          help: 'Comma-separated atSign(s) to share docker stats with',
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
              'Bounded run: emit exactly this many polling cycles, '
              'flush sync, and exit. Useful for closed-loop verification '
              'against a subscriber. Defaults to unbounded.',
        )
        ..addOption(
          'post-sync-delay',
          defaultsTo: '5s',
          help:
              'Settle time after waitUntilCaughtUp before exit, to let '
              'the last cycle\'s recipient-copy writes flush through '
              'the sync pipeline. Only relevant with --cycles.',
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
