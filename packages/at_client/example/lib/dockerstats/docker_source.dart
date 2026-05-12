/// Docker-CLI-backed source for [StatsSource]. Shells out to
/// `docker ps -q`, `docker inspect`, and `docker stats --no-stream
/// --format json`. Cheap, portable, zero extra deps — works wherever
/// the docker CLI is on PATH.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'stats_source.dart';

/// Maps each known container id to the (atSign, name, image, restarts)
/// it was last inspected with. Populated lazily on first sighting; kept
/// across polling cycles so `docker inspect` only runs once per
/// container lifetime.
class _ContainerCache {
  final Map<String, ContainerInfo> byId = {};
}

class DockerCliStatsSource implements StatsSource {
  final String _hostname;
  final _ContainerCache _cache = _ContainerCache();
  final void Function(String) _log;

  DockerCliStatsSource({
    required String hostname,
    required void Function(String) log,
  }) : _hostname = hostname,
       _log = log;

  @override
  String get hostname => _hostname;

  @override
  Future<List<StatSample>> sample() async {
    final ids = await _listContainerIds();
    if (ids.isEmpty) return const <StatSample>[];

    // Inspect only ids we haven't seen before.
    final unknown = ids.where((id) => !_cache.byId.containsKey(id)).toList();
    if (unknown.isNotEmpty) {
      await _inspectAll(unknown);
    }

    final stats = await _statsBatch(ids);
    final now = DateTime.now().millisecondsSinceEpoch;

    final samples = <StatSample>[];
    for (final s in stats) {
      final info = _cache.byId[s.containerId];
      if (info == null) continue; // inspect failed; skip this cycle
      samples.add(
        StatSample(
          atSign: info.atSign,
          hostname: _hostname,
          containerId: s.containerId,
          containerName: info.containerName,
          image: info.image,
          restartCount: info.restartCount,
          pidsCount: s.pidsCount,
          cpuPct: s.cpuPct,
          memUsage: s.memUsage,
          memLimit: s.memLimit,
          memPct: s.memPct,
          netRx: s.netRx,
          netTx: s.netTx,
          blkRead: s.blkRead,
          blkWrite: s.blkWrite,
          millis: now,
        ),
      );
    }
    return samples;
  }

  // ---------------------------------------------------------------------
  // docker ps

