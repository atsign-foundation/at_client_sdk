// Per-actor JSON keystore.
//
// Each actor file:  <name>:<device>_keystore.json
//
// Holds:
//   - identity        long-lived ML-DSA + ML-KEM material for this device
//   - ownGroup        this device's current view of <name>'s group
//   - peerCaches      cached GroupPublicInfo + trusted signer PKs per other name

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'openssl.dart' show Crypto;
import 'wire.dart';

String _b64(Uint8List b) => base64Encode(b);
Uint8List _ub64(String s) => Uint8List.fromList(base64Decode(s));

// ── Identity ────────────────────────────────────────────────────────────────

class Identity {
  final String name;
  final String deviceId;
  final Uint8List mlDsaSk;
  final Uint8List mlDsaPk;
  final Uint8List hpkeKemSk;
  final Uint8List hpkeKemPk;

  Identity({
    required this.name,
    required this.deviceId,
    required this.mlDsaSk,
    required this.mlDsaPk,
    required this.hpkeKemSk,
    required this.hpkeKemPk,
  });

  MemberDesc toMemberDesc() => MemberDesc(
        deviceId: deviceId,
        mlDsaPk: mlDsaPk,
        hpkeKemPk: hpkeKemPk,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'deviceId': deviceId,
        'mlDsaSk': _b64(mlDsaSk),
        'mlDsaPk': _b64(mlDsaPk),
        'hpkeKemSk': _b64(hpkeKemSk),
        'hpkeKemPk': _b64(hpkeKemPk),
      };

  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
        name: j['name'] as String,
        deviceId: j['deviceId'] as String,
        mlDsaSk: _ub64(j['mlDsaSk'] as String),
        mlDsaPk: _ub64(j['mlDsaPk'] as String),
        hpkeKemSk: _ub64(j['hpkeKemSk'] as String),
        hpkeKemPk: _ub64(j['hpkeKemPk'] as String),
      );

  static Identity generate(Crypto c, String name, String deviceId) {
    final (mlDsaPk, mlDsaSk) = c.mlDsa.generateKeypair();
    final (kemPk, kemSk) = c.xwing.keygen();
    return Identity(
      name: name,
      deviceId: deviceId,
      mlDsaSk: mlDsaSk,
      mlDsaPk: mlDsaPk,
      hpkeKemSk: kemSk,
      hpkeKemPk: kemPk,
    );
  }
}

// ── OwnGroupState — this device's view of its own group ─────────────────────

/// PCS heartbeat threshold — total app messages observed in an epoch before
/// the leader (lowest deviceId) fires an empty Commit to rotate the group
/// secret. Matches Triple Ratchet's per-round-trip cadence more closely.
const int kHeartbeatMsgThreshold = 10;

/// How many prior epochs' groupSecrets to retain for late-arriving app msgs.
/// Each entry weakens FS slightly, so keep this tight. 2 = "previous epoch
/// stragglers ok"; longer would let attackers go further back on compromise.
const int kEpochCacheDepth = 2;

class OwnGroupState {
  final String groupId;
  int epoch;
  Uint8List groupSecret;
  Uint8List externalHpkeSk;     // shared by all current members; rotates on Commit
  Uint8List externalHpkePk;     // matches externalHpkeSk
  List<MemberDesc> members;
  // per-sender message counter for AppMessages within current epoch
  Map<String, int> sentByThisDevice;
  // total app messages observed in the current epoch (sent + received).
  // Drives the PCS heartbeat; reset on every Commit.
  int msgsSinceCommit;
  // bounded ring of prior (epoch → groupSecret) — lets us still decrypt
  // late-arriving app messages from an epoch we have just left.
  // Insertion order matters; trimmed to kEpochCacheDepth on each mutation.
  Map<int, Uint8List> recentEpochSecrets;

