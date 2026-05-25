// =============================================================================
// pq_chat — single-file Triple Ratchet narrative demo
// =============================================================================
// Run:        dart run bin/demo.dart
//
// What this is: two parties (alice = initiator, bob = responder) live in the
// same process. Alice runs a PQXDH-style hybrid handshake against Bob's
// published pre-key bundle, then they exchange a scripted sequence of messages
// while every key, every ratchet step, every state transition is printed.
//
// Read order: top to bottom. Crypto primitives → ratchet operations →
// scripted scenario in main().
//
// Out of scope (deliberately omitted for clarity):
//   - persistence       (state lives only in `main`'s locals)
//   - out-of-order delivery / skipped-message-key cache
//   - the file-based "wire" transport from earlier iterations
//   - a separate Layer-1 hybrid demo (covered by docs/ARCHITECTURE.md)
// =============================================================================

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

// In production this is 10 or higher. Lowered so the KEM ratchet fires
// within a short scripted run.
const int kemRatchetEvery = 3;

// ─── ANSI + hex truncator ────────────────────────────────────────────────────

String _ansi(String s, int code) => '\x1B[${code}m$s\x1B[0m';
String _dim(String s)     => _ansi(s, 90);
String _bold(String s)    => _ansi(s, 1);
String _yellow(String s)  => _ansi(s, 33);
String _green(String s)   => _ansi(s, 32);
String _cyan(String s)    => _ansi(s, 36);
String _magenta(String s) => _ansi(s, 35);

String hx(List<int> bytes, {int show = 12}) {
  if (bytes.isEmpty) return '<empty>';
  final n = bytes.length < show ? bytes.length : show;
  final h = bytes
      .sublist(0, n)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join('');
  return bytes.length > show ? '$h… (${bytes.length}B)' : '$h (${bytes.length}B)';
}

bool _bytesEq(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void hr(String title) {
  final bar = '═' * 72;
  print('');
  print(_bold(bar));
  print(_bold('  $title'));
  print(_bold(bar));
}

// ─── Data types ──────────────────────────────────────────────────────────────

/// Long-lived identity + medium-lived signed pre-key bundle for one party.
class Identity {
  final String name;
  // X25519 identity DH (long-lived)
  final SimpleKeyPairData ikDhKp;
  final Uint8List ikDhPk;
  // Ed25519 identity signing (long-lived)
  final SimpleKeyPairData ikSigKp;
  final Uint8List ikSigPk;
  // X25519 signed pre-key (medium-lived)
  final SimpleKeyPairData spkDhKp;
  final Uint8List spkDhPk;
  // ML-KEM-768 signed pre-key (medium-lived)
  final Uint8List spkKemSk;
  final Uint8List spkKemPk;
  // Ed25519 signature over spkDhPk
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
}

/// Mutable per-peer ratchet state. Lives entirely in process memory in this demo.
class RatchetState {
  Uint8List rootKey;
  Uint8List? sendCK;
  Uint8List? recvCK;
  // Current DH ratchet keypair (X25519). Rotates on DH ratchet step.
  SimpleKeyPairData dhKp;
  Uint8List dhPk;
  Uint8List? remoteDhPk;
  // Current KEM ratchet keypair (ML-KEM-768). Rotates every kemRatchetEvery sends.
  Uint8List kemSk;
  Uint8List kemPk;
  Uint8List? remoteKemPk;
  // Counters
  int sendN = 0;
  int recvN = 0;
  int msgsSinceKem = 0;

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
  });
}

/// Wire-format message envelope.
class WireMessage {
  final Uint8List dhPk;     // sender's current DH ratchet pk
  final Uint8List? kemPk;   // sender's current KEM ratchet pk (when it just rotated)
  final Uint8List? kemCt;   // present only on KEM ratchet step
  final Uint8List nonce;
  final Uint8List ct;
  final Uint8List mac;
  final int msgN;
  final bool isInit;
  final Uint8List? initEphPk;
  final Uint8List? initIkPk;
  final Uint8List? initKemCt;

  WireMessage({
    required this.dhPk,
    required this.nonce,
    required this.ct,
    required this.mac,
    required this.msgN,
    this.kemPk,
    this.kemCt,
    this.isInit = false,
    this.initEphPk,
    this.initIkPk,
    this.initKemCt,
  });

