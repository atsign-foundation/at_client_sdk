// Wire envelope types — JSON-encoded into the inbox row's value field.
//
// Four types, dispatched by the `type` discriminator:
//   AppMessage          in-group app msg (recipient = current group members)
//   ExternalAppMessage  cross-name msg (recipient = a peer name's group)
//   Commit              add/remove/update; carries per-member wraps of new group_secret
//   Welcome             for a new joiner; carries full GroupState public part
//                       + HPKE-sealed group_secret to the joiner's HPKE PK

import 'dart:convert';
import 'dart:typed_data';
import 'openssl.dart' show hex;

String _b64(Uint8List b) => base64Encode(b);
Uint8List _ub64(String s) => Uint8List.fromList(base64Decode(s));
String? _b64opt(Uint8List? b) => b == null ? null : base64Encode(b);
Uint8List? _ub64opt(String? s) => s == null ? null : Uint8List.fromList(base64Decode(s));

// ── Member descriptor (in Commits, Welcomes, GroupState) ────────────────────

class MemberDesc {
  final String deviceId;
  final Uint8List mlDsaPk;     // identity signing key
  final Uint8List hpkeKemPk;   // ML-KEM PK for receiving wraps + cross-msgs

  MemberDesc({
    required this.deviceId,
    required this.mlDsaPk,
    required this.hpkeKemPk,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'mlDsaPk': _b64(mlDsaPk),
        'hpkeKemPk': _b64(hpkeKemPk),
      };

  factory MemberDesc.fromJson(Map<String, dynamic> j) => MemberDesc(
        deviceId: j['deviceId'] as String,
        mlDsaPk: _ub64(j['mlDsaPk'] as String),
        hpkeKemPk: _ub64(j['hpkeKemPk'] as String),
      );

  String describe() =>
      '$deviceId  ml-dsa.pk=${hex(mlDsaPk, maxBytes: 6)}  hpke.pk=${hex(hpkeKemPk, maxBytes: 6)}';
}

// ── App message (in-group) ──────────────────────────────────────────────────

class AppMessage {
  final String groupId;
  final int epoch;
  final String senderDevice;
  final int messageIndex;
  final Uint8List nonce;
  final Uint8List ct;
  final Uint8List mac;

  AppMessage({
    required this.groupId,
    required this.epoch,
    required this.senderDevice,
    required this.messageIndex,
    required this.nonce,
    required this.ct,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
        'type': 'app',
        'groupId': groupId,
        'epoch': epoch,
        'senderDevice': senderDevice,
        'messageIndex': messageIndex,
        'nonce': _b64(nonce),
        'ct': _b64(ct),
        'mac': _b64(mac),
      };

  factory AppMessage.fromJson(Map<String, dynamic> j) => AppMessage(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        senderDevice: j['senderDevice'] as String,
        messageIndex: j['messageIndex'] as int,
        nonce: _ub64(j['nonce'] as String),
        ct: _ub64(j['ct'] as String),
        mac: _ub64(j['mac'] as String),
      );

  int get sizeBytes => nonce.length + ct.length + mac.length + 30;
}

// ── External app message (cross-name) ───────────────────────────────────────

class ExternalAppMessage {
  final String fromName;
  final String fromDevice;
  final String toGroupId;
  final int observedEpoch;
  final Uint8List enc;          // HPKE KEM ciphertext (ML-KEM-768 → 1088 B)
  final Uint8List ct;           // HPKE AEAD ciphertext of the payload
  final Uint8List tag;          // AES-GCM tag (16 B)
  final Uint8List signerPk;     // sender's ML-DSA identity PK
  final Uint8List signature;    // ML-DSA over (enc || ct || tag)

