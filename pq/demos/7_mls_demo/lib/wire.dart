import 'dart:convert';
import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart' show hex;
import 'ratchet_tree.dart' show CommitPath;
import 'key_package.dart';

String _b64(Uint8List b) => base64Encode(b);
Uint8List _ub64(String s) => Uint8List.fromList(base64Decode(s));

// ── GroupContext (AAD for all MLS crypto) ─────────────────────────────────────

class GroupContext {
  final String groupId;
  final int epoch;
  final Uint8List treeHash;
  final Uint8List confirmedTranscriptHash;

  GroupContext({
    required this.groupId,
    required this.epoch,
    required this.treeHash,
    required this.confirmedTranscriptHash,
  });

  Uint8List encode() {
    final j = jsonEncode({
      'groupId': groupId,
      'epoch': epoch,
      'treeHash': _b64(treeHash),
      'cth': _b64(confirmedTranscriptHash),
    });
    return Uint8List.fromList(utf8.encode(j));
  }
}

// ── MlsCiphertext (in-group app message) ─────────────────────────────────────

class MlsCiphertext {
  final String groupId;
  final int epoch;
  final int leafIndex;
  final int generation;
  final Uint8List senderDataNonce;
  final Uint8List senderDataCt; // ct || tag concatenated
  final Uint8List ct;
  final Uint8List tag;

  MlsCiphertext({
    required this.groupId,
    required this.epoch,
    required this.leafIndex,
    required this.generation,
    required this.senderDataNonce,
    required this.senderDataCt,
    required this.ct,
    required this.tag,
  });

  Map<String, dynamic> toJson() => {
        'type': 'mls_app',
        'groupId': groupId,
        'epoch': epoch,
        'leafIndex': leafIndex,
        'generation': generation,
        'senderDataNonce': _b64(senderDataNonce),
        'senderDataCt': _b64(senderDataCt),
        'ct': _b64(ct),
        'tag': _b64(tag),
      };

  factory MlsCiphertext.fromJson(Map<String, dynamic> j) => MlsCiphertext(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        leafIndex: j['leafIndex'] as int,
        generation: j['generation'] as int,
        senderDataNonce: _ub64(j['senderDataNonce'] as String),
        senderDataCt: _ub64(j['senderDataCt'] as String),
        ct: _ub64(j['ct'] as String),
        tag: _ub64(j['tag'] as String),
      );

  String encode() => jsonEncode(toJson());
  static MlsCiphertext decode(String s) =>
      MlsCiphertext.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── MlsCommit ─────────────────────────────────────────────────────────────────

class MlsCommit {
  final String groupId;
  final int newEpoch;
  final List<String> addedDevices;
  final List<String> removedDevices;
  final List<KeyPackage> newMemberKps;
  final CommitPath commitPath;
  final String signerDevice;
  final Uint8List signature;