  int get sizeBytes =>
      dhPk.length +
      (kemPk?.length ?? 0) +
      (kemCt?.length ?? 0) +
      nonce.length +
      ct.length +
      mac.length +
      4 + 1 + // msgN + isInit
      (initEphPk?.length ?? 0) +
      (initIkPk?.length ?? 0) +
      (initKemCt?.length ?? 0);
}

// ─── Crypto primitives (thin wrappers around the package APIs) ───────────────

/// HKDF-SHA256 in "ratchet" mode: salt = rootKey, info = "pq-chat-ratchet".
/// Returns 64B = newRootKey ‖ chainKey.
Future<Uint8List> hkdfRkStep(Uint8List rootKey, Uint8List ikm) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: rootKey,
    info: 'pq-chat-ratchet'.codeUnits,
  );
  return Uint8List.fromList(await derived.extractBytes());
}

/// HKDF-SHA256 used once at PQXDH init: salt = empty, info = "pq-chat-init".
/// Returns 32B = initial rootKey.
Future<Uint8List> hkdfInit(Uint8List ikm) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: const <int>[],
    info: 'pq-chat-init'.codeUnits,
  );
  return Uint8List.fromList(await derived.extractBytes());
}

/// Symmetric chain step. Two independent HMACs of the chain key produce
/// (msg_key, next_chain_key).
Future<(Uint8List, Uint8List)> chainStep(Uint8List ck) async {
  final hmac = Hmac.sha256();
  final mk = await hmac.calculateMac([0x01], secretKey: SecretKey(ck));
  final nck = await hmac.calculateMac([0x02], secretKey: SecretKey(ck));
  return (Uint8List.fromList(mk.bytes), Uint8List.fromList(nck.bytes));
}