  ExternalAppMessage({
    required this.fromName,
    required this.fromDevice,
    required this.toGroupId,
    required this.observedEpoch,
    required this.enc,
    required this.ct,
    required this.tag,
    required this.signerPk,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'type': 'external_app',
        'fromName': fromName,
        'fromDevice': fromDevice,
        'toGroupId': toGroupId,
        'observedEpoch': observedEpoch,
        'enc': _b64(enc),
        'ct': _b64(ct),
        'tag': _b64(tag),
        'signerPk': _b64(signerPk),
        'signature': _b64(signature),
      };

  factory ExternalAppMessage.fromJson(Map<String, dynamic> j) => ExternalAppMessage(
        fromName: j['fromName'] as String,
        fromDevice: j['fromDevice'] as String,
        toGroupId: j['toGroupId'] as String,
        observedEpoch: j['observedEpoch'] as int,
        enc: _ub64(j['enc'] as String),
        ct: _ub64(j['ct'] as String),
        tag: _ub64(j['tag'] as String),
        signerPk: _ub64(j['signerPk'] as String),
        signature: _ub64(j['signature'] as String),
      );

  int get sizeBytes =>
      enc.length + ct.length + tag.length + signature.length + 30;

  /// Bytes signed by the sender (encrypt-then-MAC-bound to enc + tag).
  Uint8List signedBytes() {
    final out = Uint8List(enc.length + ct.length + tag.length);
    out.setAll(0, enc);
    out.setAll(enc.length, ct);
    out.setAll(enc.length + ct.length, tag);
    return out;
  }
}

// ── Commit ──────────────────────────────────────────────────────────────────

class CommitWrap {
  final String targetDevice;
  final Uint8List enc;          // HPKE KEM ciphertext
  final Uint8List ct;           // HPKE AEAD ciphertext of the new group_secret
  final Uint8List tag;

  CommitWrap({
    required this.targetDevice,
    required this.enc,
    required this.ct,
    required this.tag,
  });

  Map<String, dynamic> toJson() => {
        'targetDevice': targetDevice,
        'enc': _b64(enc),
        'ct': _b64(ct),
        'tag': _b64(tag),
      };

  factory CommitWrap.fromJson(Map<String, dynamic> j) => CommitWrap(
        targetDevice: j['targetDevice'] as String,
        enc: _ub64(j['enc'] as String),
        ct: _ub64(j['ct'] as String),
        tag: _ub64(j['tag'] as String),
      );
}

class Commit {
  final String groupId;
  final int newEpoch;
  final List<MemberDesc> newMembers;       // full member list after the commit
  final List<MemberDesc> additions;        // devices added (subset of newMembers)
  final List<String> removals;             // device IDs removed
  final List<CommitWrap> wraps;            // one per new member (key = newMember.deviceId)
  final String signerDevice;
  final Uint8List signature;               // ML-DSA over canonical bytes

  Commit({
    required this.groupId,
    required this.newEpoch,
    required this.newMembers,
    required this.additions,
    required this.removals,
    required this.wraps,
    required this.signerDevice,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'type': 'commit',
        'groupId': groupId,
        'newEpoch': newEpoch,
        'newMembers': newMembers.map((m) => m.toJson()).toList(),
        'additions': additions.map((m) => m.toJson()).toList(),
        'removals': removals,
        'wraps': wraps.map((w) => w.toJson()).toList(),
        'signerDevice': signerDevice,
        'signature': _b64(signature),
      };

  factory Commit.fromJson(Map<String, dynamic> j) => Commit(
        groupId: j['groupId'] as String,
        newEpoch: j['newEpoch'] as int,
        newMembers: (j['newMembers'] as List)
            .map((e) => MemberDesc.fromJson(e as Map<String, dynamic>))
            .toList(),
        additions: (j['additions'] as List)
            .map((e) => MemberDesc.fromJson(e as Map<String, dynamic>))
            .toList(),
        removals: (j['removals'] as List).cast<String>(),
        wraps: (j['wraps'] as List)
            .map((e) => CommitWrap.fromJson(e as Map<String, dynamic>))
            .toList(),
        signerDevice: j['signerDevice'] as String,
        signature: _ub64(j['signature'] as String),
      );

  /// Canonical bytes signed by the committer (everything except the signature).
  Uint8List signedBytes() {
    final m = Map<String, dynamic>.from(toJson())..remove('signature');
    return Uint8List.fromList(utf8.encode(jsonEncode(m)));
  }
}

// ── Welcome ─────────────────────────────────────────────────────────────────

class Welcome {
  final String groupId;
  final int epoch;
  final List<MemberDesc> members;
  final String targetDevice;
  final Uint8List enc;
  final Uint8List ct;
  final Uint8List tag;
  final String signerDevice;
  final Uint8List signature;

