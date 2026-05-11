/// Domain objects + atKey-id sanitisation for the dockerstats demo.
///
/// Tree shape:
/// ```
///   nodes (root)
///     <hostId>           CItem<HostNode>
///       atsigns (sub)
///         <atSignId>     CItem<AtsignOnHost>
///           samples (sub)
///             <millis>   CItem<StatSample>   value = full snapshot
/// ```
///
/// `<hostId>` and `<atSignId>` are sanitised forms of the raw hostname /
/// atSign — atKey segments only allow `[a-z0-9_-]`, and the SDK enforces a
/// 128-char composed-namespace budget. We lowercase, replace illegal chars
/// with `_`, and (if the result exceeds 32 chars) truncate and append an
/// 8-hex-char FNV-1a digest of the original to keep collisions vanishingly
/// rare. The raw value is preserved inside the JSON envelope for display.
library;

import 'dart:convert';

/// Root collection name (within the application namespace).
const String collectionRootName = 'nodes';

/// First-level sub-collection on a [HostNode] CItem.
const String subAtsignsName = 'atsigns';

/// Second-level sub-collection on an [AtsignOnHost] CItem.
const String subSamplesName = 'samples';

/// Cap each path segment at 32 chars so worst-case composed namespace
/// `samples.<atSignId>.atsigns.<hostId>.nodes.dockerstats.demos`
/// stays well inside the SDK's 128-char budget (32 + 32 + structural ≈ 105).
const int _maxSegmentLen = 32;

/// FNV-1a 32-bit, hex-encoded. Used as a stable suffix for over-long ids;
/// not cryptographic, just collision-resistant enough for two short
/// human-friendly identifiers.
String _stableHash8(String input) {
  int hash = 0x811c9dc5;
  for (final byte in utf8.encode(input)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Lowercase + replace non-`[a-z0-9_-]` with `_`; truncate-and-hash if the
/// result exceeds [_maxSegmentLen]. Returns a non-empty atKey-safe segment.
String sanitiseSegment(String input) {
  if (input.isEmpty) return 'empty';
  final cleaned = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  final base = trimmed.isEmpty ? 'x' : trimmed;
  if (base.length <= _maxSegmentLen) return base;
  final keep = _maxSegmentLen - 9; // 1 underscore + 8 hex
  return '${base.substring(0, keep)}_${_stableHash8(input)}';
}

// ---------------------------------------------------------------------------
// HostNode — root CItem per host

class HostNode {
  /// Raw hostname before sanitisation, kept for receiver display.
  final String hostname;
  final int firstSeenMs;

  HostNode({required this.hostname, required this.firstSeenMs});

  Map<String, dynamic> toJson() => {
    'hostname': hostname,
    'firstSeenMs': firstSeenMs,
  };

  factory HostNode.fromJson(Map<String, dynamic> j) => HostNode(
    hostname: j['hostname'] as String,
    firstSeenMs: (j['firstSeenMs'] as num).toInt(),
  );
}

// ---------------------------------------------------------------------------
// AtsignOnHost — first-level sub CItem; one per atSign-running-on-host

class AtsignOnHost {
  /// Raw atSign string, e.g. "@bob".
  final String atSign;
  final String hostname;
  final int firstSeenMs;

  AtsignOnHost({
    required this.atSign,
    required this.hostname,
    required this.firstSeenMs,
  });

  Map<String, dynamic> toJson() => {
    'atSign': atSign,
    'hostname': hostname,
    'firstSeenMs': firstSeenMs,
  };

  factory AtsignOnHost.fromJson(Map<String, dynamic> j) => AtsignOnHost(
    atSign: j['atSign'] as String,
    hostname: j['hostname'] as String,
    firstSeenMs: (j['firstSeenMs'] as num).toInt(),
  );
}

// ---------------------------------------------------------------------------
// StatSample — leaf CItem; one per polling cycle per container

class StatSample {
  final String atSign;
  final String hostname;
  final String containerId;
  final String containerName;
  final String image;
  final int restartCount;
  final int pidsCount;

  /// CPU usage as a percentage of host capacity (0..100*nCPU on Docker).
  final double cpuPct;

  /// Memory usage in bytes.
  final int memUsage;

  /// Memory limit in bytes; 0 if unset (means "no limit / host total").
  final int memLimit;

  /// Memory usage / limit as a percentage (0..100).
  final double memPct;

  /// Cumulative network bytes received since container start.
  final int netRx;

  /// Cumulative network bytes transmitted since container start.
  final int netTx;

  /// Cumulative bytes read from block devices since container start.
  final int blkRead;

  /// Cumulative bytes written to block devices since container start.
  final int blkWrite;

  /// Sample timestamp; doubles as the leaf CItem id.
  final int millis;

  StatSample({
    required this.atSign,
    required this.hostname,
    required this.containerId,
    required this.containerName,
    required this.image,
    required this.restartCount,
    required this.pidsCount,
    required this.cpuPct,
    required this.memUsage,
    required this.memLimit,
    required this.memPct,
    required this.netRx,
    required this.netTx,
    required this.blkRead,
    required this.blkWrite,
    required this.millis,
  });

  Map<String, dynamic> toJson() => {
    'atSign': atSign,
    'hostname': hostname,
    'containerId': containerId,
    'containerName': containerName,
    'image': image,
    'restartCount': restartCount,
    'pidsCount': pidsCount,
    'cpuPct': cpuPct,
    'memUsage': memUsage,
    'memLimit': memLimit,
    'memPct': memPct,
    'netRx': netRx,
    'netTx': netTx,
    'blkRead': blkRead,
    'blkWrite': blkWrite,
    'millis': millis,
  };

  factory StatSample.fromJson(Map<String, dynamic> j) => StatSample(
    atSign: j['atSign'] as String,
    hostname: j['hostname'] as String,
    containerId: j['containerId'] as String,
    containerName: j['containerName'] as String,
    image: j['image'] as String? ?? '',
    restartCount: (j['restartCount'] as num?)?.toInt() ?? 0,
    pidsCount: (j['pidsCount'] as num?)?.toInt() ?? 0,
    cpuPct: (j['cpuPct'] as num).toDouble(),
    memUsage: (j['memUsage'] as num).toInt(),
    memLimit: (j['memLimit'] as num).toInt(),
    memPct: (j['memPct'] as num).toDouble(),
    netRx: (j['netRx'] as num).toInt(),
    netTx: (j['netTx'] as num).toInt(),
    blkRead: (j['blkRead'] as num).toInt(),
    blkWrite: (j['blkWrite'] as num).toInt(),
    millis: (j['millis'] as num).toInt(),
  );
}

/// Per-container metadata the publisher carries between docker-source
/// and the AtCollection write path. Not transmitted as a CItem.
class ContainerInfo {
  final String containerId;
  final String containerName;
  final String image;
  final int restartCount;
  final String atSign;

  ContainerInfo({
    required this.containerId,
    required this.containerName,
    required this.image,
    required this.restartCount,
    required this.atSign,
  });
}