Future<Uint8List> x25519Dh(SimpleKeyPairData mySkKp, Uint8List peerPk) async {
  final ss = await X25519().sharedSecretKey(
    keyPair: mySkKp,
    remotePublicKey: SimplePublicKey(peerPk, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await ss.extractBytes());
}

Future<(Uint8List, Uint8List, Uint8List)> aesSeal(
    Uint8List key, Uint8List plaintext) async {
  final gcm = AesGcm.with256bits();
  final nonce = Uint8List.fromList(gcm.newNonce());
  final box = await gcm.encrypt(plaintext,
      secretKey: SecretKey(key), nonce: nonce);
  return (nonce, Uint8List.fromList(box.cipherText),
      Uint8List.fromList(box.mac.bytes));
}

Future<Uint8List> aesOpen(
    Uint8List key, Uint8List nonce, Uint8List ct, Uint8List mac) async {
  final pt = await AesGcm.with256bits().decrypt(
    SecretBox(ct, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
  );
  return Uint8List.fromList(pt);
}

// ─── Identity generation ─────────────────────────────────────────────────────
// Generated necessary keys for an actor
Future<Identity> genIdentity(String name) async {
  final x25519 = X25519();
  final ed25519 = Ed25519();
  final kem = PqcKem.kyber768;

  final ikDh = await (await x25519.newKeyPair()).extract();
  final ikSig = await (await ed25519.newKeyPair()).extract();
  final spkDh = await (await x25519.newKeyPair()).extract();
  final (spkKemPk, spkKemSk) = kem.generateKeyPair();

  // Identity Ed25519 signs the X25519 SPK — proves the SPK binding.
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
    spkKemSk: Uint8List.fromList(spkKemSk),
    spkKemPk: Uint8List.fromList(spkKemPk),
    spkSignature: Uint8List.fromList(sig.bytes),
  );
}

// ─── PQXDH handshake ─────────────────────────────────────────────────────────

class PqxdhInitExtras {
  final Uint8List ephPk;
  final Uint8List initKemCt;
  final Uint8List initiatorIkDhPk;
  PqxdhInitExtras(this.ephPk, this.initKemCt, this.initiatorIkDhPk);
}

Future<(RatchetState, PqxdhInitExtras)> pqxdhInitiate(
    Identity initiator, Identity responderPublic) async {
  print(_cyan('  ┌── PQXDH INIT ${"─" * 55}'));

  // 1. Fresh X25519 ephemeral.
  final eph = await (await X25519().newKeyPair()).extract();
  final ephPk = Uint8List.fromList(eph.publicKey.bytes);
  print('  │ eph_pk             : ${hx(ephPk)}');

  // 2-4. Three Diffie-Hellmans, each binds a different pair.
  final dh1 = await x25519Dh(initiator.ikDhKp, responderPublic.spkDhPk);
  final dh2 = await x25519Dh(initiator.ikDhKp, responderPublic.ikDhPk);
  final dh3 = await x25519Dh(eph, responderPublic.spkDhPk);
  print('  │ dh1 (ik × spk)     : ${hx(dh1)}');
  print('  │ dh2 (ik × ik)      : ${hx(dh2)}');
  print('  │ dh3 (eph × spk)    : ${hx(dh3)}');

  // 5. ML-KEM encaps to responder's SPK KEM pk.
  final (kemCtRaw, kemSsRaw) =
      PqcKem.kyber768.encapsulate(responderPublic.spkKemPk);
  final initKemCt = Uint8List.fromList(kemCtRaw);
  final kemSs = Uint8List.fromList(kemSsRaw);
  print('  │ initKemCt          : ${hx(initKemCt)}');
  print('  │ kem_ss             : ${hx(kemSs)}');

  // 6. HKDF over dh1‖dh2‖dh3‖kem_ss → initial rootKey.
  final ikm = Uint8List.fromList([...dh1, ...dh2, ...dh3, ...kemSs]);
  var rootKey = await hkdfInit(ikm);
  print('  │ ${_yellow("rootKey₀")}           : ${hx(rootKey)}');

  // 7+8. First DH ratchet step against responder's SPK.
  final ratchet = await (await X25519().newKeyPair()).extract();
  final ratchetPk = Uint8List.fromList(ratchet.publicKey.bytes);
  final dhOut = await x25519Dh(ratchet, responderPublic.spkDhPk);
  final mixed = await hkdfRkStep(rootKey, dhOut);
  rootKey = mixed.sublist(0, 32);
  final sendCK = mixed.sublist(32, 64);
  print('  │ first DH step:');
  print('  │   ratchet_pk       : ${hx(ratchetPk)}');
  print('  │   dhOut            : ${hx(dhOut)}');
  print('  │   ${_yellow("rootKey₁")}         : ${hx(rootKey)}');
  print('  │   sendCK           : ${hx(sendCK)}');

  // 9. Initial KEM ratchet keypair (advertised in first wire message).
  final (kemPkRaw, kemSkRaw) = PqcKem.kyber768.generateKeyPair();
  final kemPk = Uint8List.fromList(kemPkRaw);
  final kemSk = Uint8List.fromList(kemSkRaw);
  print('  │ initial KEM ratchet keypair generated');
  print('  │   kemRatchetPk     : ${hx(kemPk)}');
  print('  └${"─" * 70}');

  final state = RatchetState(
    rootKey: rootKey,
    sendCK: sendCK,
    dhKp: ratchet,
    dhPk: ratchetPk,
    remoteDhPk: responderPublic.spkDhPk,
    kemSk: kemSk,
    kemPk: kemPk,
    remoteKemPk: responderPublic.spkKemPk,
  );
  return (state, PqxdhInitExtras(ephPk, initKemCt, initiator.ikDhPk));
}

Future<RatchetState> pqxdhRespond(Identity responder, WireMessage firstMsg) async {
  print(_cyan('  ┌── PQXDH RESPOND ${"─" * 52}'));

  // Mirror the initiator's math (their sk × my pk ≡ my sk × their pk).
  final dh1 = await x25519Dh(responder.spkDhKp, firstMsg.initIkPk!);
  final dh2 = await x25519Dh(responder.ikDhKp, firstMsg.initIkPk!);
  final dh3 = await x25519Dh(responder.spkDhKp, firstMsg.initEphPk!);
  final kemSs = Uint8List.fromList(
      PqcKem.kyber768.decapsulate(responder.spkKemSk, firstMsg.initKemCt!));
  print('  │ dh1 (spk × ik_in)  : ${hx(dh1)}');
  print('  │ dh2 (ik × ik_in)   : ${hx(dh2)}');
  print('  │ dh3 (spk × eph_in) : ${hx(dh3)}');
  print('  │ kem_ss             : ${hx(kemSs)}');

  final ikm = Uint8List.fromList([...dh1, ...dh2, ...dh3, ...kemSs]);
  var rootKey = await hkdfInit(ikm);
  print('  │ ${_yellow("rootKey₀")}           : ${hx(rootKey)}');

  // Mirror initiator's first DH step → recvCK matches initiator's sendCK.
  final dhOut1 = await x25519Dh(responder.spkDhKp, firstMsg.dhPk);
  final mixed1 = await hkdfRkStep(rootKey, dhOut1);
  rootKey = mixed1.sublist(0, 32);
  final recvCK = mixed1.sublist(32, 64);
  print('  │ first DH mirror:');
  print('  │   dhOut            : ${hx(dhOut1)}');
  print('  │   ${_yellow("rootKey₁")}         : ${hx(rootKey)}');
  print('  │   recvCK           : ${hx(recvCK)} ← matches initiator sendCK');

  // Responder generates a fresh DH ratchet keypair for *their* sends.
  final myKp = await (await X25519().newKeyPair()).extract();
  final myPk = Uint8List.fromList(myKp.publicKey.bytes);
  final dhOut2 = await x25519Dh(myKp, firstMsg.dhPk);
  final mixed2 = await hkdfRkStep(rootKey, dhOut2);
  rootKey = mixed2.sublist(0, 32);
  final sendCK = mixed2.sublist(32, 64);
  print('  │ responder send-side step:');
  print('  │   new ratchet_pk   : ${hx(myPk)}');
  print('  │   dhOut            : ${hx(dhOut2)}');
  print('  │   ${_yellow("rootKey₂")}         : ${hx(rootKey)}');
  print('  │   sendCK           : ${hx(sendCK)}');
  print('  └${"─" * 70}');

  // Responder's KEM ratchet starts at their SPK KEM until the first ratchet step.
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

Future<WireMessage> sendMessage(
  RatchetState s,
  String plaintext, {
  bool isInit = false,
  PqxdhInitExtras? initExtras,
}) async {
  Uint8List? outKemCt;
  Uint8List? outKemPk;

  // 1. KEM ratchet trigger?
  if (s.sendN > 0 && s.sendN % kemRatchetEvery == 0 && s.remoteKemPk != null) {
    print(_magenta(
        '    STEP  KEM RATCHET TRIGGER  (sendN=${s.sendN} % $kemRatchetEvery == 0)'));
    final (kemCtRaw, kemSsRaw) = PqcKem.kyber768.encapsulate(s.remoteKemPk!);
    outKemCt = Uint8List.fromList(kemCtRaw);
    final kemSs = Uint8List.fromList(kemSsRaw);
    print('      Encaps(remoteKemPk) → kemCt   : ${hx(outKemCt)}');
    print('                          → kem_ss  : ${hx(kemSs)}');
    final mixed = await hkdfRkStep(s.rootKey, kemSs);
    s.rootKey = mixed.sublist(0, 32);
    print('      ${_yellow("rootKey")} ← HKDF(rootKey, kem_ss) = ${hx(s.rootKey)}');
    final (newPk, newSk) = PqcKem.kyber768.generateKeyPair();
    s.kemSk = Uint8List.fromList(newSk);
    s.kemPk = Uint8List.fromList(newPk);
    outKemPk = s.kemPk;
    print('      new local KEM keypair; kemPk advertised : ${hx(outKemPk)}');
    s.msgsSinceKem = 0;
  }

  // 2. Symmetric chain step.
  print(_dim('    STEP  symmetric chain step'));
  final (msgKey, newSendCK) = await chainStep(s.sendCK!);
  print('      HMAC(sendCK, 0x01) → msg_key  : ${hx(msgKey)}');
  print('      HMAC(sendCK, 0x02) → new sendCK : ${hx(newSendCK)}');
  s.sendCK = newSendCK;

  // 3. AES-256-GCM seal.
  print(_dim('    STEP  AES-256-GCM seal'));
  final pt = Uint8List.fromList(plaintext.codeUnits);
  final (nonce, ct, mac) = await aesSeal(msgKey, pt);
  print('      plaintext : "$plaintext"');
  print('      nonce     : ${hx(nonce)}');
  print('      ct        : ${hx(ct)}');
  print('      mac       : ${hx(mac)}');

  final msg = WireMessage(
    dhPk: s.dhPk,
    kemPk: isInit ? s.kemPk : outKemPk,
    kemCt: outKemCt,
    nonce: nonce,
    ct: ct,
    mac: mac,
    msgN: s.sendN,
    isInit: isInit,
    initEphPk: initExtras?.ephPk,
    initIkPk: initExtras?.initiatorIkDhPk,
    initKemCt: initExtras?.initKemCt,
  );
  s.sendN++;
  s.msgsSinceKem++;
  return msg;
}

Future<String> receiveMessage(RatchetState s, WireMessage msg) async {
  // 1. DH ratchet trigger?
  if (!_bytesEq(msg.dhPk, s.remoteDhPk)) {
    print(_magenta('    STEP  DH RATCHET TRIGGER  (peer dhPk changed)'));
    final dhOut1 = await x25519Dh(s.dhKp, msg.dhPk);
    final mixed1 = await hkdfRkStep(s.rootKey, dhOut1);
    s.rootKey = mixed1.sublist(0, 32);
    s.recvCK = mixed1.sublist(32, 64);
    print('      recv-side: dhOut = our_sk × msg.dhPk = ${hx(dhOut1)}');
    print('        ${_yellow("rootKey")} ← HKDF(...) = ${hx(s.rootKey)}');
    print('        recvCK  = ${hx(s.recvCK!)}');
    final newKp = await (await X25519().newKeyPair()).extract();
    s.dhKp = newKp;
    s.dhPk = Uint8List.fromList(newKp.publicKey.bytes);
    final dhOut2 = await x25519Dh(s.dhKp, msg.dhPk);
    final mixed2 = await hkdfRkStep(s.rootKey, dhOut2);
    s.rootKey = mixed2.sublist(0, 32);
    s.sendCK = mixed2.sublist(32, 64);
    print('      send-side: new ratchet_pk = ${hx(s.dhPk)}');
    print('        ${_yellow("rootKey")} ← HKDF(...) = ${hx(s.rootKey)}');
    print('        sendCK  = ${hx(s.sendCK!)}');
    s.remoteDhPk = msg.dhPk;
    s.sendN = 0;
    s.recvN = 0;
  }

  // 2. KEM ratchet receive?
  if (msg.kemCt != null) {
    print(_magenta('    STEP  KEM RATCHET RECEIVE  (msg carries kemCt)'));
    final kemSs = Uint8List.fromList(
        PqcKem.kyber768.decapsulate(s.kemSk, msg.kemCt!));
    print('      Decaps(our_kemSk, msg.kemCt) → kem_ss : ${hx(kemSs)}');
    final mixed = await hkdfRkStep(s.rootKey, kemSs);
    s.rootKey = mixed.sublist(0, 32);
    print('      ${_yellow("rootKey")} ← HKDF(rootKey, kem_ss) = ${hx(s.rootKey)}');
    if (msg.kemPk != null) {
      s.remoteKemPk = msg.kemPk;
      print('      remoteKemPk = ${hx(s.remoteKemPk!)}');
    }
    final (newPk, newSk) = PqcKem.kyber768.generateKeyPair();
    s.kemSk = Uint8List.fromList(newSk);
    s.kemPk = Uint8List.fromList(newPk);
    print('      new local KEM keypair; kemPk = ${hx(s.kemPk)}');
  }

  // 3. KEM PK advertisement only (first message after init).
  if (msg.kemPk != null && msg.kemCt == null) {
    s.remoteKemPk = msg.kemPk;
    print(_dim('    STEP  remoteKemPk advertised: ${hx(msg.kemPk!)}'));
  }

  // 4. Symmetric chain step on recv chain.
  print(_dim('    STEP  symmetric chain step'));
  final (msgKey, newRecvCK) = await chainStep(s.recvCK!);
  print('      HMAC(recvCK, 0x01) → msg_key  : ${hx(msgKey)}');
  print('      HMAC(recvCK, 0x02) → new recvCK : ${hx(newRecvCK)}');
  s.recvCK = newRecvCK;

  // 5. AES open.
  print(_dim('    STEP  AES-256-GCM open'));
  final pt = await aesOpen(msgKey, msg.nonce, msg.ct, msg.mac);
  s.recvN++;
  return String.fromCharCodes(pt);
}

// ─── State snapshot / diff ───────────────────────────────────────────────────

Map<String, String> snapshot(RatchetState s) => {
      'rootKey':    hx(s.rootKey),
      'sendCK':     s.sendCK == null ? '<null>' : hx(s.sendCK!),
      'recvCK':     s.recvCK == null ? '<null>' : hx(s.recvCK!),
      'dhPk':       hx(s.dhPk),
      'remoteDhPk': s.remoteDhPk == null ? '<null>' : hx(s.remoteDhPk!),
      'kemPk':      hx(s.kemPk),
      'remoteKemPk':s.remoteKemPk == null ? '<null>' : hx(s.remoteKemPk!),
      'sendN':      '${s.sendN}',
      'recvN':      '${s.recvN}',
      'msgsSince':  '${s.msgsSinceKem}',
    };

void printSnapshot(String label, Map<String, String> snap,
    [Map<String, String>? prev]) {
  print(_bold('  $label'));
  snap.forEach((k, v) {
    final changed = prev != null && prev[k] != v;
    final marker = changed ? _green('*') : ' ';
    final line = '$marker ${k.padRight(11)}: $v';
    print('    ' + (changed ? _green(line) : line));
  });
}

void printWire(WireMessage m) {
  print(_dim('    WIRE  envelope size = ${m.sizeBytes}B  '
      '[dhPk=${m.dhPk.length} '
      'kemPk=${m.kemPk?.length ?? 0} '
      'kemCt=${m.kemCt?.length ?? 0} '
      'isInit=${m.isInit}]'));
}

// ─── main ────────────────────────────────────────────────────────────────────

Future<void> main() async {
  // ── 1. SETUP ───────────────────────────────────────────────────────────────
  hr('SETUP — generate alice (initiator) and bob (responder)');
  final alice = await genIdentity('alice');
  final bob = await genIdentity('bob');
  print('  alice.ik_pk      : ${hx(alice.ikDhPk)}');
  print('  alice.ikSig_pk   : ${hx(alice.ikSigPk)}');
  print('  alice.spk_pk     : ${hx(alice.spkDhPk)}');
  print('  alice.spkKemPk   : ${hx(alice.spkKemPk)}');
  print('  bob.ik_pk        : ${hx(bob.ikDhPk)}');
  print('  bob.ikSig_pk     : ${hx(bob.ikSigPk)}');
  print('  bob.spk_pk       : ${hx(bob.spkDhPk)}');
  print('  bob.spkKemPk     : ${hx(bob.spkKemPk)}');

  // ── 2. SPK signature check (initiator-side bundle verification) ───────────
  hr('Alice verifies Bob\'s SPK signature');
  final sigOk = await Ed25519().verify(
    bob.spkDhPk,
    signature: Signature(
      bob.spkSignature,
      publicKey: SimplePublicKey(bob.ikSigPk, type: KeyPairType.ed25519),
    ),
  );
  print('  Ed25519.verify(bob.ikSig_pk, bob.spk_pk, sig)  →  '
      '${sigOk ? _green("VALID") : "INVALID"}');

  // ── 3. PQXDH handshake (initiator side) ───────────────────────────────────
  hr('PQXDH HANDSHAKE  (alice as initiator)');
  final (aliceS, initExtras) = await pqxdhInitiate(alice, bob);

  Map<String, String> before, after;

  // ── 4. ALICE → BOB  msg #0 (carries PQXDH init payload) ───────────────────
  hr('ALICE → BOB  msg #0  (with PQXDH init payload)');
  before = snapshot(aliceS);
  printSnapshot('BEFORE', before);
  final m0 = await sendMessage(aliceS, 'Hi Bob!',
      isInit: true, initExtras: initExtras);
  printWire(m0);
  after = snapshot(aliceS);
  printSnapshot('AFTER', after, before);

  // ── 5. BOB ← ALICE  msg #0  (PQXDH respond + receive) ─────────────────────
  hr('BOB ← ALICE  msg #0  (PQXDH respond + decrypt)');
  final bobS = await pqxdhRespond(bob, m0);
  before = snapshot(bobS);
  printSnapshot('BEFORE', before);
  final pt0 = await receiveMessage(bobS, m0);
  print(_dim('    plaintext recovered: "$pt0"'));
  after = snapshot(bobS);
  printSnapshot('AFTER', after, before);

  // ── 6. BOB → ALICE  msg #0  (bob's first send — DH RATCHET on alice's recv)
  // The round-trip MUST happen before any KEM ratchet attempt. Otherwise alice
  // and bob have unequal rootKeys (alice stopped at rootKey₁ during init; bob
  // ran an extra DH step to rootKey₂). A KEM ratchet would mutate both, but
  // from different starting points, causing chain-key desync.
  hr('BOB → ALICE  msg #0  (bob\'s first send to alice)');
  before = snapshot(bobS);
  printSnapshot('BEFORE', before);
  final b0 = await sendMessage(bobS, 'Hi Alice!');
  printWire(b0);
  after = snapshot(bobS);
  printSnapshot('AFTER', after, before);

  hr('ALICE ← BOB  msg #0  (expect DH RATCHET trigger on alice)');
  before = snapshot(aliceS);
  printSnapshot('BEFORE', before);
  final apt = await receiveMessage(aliceS, b0);
  print(_dim('    plaintext recovered: "$apt"'));
  after = snapshot(aliceS);
  printSnapshot('AFTER', after, before);

  // ── 7. ALICE → BOB  msg #0 (new chain — DH RATCHET on bob's recv) ────────
  // Alice's DH ratchet generated a new dhPk; bob will see it as new and ratchet.
  hr('ALICE → BOB  msg #0  (new chain, sendN reset by alice\'s DH ratchet)');
  before = snapshot(aliceS);
  printSnapshot('BEFORE', before);
  final mAfterDh = await sendMessage(aliceS, 'Got your msg, Bob!');
  printWire(mAfterDh);
  after = snapshot(aliceS);
  printSnapshot('AFTER', after, before);

  hr('BOB ← ALICE  msg #0  (expect DH RATCHET trigger on bob)');
  before = snapshot(bobS);
  printSnapshot('BEFORE', before);
  final ptAfterDh = await receiveMessage(bobS, mAfterDh);
  print(_dim('    plaintext recovered: "$ptAfterDh"'));
  after = snapshot(bobS);
  printSnapshot('AFTER', after, before);

  // After two DH ratchets, alice.rootKey == bob.rootKey. Now safe to KEM ratchet.

  // ── 8. ALICE → BOB msgs #1, #2  (chain rotation only) ─────────────────────
  for (var i = 1; i <= 2; i++) {
    hr('ALICE → BOB  msg #$i  (symmetric chain only)');
    before = snapshot(aliceS);
    printSnapshot('BEFORE', before);
    final m = await sendMessage(aliceS, 'Alice msg #$i');
    printWire(m);
    after = snapshot(aliceS);
    printSnapshot('AFTER', after, before);

    hr('BOB ← ALICE  msg #$i');
    before = snapshot(bobS);
    printSnapshot('BEFORE', before);
    final pt = await receiveMessage(bobS, m);
    print(_dim('    plaintext recovered: "$pt"'));
    after = snapshot(bobS);
    printSnapshot('AFTER', after, before);
  }

  // ── 9. ALICE → BOB  msg #3  (KEM RATCHET fires; alice's sendN=3) ──────────
  hr('ALICE → BOB  msg #3  (expect KEM RATCHET trigger)');
  before = snapshot(aliceS);
  printSnapshot('BEFORE', before);
  final m3 = await sendMessage(aliceS, 'Alice msg #3 — kem ratchet step');
  printWire(m3);
  after = snapshot(aliceS);
  printSnapshot('AFTER', after, before);

  hr('BOB ← ALICE  msg #3  (expect KEM RATCHET RECEIVE)');
  before = snapshot(bobS);
  printSnapshot('BEFORE', before);
  final pt3 = await receiveMessage(bobS, m3);
  print(_dim('    plaintext recovered: "$pt3"'));
  after = snapshot(bobS);
  printSnapshot('AFTER', after, before);

  // ── 10. Summary ───────────────────────────────────────────────────────────
  hr('DEMO COMPLETE');
  print('  ${_green("✓")} PQXDH handshake (3 DH + 1 ML-KEM Encaps → rootKey)');
  print('  ${_green("✓")} symmetric chain step on every send and receive');
  print('  ${_green("✓")} DH ratchet fired on alice\'s receive of bob\'s first send');
  print('  ${_green("✓")} DH ratchet fired on bob\'s receive of alice\'s reply');
  print('  ${_green("✓")} KEM ratchet fired on alice\'s sendN=$kemRatchetEvery (after state sync)');
  print('');
  print('  Re-run the demo to see different randomness — the structure is invariant.');
}