  OwnGroupState({
    required this.groupId,
    required this.epoch,
    required this.groupSecret,
    required this.externalHpkeSk,
    required this.externalHpkePk,
    required this.members,
    Map<String, int>? sentByThisDevice,
    this.msgsSinceCommit = 0,
    Map<int, Uint8List>? recentEpochSecrets,
  })  : sentByThisDevice = sentByThisDevice ?? {},
        recentEpochSecrets = recentEpochSecrets ?? {};

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'epoch': epoch,
        'groupSecret': _b64(groupSecret),
        'externalHpkeSk': _b64(externalHpkeSk),
        'externalHpkePk': _b64(externalHpkePk),
        'members': members.map((m) => m.toJson()).toList(),
        'sentByThisDevice': sentByThisDevice,
        'msgsSinceCommit': msgsSinceCommit,
        'recentEpochSecrets':
            recentEpochSecrets.map((k, v) => MapEntry(k.toString(), _b64(v))),
      };

  factory OwnGroupState.fromJson(Map<String, dynamic> j) => OwnGroupState(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        groupSecret: _ub64(j['groupSecret'] as String),
        externalHpkeSk: _ub64(j['externalHpkeSk'] as String),
        externalHpkePk: _ub64(j['externalHpkePk'] as String),
        members: (j['members'] as List)
            .map((e) => MemberDesc.fromJson(e as Map<String, dynamic>))
            .toList(),
        sentByThisDevice: Map<String, int>.from(
            (j['sentByThisDevice'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, v as int))),
        msgsSinceCommit: (j['msgsSinceCommit'] as int?) ?? 0,
        recentEpochSecrets: Map<int, Uint8List>.from(
            (j['recentEpochSecrets'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(int.parse(k), _ub64(v as String)))),
      );

  /// Record the current (epoch, groupSecret) into the prior-epoch cache before
  /// the caller overwrites them with the next epoch's values. Trims to
  /// [kEpochCacheDepth] entries (most-recent kept).
  void rememberCurrentForCache() {
    recentEpochSecrets[epoch] = groupSecret;
    if (recentEpochSecrets.length > kEpochCacheDepth) {
      final sortedKeys = recentEpochSecrets.keys.toList()..sort();
      while (recentEpochSecrets.length > kEpochCacheDepth) {
        recentEpochSecrets.remove(sortedKeys.removeAt(0));
      }
    }
  }

  /// Caller is the leader (lowest deviceId in current members) AND we have
  /// accumulated ≥ [kHeartbeatMsgThreshold] in-epoch messages.
  bool shouldHeartbeat(String selfDeviceId) {
    if (msgsSinceCommit < kHeartbeatMsgThreshold) return false;
    if (members.isEmpty) return false;
    final lowest = members
        .map((m) => m.deviceId)
        .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    return lowest == selfDeviceId;
  }

  GroupPublicInfo toPublicInfo() => GroupPublicInfo(
        groupId: groupId,
        epoch: epoch,
        members: members,
        externalHpkePk: externalHpkePk,
      );
}

// ── Per-peer cache (TOFU) ───────────────────────────────────────────────────

class PeerCache {
  GroupPublicInfo? groupInfo;
  // device_id → mlDsaPk we have TOFU-pinned for that device on this peer
  final Map<String, Uint8List> trustedSignerPks;

  PeerCache({this.groupInfo, Map<String, Uint8List>? trustedSignerPks})
      : trustedSignerPks = trustedSignerPks ?? {};

  Map<String, dynamic> toJson() => {
        'groupInfo': groupInfo?.toJson(),
        'trustedSignerPks':
            trustedSignerPks.map((k, v) => MapEntry(k, _b64(v))),
      };

  factory PeerCache.fromJson(Map<String, dynamic> j) => PeerCache(
        groupInfo: j['groupInfo'] == null
            ? null
            : GroupPublicInfo.fromJson(j['groupInfo'] as Map<String, dynamic>),
        trustedSignerPks: Map<String, Uint8List>.from(
            (j['trustedSignerPks'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, _ub64(v as String)))),
      );
}

// ── Keystore (top-level container) ──────────────────────────────────────────

class Keystore {
  final Identity identity;
  OwnGroupState? ownGroup;
  final Map<String, PeerCache> peerCaches;

  Keystore({
    required this.identity,
    this.ownGroup,
    Map<String, PeerCache>? peerCaches,
  }) : peerCaches = peerCaches ?? {};

  static String _filename(String name, String deviceId) =>
      '${name}-${deviceId}_keystore.json';

  static Future<Keystore> loadOrGenerate(
      Crypto c, String name, String deviceId) async {
    final f = File(_filename(name, deviceId));
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Keystore(
        identity: Identity.fromJson(j['identity'] as Map<String, dynamic>),
        ownGroup: j['ownGroup'] == null
            ? null
            : OwnGroupState.fromJson(j['ownGroup'] as Map<String, dynamic>),
        peerCaches: (j['peerCaches'] as Map<String, dynamic>? ?? {}).map(
            (k, v) =>
                MapEntry(k, PeerCache.fromJson(v as Map<String, dynamic>))),
      );
    }
    final identity = Identity.generate(c, name, deviceId);
    final ks = Keystore(identity: identity);
    await ks.save();
    return ks;
  }

  Future<void> save() async {
    final j = {
      'identity': identity.toJson(),
      'ownGroup': ownGroup?.toJson(),
      'peerCaches': peerCaches.map((k, v) => MapEntry(k, v.toJson())),
    };
    await File(_filename(identity.name, identity.deviceId)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(j),
        flush: true);
  }
}
