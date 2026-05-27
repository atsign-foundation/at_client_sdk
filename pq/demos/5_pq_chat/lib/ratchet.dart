// Ratchet algorithm: PQXDH handshake + Triple Ratchet (Signal Double Ratchet
// + KEM ratchet). Algorithm ported verbatim from pq/demos/4_pq_chat/bin/demo.dart
// with inline tracing removed. RatchetState is JSON-codable for keystore persistence.

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto.dart';
import 'wire.dart';

const int kemRatchetEvery = 10;

/// Long-lived identity + medium-lived signed pre-key for one party.
class Identity {
  final String name;
  final SimpleKeyPairData ikDhKp;
  final Uint8List ikDhPk;
  final SimpleKeyPairData ikSigKp;
  final Uint8List ikSigPk;
  final SimpleKeyPairData spkDhKp;
  final Uint8List spkDhPk;
  final Uint8List spkKemSk;
  final Uint8List spkKemPk;
  final Uint8List spkSignature;

  Identity({
    required this.name,
    required this.ikDhKp,
    required this.ikDhPk,
    required this.ikSigKp,
    required this.ikSigPk,
    required this.spkDhKp,
    required this.spkDhPk,
    required this.spkKemSk,
    required this.spkKemPk,
    required this.spkSignature,
  });

  /// Public pre-key bundle (the half that gets published).
  Map<String, dynamic> publicBundle() => {
        'name': name,
        'ikDhPk': toHex(ikDhPk),
        'ikSigPk': toHex(ikSigPk),
        'spkDhPk': toHex(spkDhPk),
        'spkKemPk': toHex(spkKemPk),
        'spkSig': toHex(spkSignature),
      };

  /// Per-party private material, hex-encoded for keystore JSON storage.
  Future<Map<String, dynamic>> toPrivateJson() async => {
        'ikDhSk': toHex((await ikDhKp.extractPrivateKeyBytes())),
        'ikDhPk': toHex(ikDhPk),
        'ikSigSk': toHex((await ikSigKp.extractPrivateKeyBytes())),
        'ikSigPk': toHex(ikSigPk),
        'spkDhSk': toHex((await spkDhKp.extractPrivateKeyBytes())),
        'spkDhPk': toHex(spkDhPk),
        'spkKemSk': toHex(spkKemSk),
        'spkKemPk': toHex(spkKemPk),
        'spkSig': toHex(spkSignature),
      };