  MlsCommit({
    required this.groupId,
    required this.newEpoch,
    required this.addedDevices,
    required this.removedDevices,
    required this.newMemberKps,
    required this.commitPath,
    required this.signerDevice,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'type': 'mls_commit',
        'groupId': groupId,
        'newEpoch': newEpoch,
        'addedDevices': addedDevices,
        'removedDevices': removedDevices,
        'newMemberKps': newMemberKps.map((k) => k.toJson()).toList(),
        'commitPath': commitPath.toJson(),
        'signerDevice': signerDevice,
        'signature': _b64(signature),
      };

  factory MlsCommit.fromJson(Map<String, dynamic> j) => MlsCommit(
        groupId: j['groupId'] as String,
        newEpoch: j['newEpoch'] as int,
        addedDevices: (j['addedDevices'] as List).cast<String>(),
        removedDevices: (j['removedDevices'] as List).cast<String>(),
        newMemberKps: (j['newMemberKps'] as List)
            .map((e) => KeyPackage.fromJson(e as Map<String, dynamic>))
            .toList(),
        commitPath:
            CommitPath.fromJson(j['commitPath'] as Map<String, dynamic>),
        signerDevice: j['signerDevice'] as String,
        signature: _ub64(j['signature'] as String),
      );

  Uint8List signedBytes() {
    final m = Map<String, dynamic>.from(toJson())..remove('signature');
    return Uint8List.fromList(utf8.encode(jsonEncode(m)));
  }

  String encode() => jsonEncode(toJson());
  static MlsCommit decode(String s) =>
      MlsCommit.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── MlsWelcome ────────────────────────────────────────────────────────────────

class MlsWelcome {
  final String groupId;
  final int epoch;
  final String targetDevice;
  final Uint8List pqxdhEkPk; // X25519 ephemeral pk (32 B)
  final Uint8List pqxdhKemCt; // X-Wing ciphertext (1120 B)
  final Uint8List ct; // AES-GCM ciphertext of serialized group state
  final Uint8List tag;
  final Uint8List nonce;
  final Uint8List senderIkPk; // sender's X25519 identity pk
  final String signerDevice;
  final Uint8List signature;

  MlsWelcome({
    required this.groupId,
    required this.epoch,
    required this.targetDevice,
    required this.pqxdhEkPk,
    required this.pqxdhKemCt,
    required this.ct,
    required this.tag,
    required this.nonce,
    required this.senderIkPk,
    required this.signerDevice,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'type': 'mls_welcome',
        'groupId': groupId,
        'epoch': epoch,
        'targetDevice': targetDevice,
        'pqxdhEkPk': _b64(pqxdhEkPk),
        'pqxdhKemCt': _b64(pqxdhKemCt),
        'ct': _b64(ct),
        'tag': _b64(tag),
        'nonce': _b64(nonce),
        'senderIkPk': _b64(senderIkPk),
        'signerDevice': signerDevice,
        'signature': _b64(signature),
      };

  factory MlsWelcome.fromJson(Map<String, dynamic> j) => MlsWelcome(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        targetDevice: j['targetDevice'] as String,
        pqxdhEkPk: _ub64(j['pqxdhEkPk'] as String),
        pqxdhKemCt: _ub64(j['pqxdhKemCt'] as String),
        ct: _ub64(j['ct'] as String),
        tag: _ub64(j['tag'] as String),
        nonce: _ub64(j['nonce'] as String),
        senderIkPk: _ub64(j['senderIkPk'] as String),
        signerDevice: j['signerDevice'] as String,
        signature: _ub64(j['signature'] as String),
      );

  Uint8List signedBytes() {
    final m = Map<String, dynamic>.from(toJson())..remove('signature');
    return Uint8List.fromList(utf8.encode(jsonEncode(m)));
  }

  String encode() => jsonEncode(toJson());
  static MlsWelcome decode(String s) =>
      MlsWelcome.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── JoinRequest ───────────────────────────────────────────────────────────────

class JoinRequest {
  final String groupId;
  final String fromDevice;
  final KeyPackage keyPackage;

  JoinRequest(
      {required this.groupId,
      required this.fromDevice,
      required this.keyPackage});

  Map<String, dynamic> toJson() => {
        'type': 'mls_join_request',
        'groupId': groupId,
        'fromDevice': fromDevice,
        'keyPackage': keyPackage.toJson(),
      };

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
        groupId: j['groupId'] as String,
        fromDevice: j['fromDevice'] as String,
        keyPackage:
            KeyPackage.fromJson(j['keyPackage'] as Map<String, dynamic>),
      );

  String encode() => jsonEncode(toJson());
  static JoinRequest decode(String s) =>
      JoinRequest.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── GroupPublicInfo ───────────────────────────────────────────────────────────

class GroupPublicInfo {
  final String groupId;
  final int epoch;
  final List<String> memberDevices;
  final Uint8List treeHash;

  GroupPublicInfo({
    required this.groupId,
    required this.epoch,
    required this.memberDevices,
    required this.treeHash,
  });

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'epoch': epoch,
        'memberDevices': memberDevices,
        'treeHash': _b64(treeHash),
      };

  factory GroupPublicInfo.fromJson(Map<String, dynamic> j) => GroupPublicInfo(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        memberDevices: (j['memberDevices'] as List).cast<String>(),
        treeHash: _ub64(j['treeHash'] as String),
      );

  String encode() => jsonEncode(toJson());
  static GroupPublicInfo decode(String s) =>
      GroupPublicInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
