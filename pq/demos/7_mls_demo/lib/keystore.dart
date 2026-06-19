import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart' show Crypto;
import 'key_package.dart';
import 'ratchet_tree.dart';

String _b64(Uint8List b) => base64Encode(b);
Uint8List _ub64(String s) => Uint8List.fromList(base64Decode(s));

// Full actor identity: ML-DSA + all KeyPackage material.
class Identity {
  final String name;
  final String deviceId;
  final Uint8List mlDsaSk;
  final Uint8List mlDsaPk;
  final Uint8List ikSk; // X25519 identity sk
  final Uint8List ikPk;
  final Uint8List spkSk; // X25519 signed prekey sk
  final Uint8List spkPk;
  final Uint8List spkSig;
  Uint8List? opkSk;
  Uint8List? opkPk;
  Uint8List pqspkSk; // X-Wing PQ prekey sk
  Uint8List pqspkPk;
  Uint8List pqspkSig;
  Uint8List leafSk; // X-Wing TreeKEM leaf sk
  Uint8List leafPk;

  Identity({
    required this.name,
    required this.deviceId,
    required this.mlDsaSk,
    required this.mlDsaPk,
    required this.ikSk,
    required this.ikPk,
    required this.spkSk,
    required this.spkPk,
    required this.spkSig,
    this.opkSk,
    this.opkPk,
    required this.pqspkSk,
    required this.pqspkPk,
    required this.pqspkSig,
    required this.leafSk,
    required this.leafPk,
  });

  KeyPackage toKeyPackage() => KeyPackage(
        deviceId: deviceId,
        mlDsaPk: mlDsaPk,
        ikPk: ikPk,
        spkPk: spkPk,
        spkSig: spkSig,
        opkPk: opkPk,
        pqspkPk: pqspkPk,
        pqspkSig: pqspkSig,
        leafPk: leafPk,
      );

  KeyPackageSk toKeyPackageSk() => KeyPackageSk(
        deviceId: deviceId,
        mlDsaSk: mlDsaSk,
        ikSk: ikSk,
        spkSk: spkSk,
        opkSk: opkSk,
        pqspkSk: pqspkSk,
        leafSk: leafSk,
      );

  static Identity generate(Crypto c, String actorName, String actorDeviceId) {
    final (mlDsaPk, mlDsaSk) = c.mlDsa.generateKeypair();
    final (ikPk, ikSk) = c.x25519.keygen(c.rand);
    final (spkPk, spkSk) = c.x25519.keygen(c.rand);
    final spkSig = c.mlDsa.sign(mlDsaSk, spkPk);
    final (opkPk, opkSk) = c.x25519.keygen(c.rand);
    final (pqspkPk, pqspkSk) = c.xwing.keygen();
    final pqspkSig = c.mlDsa.sign(mlDsaSk, pqspkPk);
    final (leafPk, leafSk) = c.xwing.keygen();
    return Identity(
      name: actorName,
      deviceId: actorDeviceId,
      mlDsaSk: mlDsaSk,
      mlDsaPk: mlDsaPk,
      ikSk: ikSk,
      ikPk: ikPk,
      spkSk: spkSk,
      spkPk: spkPk,
      spkSig: spkSig,
      opkSk: opkSk,
      opkPk: opkPk,
      pqspkSk: pqspkSk,
      pqspkPk: pqspkPk,
      pqspkSig: pqspkSig,
      leafSk: leafSk,
      leafPk: leafPk,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'deviceId': deviceId,
        'mlDsaSk': _b64(mlDsaSk),
        'mlDsaPk': _b64(mlDsaPk),
        'ikSk': _b64(ikSk),
        'ikPk': _b64(ikPk),
        'spkSk': _b64(spkSk),
        'spkPk': _b64(spkPk),
        'spkSig': _b64(spkSig),
        'opkSk': opkSk == null ? null : _b64(opkSk!),
        'opkPk': opkPk == null ? null : _b64(opkPk!),
        'pqspkSk': _b64(pqspkSk),
        'pqspkPk': _b64(pqspkPk),
        'pqspkSig': _b64(pqspkSig),
        'leafSk': _b64(leafSk),
        'leafPk': _b64(leafPk),
      };

  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
        name: j['name'] as String,
        deviceId: j['deviceId'] as String,
        mlDsaSk: _ub64(j['mlDsaSk'] as String),
        mlDsaPk: _ub64(j['mlDsaPk'] as String),
        ikSk: _ub64(j['ikSk'] as String),
        ikPk: _ub64(j['ikPk'] as String),
        spkSk: _ub64(j['spkSk'] as String),
        spkPk: _ub64(j['spkPk'] as String),
        spkSig: _ub64(j['spkSig'] as String),
        opkSk:
            j['opkSk'] == null ? null : _ub64(j['opkSk'] as String),
        opkPk:
            j['opkPk'] == null ? null : _ub64(j['opkPk'] as String),
        pqspkSk: _ub64(j['pqspkSk'] as String),
        pqspkPk: _ub64(j['pqspkPk'] as String),
        pqspkSig: _ub64(j['pqspkSig'] as String),
        leafSk: _ub64(j['leafSk'] as String),
        leafPk: _ub64(j['leafPk'] as String),
      );
}