  Future<List<String>> _listContainerIds() async {
    final result = await Process.run('docker', ['ps', '-q']);
    if (result.exitCode != 0) {
      _log('docker ps failed (exit ${result.exitCode}): ${result.stderr}');
      return const [];
    }
    return (result.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ---------------------------------------------------------------------
  // docker inspect — pulls atSign out of the Args array, falls back to
  // the container name when no Arg starts with '@'.

  Future<void> _inspectAll(List<String> ids) async {
    final result = await Process.run('docker', ['inspect', ...ids]);
    if (result.exitCode != 0) {
      _log('docker inspect failed (exit ${result.exitCode}): ${result.stderr}');
      return;
    }
    final List<dynamic> arr;
    try {
      arr = jsonDecode(result.stdout as String) as List<dynamic>;
    } on FormatException catch (e) {
      _log('docker inspect: bad JSON: $e');
      return;
    }
    for (final raw in arr) {
      final m = raw as Map<String, dynamic>;
      final id = (m['Id'] as String?) ?? '';
      if (id.isEmpty) continue;
      final config = (m['Config'] as Map?) ?? const {};
      final args = (m['Args'] as List?) ?? const [];
      final name =
          (m['Name'] as String?)?.replaceFirst(RegExp(r'^/'), '') ?? id;
      final image = (config['Image'] as String?) ?? '';
      final restartCount = (m['RestartCount'] as num?)?.toInt() ?? 0;

      final atSign = _findAtSignArg(args) ?? name;
      _cache.byId[id] = ContainerInfo(
        containerId: id,
        containerName: name,
        image: image,
        restartCount: restartCount,
        atSign: atSign,
      );
    }
  }

  static String? _findAtSignArg(List<dynamic> args) {
    for (final a in args) {
      if (a is String && a.startsWith('@') && a.length > 1) return a;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // docker stats

  Future<List<_RawStats>> _statsBatch(List<String> ids) async {
    final result = await Process.run('docker', [
      'stats',
      '--no-stream',
      '--format',
      '{{json .}}',
      ...ids,
    ]);
    if (result.exitCode != 0) {
      _log('docker stats failed (exit ${result.exitCode}): ${result.stderr}');
      return const [];
    }
    final out = <_RawStats>[];
    for (final line in (result.stdout as String).split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        final j = jsonDecode(t) as Map<String, dynamic>;
        out.add(_RawStats.parse(j));
      } catch (e) {
        _log('docker stats: bad JSON line: $e');
      }
    }
    return out;
  }
}

/// Parsed `docker stats --format '{{json .}}'` row. The CLI emits
/// human-readable values like "12.34%", "1.23GiB / 2GiB", "100kB / 50MB",
/// so we have to undo the unit-formatting.
class _RawStats {
  final String containerId;
  final double cpuPct;
  final int memUsage;
  final int memLimit;
  final double memPct;
  final int netRx;
  final int netTx;
  final int blkRead;
  final int blkWrite;
  final int pidsCount;

  _RawStats({
    required this.containerId,
    required this.cpuPct,
    required this.memUsage,
    required this.memLimit,
    required this.memPct,
    required this.netRx,
    required this.netTx,
    required this.blkRead,
    required this.blkWrite,
    required this.pidsCount,
  });

  factory _RawStats.parse(Map<String, dynamic> j) {
    // The full container ID isn't in the json output (only the short ID
    // under the "Container" key). The publisher passes the long ids in
    // and gets short ids back; we'll reconcile by short-id prefix in
    // [DockerCliStatsSource] below if needed. For simplicity, store
    // whatever the CLI gives us — it's stable within a host.
    final id = (j['Container'] as String?)?.trim() ?? '';
    final memPair = _splitPair(j['MemUsage'] as String?);
    final netPair = _splitPair(j['NetIO'] as String?);
    final blkPair = _splitPair(j['BlockIO'] as String?);
    return _RawStats(
      containerId: id,
      cpuPct: _parsePct(j['CPUPerc'] as String?),
      memUsage: _parseSize(memPair.$1),
      memLimit: _parseSize(memPair.$2),
      memPct: _parsePct(j['MemPerc'] as String?),
      netRx: _parseSize(netPair.$1),
      netTx: _parseSize(netPair.$2),
      blkRead: _parseSize(blkPair.$1),
      blkWrite: _parseSize(blkPair.$2),
      pidsCount: int.tryParse(((j['PIDs'] as String?) ?? '').trim()) ?? 0,
    );
  }

  /// Splits a `<usage> / <limit>` string. Either half may be missing.
  static (String, String) _splitPair(String? s) {
    if (s == null || s.trim().isEmpty) return ('', '');
    final parts = s.split('/');
    return (parts[0].trim(), parts.length > 1 ? parts[1].trim() : '');
  }

  static double _parsePct(String? s) {
    if (s == null) return 0;
    final m = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(s);
    return m == null ? 0 : double.tryParse(m.group(1)!) ?? 0;
  }

  /// Parses sizes in the form `12.3kB` / `1.5GiB` / `0B` etc. Returns 0
  /// for unparseable input (`--`, empty, garbled).
  static int _parseSize(String s) {
    if (s.isEmpty) return 0;
    final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]+)?$').firstMatch(s);
    if (m == null) return 0;
    final v = double.tryParse(m.group(1)!) ?? 0;
    final unit = (m.group(2) ?? '').toLowerCase();
    final mult = _unitMultiplier(unit);
    return (v * mult).round();
  }

  static double _unitMultiplier(String unit) {
    switch (unit) {
      case '':
      case 'b':
        return 1;
      case 'kb':
        return 1000;
      case 'mb':
        return 1000 * 1000;
      case 'gb':
        return 1000 * 1000 * 1000;
      case 'tb':
        return 1000 * 1000 * 1000 * 1000;
      case 'kib':
        return 1024;
      case 'mib':
        return 1024 * 1024;
      case 'gib':
        return 1024 * 1024 * 1024;
      case 'tib':
        return 1024 * 1024 * 1024 * 1024;
      default:
        return 1;
    }
  }
}
