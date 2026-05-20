/// Mirror of the publisher's domain objects (see
/// `packages/at_client/example/lib/dockerstats/models.dart`). Kept
/// receiver-side so the Flutter app doesn't need a path-dependency on
/// the CLI example package.
library;

class HostNode {
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

class AtsignOnHost {
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

class StatSample {
  final String atSign;
  final String hostname;
  final String containerId;
  final String containerName;
  final String image;
  final int restartCount;
  final int pidsCount;
  final double cpuPct;
  final int memUsage;
  final int memLimit;
  final double memPct;
  final int netRx;
  final int netTx;
  final int blkRead;
  final int blkWrite;
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