  static Future<Identity> fromPrivateJson(
      String name, Map<String, dynamic> j) async {
    final ikDhSk = fromHex(j['ikDhSk'] as String);
    final ikDhPk = fromHex(j['ikDhPk'] as String);
    final ikSigSk = fromHex(j['ikSigSk'] as String);
    final ikSigPk = fromHex(j['ikSigPk'] as String);
    final spkDhSk = fromHex(j['spkDhSk'] as String);
    final spkDhPk = fromHex(j['spkDhPk'] as String);

    final ikDhKp = SimpleKeyPairData(
      ikDhSk,
      publicKey: SimplePublicKey(ikDhPk, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final ikSigKp = SimpleKeyPairData(
      ikSigSk,
      publicKey: SimplePublicKey(ikSigPk, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
    final spkDhKp = SimpleKeyPairData(
      spkDhSk,
      publicKey: SimplePublicKey(spkDhPk, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    return Identity(
      name: name,
      ikDhKp: ikDhKp,
      ikDhPk: ikDhPk,
      ikSigKp: ikSigKp,
      ikSigPk: ikSigPk,
      spkDhKp: spkDhKp,
      spkDhPk: spkDhPk,
      spkKemSk: fromHex(j['spkKemSk'] as String),
      spkKemPk: fromHex(j['spkKemPk'] as String),
      spkSignature: fromHex(j['spkSig'] as String),
    );
  }
}

/// Peer's public bundle (loaded from peer's published record).
class PeerBundle {
  final String name;
  final Uint8List ikDhPk;
  final Uint8List ikSigPk;
  final Uint8List spkDhPk;
  final Uint8List spkKemPk;
  final Uint8List spkSig;

  PeerBundle({
    required this.name,
    required this.ikDhPk,
    required this.ikSigPk,
    required this.spkDhPk,
    required this.spkKemPk,
    required this.spkSig,
  });

  factory PeerBundle.fromJson(Map<String, dynamic> j) => PeerBundle(
        name: j['name'] as String,
        ikDhPk: fromHex(j['ikDhPk'] as String),
        ikSigPk: fromHex(j['ikSigPk'] as String),
        spkDhPk: fromHex(j['spkDhPk'] as String),
        spkKemPk: fromHex(j['spkKemPk'] as String),
        spkSig: fromHex(j['spkSig'] as String),
      );

  /// Verify the SPK signature with the peer's identity signing key.
  Future<bool> verifySignature() async {
    return await Ed25519().verify(
      spkDhPk,
      signature: Signature(
        spkSig,
        publicKey: SimplePublicKey(ikSigPk, type: KeyPairType.ed25519),
      ),
    );
  }
}

/// Per-peer ratchet state. Persisted in the keystore.
class RatchetState {
  Uint8List rootKey;
  Uint8List? sendCK;
  Uint8List? recvCK;
  SimpleKeyPairData dhKp;
  Uint8List dhPk;
  Uint8List? remoteDhPk;
  Uint8List kemSk;
  Uint8List kemPk;
  Uint8List? remoteKemPk;
  int sendN = 0;
  int recvN = 0;
  int msgsSinceKem = 0;

  // Initiator-only: queued init payload for the first send.
  Uint8List? pendingInitEphPk;
  Uint8List? pendingInitIkPk;
  Uint8List? pendingInitKemCt;
  bool initMessageSent = false;

  RatchetState({
    required this.rootKey,
    required this.dhKp,
    required this.dhPk,
    required this.kemSk,
    required this.kemPk,
    this.sendCK,
    this.recvCK,
    this.remoteDhPk,
    this.remoteKemPk,
    this.pendingInitEphPk,
    this.pendingInitIkPk,
    this.pendingInitKemCt,
    this.initMessageSent = false,
  });

  Future<Map<String, dynamic>> toJson() async {
    final dhSk = await dhKp.extractPrivateKeyBytes();
    final m = <String, dynamic>{
      'rootKey': toHex(rootKey),
      'sendCK': sendCK == null ? null : toHex(sendCK!),
      'recvCK': recvCK == null ? null : toHex(recvCK!),
      'dhSk': toHex(dhSk),
      'dhPk': toHex(dhPk),
      'remoteDhPk': remoteDhPk == null ? null : toHex(remoteDhPk!),
      'kemSk': toHex(kemSk),
      'kemPk': toHex(kemPk),
      'remoteKemPk': remoteKemPk == null ? null : toHex(remoteKemPk!),
      'sendN': sendN,
      'recvN': recvN,
      'msgsSinceKem': msgsSinceKem,
      'initMessageSent': initMessageSent,
    };
    if (pendingInitEphPk != null) m['pendingInitEphPk'] = toHex(pendingInitEphPk!);
    if (pendingInitIkPk != null) m['pendingInitIkPk'] = toHex(pendingInitIkPk!);
    if (pendingInitKemCt != null) m['pendingInitKemCt'] = toHex(pendingInitKemCt!);
    return m;
  }

  static RatchetState fromJson(Map<String, dynamic> j) {
    Uint8List? opt(String k) {
      final v = j[k] as String?;
      return v == null ? null : fromHex(v);
    }

    final dhSk = fromHex(j['dhSk'] as String);
    final dhPk = fromHex(j['dhPk'] as String);
    final dhKp = SimpleKeyPairData(
      dhSk,
      publicKey: SimplePublicKey(dhPk, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    return RatchetState(
      rootKey: fromHex(j['rootKey'] as String),
      sendCK: opt('sendCK'),
      recvCK: opt('recvCK'),
      dhKp: dhKp,
      dhPk: dhPk,
      remoteDhPk: opt('remoteDhPk'),
      kemSk: fromHex(j['kemSk'] as String),
      kemPk: fromHex(j['kemPk'] as String),
      remoteKemPk: opt('remoteKemPk'),
      pendingInitEphPk: opt('pendingInitEphPk'),
      pendingInitIkPk: opt('pendingInitIkPk'),
      pendingInitKemCt: opt('pendingInitKemCt'),
      initMessageSent: j['initMessageSent'] as bool? ?? false,
    )
      ..sendN = j['sendN'] as int? ?? 0
      ..recvN = j['recvN'] as int? ?? 0
      ..msgsSinceKem = j['msgsSinceKem'] as int? ?? 0;
  }
}

// ─── Identity generation ─────────────────────────────────────────────────────

Future<Identity> genIdentity(String name) async {
  final x25519 = X25519();
  final ed25519 = Ed25519();

  final ikDh = await (await x25519.newKeyPair()).extract();
  final ikSig = await (await ed25519.newKeyPair()).extract();
  final spkDh = await (await x25519.newKeyPair()).extract();
  final (spkKemPk, spkKemSk) = mlKemGenerateKeyPair();

  final sig = await ed25519.sign(
    Uint8List.fromList(spkDh.publicKey.bytes),
    keyPair: ikSig,
  );

  return Identity(
    name: name,
    ikDhKp: ikDh,
    ikDhPk: Uint8List.fromList(ikDh.publicKey.bytes),
    ikSigKp: ikSig,
    ikSigPk: Uint8List.fromList(ikSig.publicKey.bytes),
    spkDhKp: spkDh,
    spkDhPk: Uint8List.fromList(spkDh.publicKey.bytes),
    spkKemSk: spkKemSk,
    spkKemPk: spkKemPk,
    spkSignature: Uint8List.fromList(sig.bytes),
  );
}

// ─── PQXDH ───────────────────────────────────────────────────────────────────

Future<RatchetState> pqxdhInitiate(Identity initiator, PeerBundle peer) async {
  final eph = await (await X25519().newKeyPair()).extract();
  final ephPk = Uint8List.fromList(eph.publicKey.bytes);

  final dh1 = await x25519Dh(initiator.ikDhKp, peer.spkDhPk);
  final dh2 = await x25519Dh(initiator.ikDhKp, peer.ikDhPk);
  final dh3 = await x25519Dh(eph, peer.spkDhPk);
  final (initKemCt, kemSs) = mlKemEncaps(peer.spkKemPk);

  final ikm = Uint8List.fromList([...dh1, ...dh2, ...dh3, ...kemSs]);
  var rootKey = await hkdfInit(ikm);

  final ratchet = await (await X25519().newKeyPair()).extract();
  final ratchetPk = Uint8List.fromList(ratchet.publicKey.bytes);
  final dhOut = await x25519Dh(ratchet, peer.spkDhPk);
  final mixed = await hkdfRkStep(rootKey, dhOut);
  rootKey = mixed.sublist(0, 32);
  final sendCK = mixed.sublist(32, 64);

  final (kemPk, kemSk) = mlKemGenerateKeyPair();

  return RatchetState(
    rootKey: rootKey,
    sendCK: sendCK,
    dhKp: ratchet,
    dhPk: ratchetPk,
    remoteDhPk: peer.spkDhPk,
    kemSk: kemSk,
    kemPk: kemPk,
    remoteKemPk: peer.spkKemPk,
    pendingInitEphPk: ephPk,
    pendingInitIkPk: initiator.ikDhPk,
    pendingInitKemCt: initKemCt,
  );
}

Future<RatchetState> pqxdhRespond(Identity responder, WireMessage firstMsg) async {
  final dh1 = await x25519Dh(responder.spkDhKp, firstMsg.initIkPk!);
  final dh2 = await x25519Dh(responder.ikDhKp, firstMsg.initIkPk!);
  final dh3 = await x25519Dh(responder.spkDhKp, firstMsg.initEphPk!);
  final kemSs = mlKemDecaps(responder.spkKemSk, firstMsg.initKemCt!);

  final ikm = Uint8List.fromList([...dh1, ...dh2, ...dh3, ...kemSs]);
  var rootKey = await hkdfInit(ikm);

  final dhOut1 = await x25519Dh(responder.spkDhKp, firstMsg.dhPk);
  final mixed1 = await hkdfRkStep(rootKey, dhOut1);
  rootKey = mixed1.sublist(0, 32);
  final recvCK = mixed1.sublist(32, 64);

  final myKp = await (await X25519().newKeyPair()).extract();
  final myPk = Uint8List.fromList(myKp.publicKey.bytes);
  final dhOut2 = await x25519Dh(myKp, firstMsg.dhPk);
  final mixed2 = await hkdfRkStep(rootKey, dhOut2);
  rootKey = mixed2.sublist(0, 32);
  final sendCK = mixed2.sublist(32, 64);

  return RatchetState(
    rootKey: rootKey,
    sendCK: sendCK,
    recvCK: recvCK,
    dhKp: myKp,
    dhPk: myPk,
    remoteDhPk: firstMsg.dhPk,
    kemSk: responder.spkKemSk,
    kemPk: responder.spkKemPk,
    remoteKemPk: firstMsg.kemPk,
  );
}

// ─── Send / receive ──────────────────────────────────────────────────────────

/// Returns the wire message AND a status code for the chat layer to log:
///   "kem"   → KEM ratchet step fired
///   "init"  → first send carrying PQXDH init payload
///   "msg"   → ordinary message
class SendResult {
  final WireMessage msg;
  final String status;
  SendResult(this.msg, this.status);
}

Future<SendResult> sendMessage(RatchetState s, String plaintext) async {
  Uint8List? outKemCt;
  Uint8List? outKemPk;
  var statusKem = false;

  if (s.sendN > 0 && s.sendN % kemRatchetEvery == 0 && s.remoteKemPk != null) {
    final (kemCt, kemSs) = mlKemEncaps(s.remoteKemPk!);
    outKemCt = kemCt;
    final mixed = await hkdfRkStep(s.rootKey, kemSs);
    s.rootKey = mixed.sublist(0, 32);
    final (newPk, newSk) = mlKemGenerateKeyPair();
    s.kemSk = newSk;
    s.kemPk = newPk;
    outKemPk = s.kemPk;
    s.msgsSinceKem = 0;
    statusKem = true;
  }

  final isInit = !s.initMessageSent && s.pendingInitEphPk != null;

  final (msgKey, newSendCK) = await chainStep(s.sendCK!);
  s.sendCK = newSendCK;

  final pt = Uint8List.fromList(plaintext.codeUnits);
  final (nonce, ct, mac) = await aesSeal(msgKey, pt);

  final msg = WireMessage(
    dhPk: s.dhPk,
    kemPk: isInit ? s.kemPk : outKemPk,
    kemCt: outKemCt,
    nonce: nonce,
    ct: ct,
    mac: mac,
    msgN: s.sendN,
    isInit: isInit,
    initEphPk: isInit ? s.pendingInitEphPk : null,
    initIkPk: isInit ? s.pendingInitIkPk : null,
    initKemCt: isInit ? s.pendingInitKemCt : null,
  );

  s.sendN++;
  s.msgsSinceKem++;
  if (isInit) {
    s.initMessageSent = true;
    s.pendingInitEphPk = null;
    s.pendingInitIkPk = null;
    s.pendingInitKemCt = null;
  }

  final status =
      isInit ? 'init' : (statusKem ? 'kem' : 'msg');
  return SendResult(msg, status);
}

class ReceiveResult {
  final String plaintext;
  final String status;
  ReceiveResult(this.plaintext, this.status);
}

Future<ReceiveResult> receiveMessage(RatchetState s, WireMessage msg) async {
  var triggeredDh = false;
  var triggeredKem = false;

  if (!bytesEq(msg.dhPk, s.remoteDhPk)) {
    triggeredDh = true;
    final dhOut1 = await x25519Dh(s.dhKp, msg.dhPk);
    final mixed1 = await hkdfRkStep(s.rootKey, dhOut1);
    s.rootKey = mixed1.sublist(0, 32);
    s.recvCK = mixed1.sublist(32, 64);

    final newKp = await (await X25519().newKeyPair()).extract();
    s.dhKp = newKp;
    s.dhPk = Uint8List.fromList(newKp.publicKey.bytes);
    final dhOut2 = await x25519Dh(s.dhKp, msg.dhPk);
    final mixed2 = await hkdfRkStep(s.rootKey, dhOut2);
    s.rootKey = mixed2.sublist(0, 32);
    s.sendCK = mixed2.sublist(32, 64);

    s.remoteDhPk = msg.dhPk;
    s.sendN = 0;
    s.recvN = 0;
  }

  if (msg.kemCt != null) {
    triggeredKem = true;
    final kemSs = mlKemDecaps(s.kemSk, msg.kemCt!);
    final mixed = await hkdfRkStep(s.rootKey, kemSs);
    s.rootKey = mixed.sublist(0, 32);
    if (msg.kemPk != null) {
      s.remoteKemPk = msg.kemPk;
    }
    final (newPk, newSk) = mlKemGenerateKeyPair();
    s.kemSk = newSk;
    s.kemPk = newPk;
  }

  if (msg.kemPk != null && msg.kemCt == null) {
    s.remoteKemPk = msg.kemPk;
  }

  final (msgKey, newRecvCK) = await chainStep(s.recvCK!);
  s.recvCK = newRecvCK;

  final pt = await aesOpen(msgKey, msg.nonce, msg.ct, msg.mac);
  s.recvN++;

  final status = triggeredDh && triggeredKem
      ? 'dh+kem'
      : triggeredDh
          ? 'dh'
          : triggeredKem
              ? 'kem'
              : 'msg';
  return ReceiveResult(String.fromCharCodes(pt), status);
}