  Welcome({
    required this.groupId,
    required this.epoch,
    required this.members,
    required this.targetDevice,
    required this.enc,
    required this.ct,
    required this.tag,
    required this.signerDevice,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'type': 'welcome',
        'groupId': groupId,
        'epoch': epoch,
        'members': members.map((m) => m.toJson()).toList(),
        'targetDevice': targetDevice,
        'enc': _b64(enc),
        'ct': _b64(ct),
        'tag': _b64(tag),
        'signerDevice': signerDevice,
        'signature': _b64(signature),
      };

  factory Welcome.fromJson(Map<String, dynamic> j) => Welcome(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        members: (j['members'] as List)
            .map((e) => MemberDesc.fromJson(e as Map<String, dynamic>))
            .toList(),
        targetDevice: j['targetDevice'] as String,
        enc: _ub64(j['enc'] as String),
        ct: _ub64(j['ct'] as String),
        tag: _ub64(j['tag'] as String),
        signerDevice: j['signerDevice'] as String,
        signature: _ub64(j['signature'] as String),
      );

  Uint8List signedBytes() {
    final m = Map<String, dynamic>.from(toJson())..remove('signature');
    return Uint8List.fromList(utf8.encode(jsonEncode(m)));
  }
}

// ── Join request (broadcast when a new device starts and sees an existing group) ─

class JoinRequest {
  final String groupId;
  final String fromDevice;
  final Uint8List mlDsaPk;
  final Uint8List hpkeKemPk;

  JoinRequest({
    required this.groupId,
    required this.fromDevice,
    required this.mlDsaPk,
    required this.hpkeKemPk,
  });

  Map<String, dynamic> toJson() => {
        'type': 'join_request',
        'groupId': groupId,
        'fromDevice': fromDevice,
        'mlDsaPk': _b64(mlDsaPk),
        'hpkeKemPk': _b64(hpkeKemPk),
      };

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
        groupId: j['groupId'] as String,
        fromDevice: j['fromDevice'] as String,
        mlDsaPk: _ub64(j['mlDsaPk'] as String),
        hpkeKemPk: _ub64(j['hpkeKemPk'] as String),
      );
}

// ── Group public info (published as record 'group') ─────────────────────────
//
// Anything anyone (including non-members) can read about a group.

class GroupPublicInfo {
  final String groupId;
  final int epoch;
  final List<MemberDesc> members;
  final Uint8List externalHpkePk;   // for cross-name senders to encrypt against

  GroupPublicInfo({
    required this.groupId,
    required this.epoch,
    required this.members,
    required this.externalHpkePk,
  });

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'epoch': epoch,
        'members': members.map((m) => m.toJson()).toList(),
        'externalHpkePk': _b64(externalHpkePk),
      };

  factory GroupPublicInfo.fromJson(Map<String, dynamic> j) => GroupPublicInfo(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        members: (j['members'] as List)
            .map((e) => MemberDesc.fromJson(e as Map<String, dynamic>))
            .toList(),
        externalHpkePk: _ub64(j['externalHpkePk'] as String),
      );

  String encode() => jsonEncode(toJson());
  static GroupPublicInfo decode(String s) =>
      GroupPublicInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

String unusedB64Helper() => _b64opt(null) ?? '';
Uint8List unusedUb64Helper() => _ub64opt(null) ?? Uint8List(0);