// Serializable group state for this actor.
class GroupState {
  final String groupId;
  int epoch;
  Uint8List initSecret;
  Uint8List confirmedTranscriptHash;
  RatchetTree tree;
  Map<String, int> memberLeafIndex; // deviceId → leaf index
  Map<int, String> leafIndexMember; // leaf index → deviceId
  Map<int, Uint8List> epochEncryptionSecrets; // bounded cache
  Uint8List? senderDataSecret;   // current epoch — for decrypting sender data after restart
  Uint8List? externalHpkeSk;    // current epoch — X25519 sk derived from epochSecret

  GroupState({
    required this.groupId,
    required this.epoch,
    required this.initSecret,
    required this.confirmedTranscriptHash,
    required this.tree,
    required this.memberLeafIndex,
    required this.leafIndexMember,
    Map<int, Uint8List>? epochEncryptionSecrets,
    this.senderDataSecret,
    this.externalHpkeSk,
  }) : epochEncryptionSecrets = epochEncryptionSecrets ?? {};

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'epoch': epoch,
        'initSecret': _b64(initSecret),
        'cth': _b64(confirmedTranscriptHash),
        'tree': tree.toJson(),
        'memberLeafIndex': memberLeafIndex,
        'leafIndexMember':
            leafIndexMember.map((k, v) => MapEntry(k.toString(), v)),
        'epochEncryptionSecrets': epochEncryptionSecrets
            .map((k, v) => MapEntry(k.toString(), _b64(v))),
        if (senderDataSecret != null) 'senderDataSecret': _b64(senderDataSecret!),
        if (externalHpkeSk != null) 'externalHpkeSk': _b64(externalHpkeSk!),
      };

  factory GroupState.fromJson(Map<String, dynamic> j) => GroupState(
        groupId: j['groupId'] as String,
        epoch: j['epoch'] as int,
        initSecret: _ub64(j['initSecret'] as String),
        confirmedTranscriptHash: _ub64(j['cth'] as String),
        tree: RatchetTree.fromJson(j['tree'] as Map<String, dynamic>),
        memberLeafIndex: Map<String, int>.from(
            (j['memberLeafIndex'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, v as int))),
        leafIndexMember: Map<int, String>.from(
            (j['leafIndexMember'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(int.parse(k), v as String))),
        epochEncryptionSecrets: Map<int, Uint8List>.from(
            (j['epochEncryptionSecrets'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(int.parse(k), _ub64(v as String)))),
        senderDataSecret: j['senderDataSecret'] == null
            ? null
            : _ub64(j['senderDataSecret'] as String),
        externalHpkeSk: j['externalHpkeSk'] == null
            ? null
            : _ub64(j['externalHpkeSk'] as String),
      );
}

class Keystore {
  final Identity identity;
  GroupState? groupState;

  Keystore({required this.identity, this.groupState});

  static String _filename(String actorName, String deviceId) =>
      '${actorName}_${deviceId}_mls7_ks.json';

  static Future<Keystore> loadOrGenerate(
      Crypto c, String actorName, String deviceId) async {
    final f = File(_filename(actorName, deviceId));
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Keystore(
        identity: Identity.fromJson(j['identity'] as Map<String, dynamic>),
        groupState: j['groupState'] == null
            ? null
            : GroupState.fromJson(j['groupState'] as Map<String, dynamic>),
      );
    }
    final ks = Keystore(identity: Identity.generate(c, actorName, deviceId));
    await ks.save();
    return ks;
  }

  Future<void> save() async {
    final j = {
      'identity': identity.toJson(),
      'groupState': groupState?.toJson(),
    };
    await File(_filename(identity.name, identity.deviceId)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(j),
        flush: true);
  }
}
