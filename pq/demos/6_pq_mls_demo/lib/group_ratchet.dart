// MLS-shaped group ratchet — one group per name (alice's group, bob's group).
//
// Properties kept:
//   - Single per-epoch group_secret shared by all current members
//   - FS across epochs (old secret discarded on Commit)
//   - PCS per Commit (new secret = fresh randomness, HPKE-sealed to each member)
//   - External-sender mode: a single externalHpkePk per epoch lets non-members
//     encrypt to the group without enumerating members
//
// Properties dropped vs full MLS RFC 9420:
//   - No TreeKEM (flat per-member HPKE wraps; O(N) per Commit instead of O(log N))
//   - No PSK / external commits / group resumption

import 'dart:convert';
import 'dart:typed_data';

import 'keystore.dart';
import 'openssl.dart';
import 'wire.dart';

class GroupRatchet {
  final Crypto c;
  final Identity self;

  GroupRatchet(this.c, this.self);

  // ── Bootstrap (solo group for this name) ──────────────────────────────────

  OwnGroupState bootstrap(String groupId) {
    final groupSecret = c.rand.bytes(32);
    final (extPk, extSk) = c.xwing.keygen();
    return OwnGroupState(
      groupId: groupId,
      epoch: 0,
      groupSecret: groupSecret,
      externalHpkeSk: extSk,
      externalHpkePk: extPk,
      members: [self.toMemberDesc()],
    );
  }

  // ── Commit: Add / Remove / Update ─────────────────────────────────────────

  /// Build a Commit (+ Welcomes for new joiners) that produces a new epoch.
  /// `additions` may be empty (pure Update or Remove); `removals` likewise.
  /// Returns (Commit, list of Welcomes), and a mutated newOwnState the caller
  /// applies after broadcasting.
  ({Commit commit, List<Welcome> welcomes, OwnGroupState newState}) commit({
    required OwnGroupState current,
    List<MemberDesc> additions = const [],
    List<String> removals = const [],
  }) {
    // Compute the new member list = (current - removals) + additions.
    final removedSet = removals.toSet();
    final base = current.members.where((m) => !removedSet.contains(m.deviceId)).toList();
    final newMembers = [...base, ...additions];

    // Fresh group_secret and external HPKE keypair.
    final newGroupSecret = c.rand.bytes(32);
    final (newExtPk, newExtSk) = c.xwing.keygen();

    // Build the wrap payload: groupSecret(32) || extSk(varies).
    final wrapPayload = Uint8List(newGroupSecret.length + newExtSk.length);
    wrapPayload.setAll(0, newGroupSecret);
    wrapPayload.setAll(newGroupSecret.length, newExtSk);

    // HPKE.seal a wrap targeted at each new member.
    final info = Uint8List.fromList(
        utf8.encode('commit|${current.groupId}|${current.epoch + 1}'));
    final wraps = <CommitWrap>[];
    for (final m in newMembers) {
      final (enc, ct, tag) =
          c.hpke.seal(m.hpkeKemPk, info, Uint8List(0), wrapPayload);
      wraps.add(CommitWrap(
          targetDevice: m.deviceId, enc: enc, ct: ct, tag: tag));
    }

    // Build + sign the Commit.
    final commit = Commit(
      groupId: current.groupId,
      newEpoch: current.epoch + 1,
      newMembers: newMembers,
      additions: additions,
      removals: removals,
      wraps: wraps,
      signerDevice: self.deviceId,
      signature: Uint8List(0), // placeholder, replaced below
    );
    final signature = c.mlDsa.sign(self.mlDsaSk, commit.signedBytes());
    final signedCommit = Commit(
      groupId: commit.groupId,
      newEpoch: commit.newEpoch,
      newMembers: commit.newMembers,
      additions: commit.additions,
      removals: commit.removals,
      wraps: commit.wraps,
      signerDevice: commit.signerDevice,
      signature: signature,
    );

    // Build Welcomes for each new joiner. A Welcome carries the full member
    // list (so the joiner can bootstrap from nothing) plus its own wrap of
    // groupSecret || extSk.
    final welcomes = <Welcome>[];
    final welcomeInfo = Uint8List.fromList(
        utf8.encode('welcome|${current.groupId}|${current.epoch + 1}'));
    for (final m in additions) {
      final (enc, ct, tag) =
          c.hpke.seal(m.hpkeKemPk, welcomeInfo, Uint8List(0), wrapPayload);
      final wel = Welcome(
        groupId: current.groupId,
        epoch: current.epoch + 1,
        members: newMembers,
        targetDevice: m.deviceId,
        enc: enc,
        ct: ct,
        tag: tag,
        signerDevice: self.deviceId,
        signature: Uint8List(0),
      );
      final welSig = c.mlDsa.sign(self.mlDsaSk, wel.signedBytes());
      welcomes.add(Welcome(
        groupId: wel.groupId,
        epoch: wel.epoch,
        members: wel.members,
        targetDevice: wel.targetDevice,
        enc: wel.enc,
        ct: wel.ct,
        tag: wel.tag,
        signerDevice: wel.signerDevice,
        signature: welSig,
      ));
    }

    // Build the new local state. Reset sentByThisDevice + heartbeat counter
    // (new epoch). Inherit the old epoch's groupSecret into the prior-epoch
    // cache so we can still decrypt late-arriving messages from the leaving
    // epoch.
    final newRecent = Map<int, Uint8List>.from(current.recentEpochSecrets);
    newRecent[current.epoch] = current.groupSecret;
    _trimEpochCache(newRecent);
    final newState = OwnGroupState(
      groupId: current.groupId,
      epoch: current.epoch + 1,
      groupSecret: newGroupSecret,
      externalHpkeSk: newExtSk,
      externalHpkePk: newExtPk,
      members: newMembers,
      recentEpochSecrets: newRecent,
    );

    return (commit: signedCommit, welcomes: welcomes, newState: newState);
  }

  static void _trimEpochCache(Map<int, Uint8List> cache) {
    if (cache.length <= kEpochCacheDepth) return;
    final sortedKeys = cache.keys.toList()..sort();
    while (cache.length > kEpochCacheDepth) {
      cache.remove(sortedKeys.removeAt(0));
    }
  }

  // ── Apply Commit (we are an existing member) ──────────────────────────────

  OwnGroupState applyCommit(OwnGroupState current, Commit commit) {
    if (commit.groupId != current.groupId) {
      throw StateError('commit groupId mismatch');
    }
    if (commit.newEpoch != current.epoch + 1) {
      throw StateError(
          'epoch jump: have=${current.epoch}, commit advances to ${commit.newEpoch}');
    }

    // Find the signer in the OLD member list (must be a current member).
    final signer = current.members.firstWhere(
        (m) => m.deviceId == commit.signerDevice,
        orElse: () =>
            throw StateError('commit signer ${commit.signerDevice} not in current members'));
    if (!c.mlDsa.verify(signer.mlDsaPk, commit.signedBytes(), commit.signature)) {
      throw StateError('commit signature invalid');
    }

    // Find our wrap.
    final ourWrap = commit.wraps.firstWhere(
        (w) => w.targetDevice == self.deviceId,
        orElse: () => throw StateError(
            'no wrap targeting ${self.deviceId} in commit'));

    // Open the wrap with our hpke SK (X-Wing — flat bytes, no FFI handle).
    final info = Uint8List.fromList(
        utf8.encode('commit|${current.groupId}|${commit.newEpoch}'));
    final payload = c.hpke.open(self.hpkeKemSk, ourWrap.enc, info, Uint8List(0),
        ourWrap.ct, ourWrap.tag);

    // Parse: groupSecret(32) || extSk(rest).
    final newGroupSecret = Uint8List.fromList(payload.sublist(0, 32));
    final newExtSk = Uint8List.fromList(payload.sublist(32));

    // X-Wing SK embeds the X25519 PK; ML-KEM PK we extract via the import dance.
    final extPk = _xwingPkFromSk(newExtSk);

    final newRecent = Map<int, Uint8List>.from(current.recentEpochSecrets);
    newRecent[current.epoch] = current.groupSecret;
    _trimEpochCache(newRecent);

    return OwnGroupState(
      groupId: current.groupId,
      epoch: commit.newEpoch,
      groupSecret: newGroupSecret,
      externalHpkeSk: newExtSk,
      externalHpkePk: extPk,
      members: commit.newMembers,
      recentEpochSecrets: newRecent,
    );
  }

  // ── Apply Welcome (we are a new joiner) ───────────────────────────────────

  OwnGroupState applyWelcome(Welcome welcome) {
    if (welcome.targetDevice != self.deviceId) {
      throw StateError(
          'welcome target=${welcome.targetDevice}, we are ${self.deviceId}');
    }
    // Verify signature using the signer's pk from the (untrusted) members list.
    final signer = welcome.members.firstWhere(
        (m) => m.deviceId == welcome.signerDevice,
        orElse: () => throw StateError(
            'welcome signer ${welcome.signerDevice} not in members list'));
    if (!c.mlDsa.verify(signer.mlDsaPk, welcome.signedBytes(), welcome.signature)) {
      throw StateError('welcome signature invalid');
    }

    // Open the wrap (X-Wing — flat bytes, no FFI handle).
    final info = Uint8List.fromList(
        utf8.encode('welcome|${welcome.groupId}|${welcome.epoch}'));
    final payload = c.hpke.open(self.hpkeKemSk, welcome.enc, info, Uint8List(0),
        welcome.ct, welcome.tag);

    final newGroupSecret = Uint8List.fromList(payload.sublist(0, 32));
    final newExtSk = Uint8List.fromList(payload.sublist(32));
    final extPk = _xwingPkFromSk(newExtSk);

    return OwnGroupState(
      groupId: welcome.groupId,
      epoch: welcome.epoch,
      groupSecret: newGroupSecret,
      externalHpkeSk: newExtSk,
      externalHpkePk: extPk,
      members: welcome.members,
    );
  }

  // ── App message: in-group send/receive ────────────────────────────────────

  AppMessage sendApp(OwnGroupState state, String plaintext) {
    final msgIdx = (state.sentByThisDevice[self.deviceId] ?? 0);
    state.sentByThisDevice[self.deviceId] = msgIdx + 1;
    state.msgsSinceCommit += 1;

    final msgKey = _deriveAppKey(state.groupSecret, self.deviceId, msgIdx);
    final nonce = c.rand.bytes(12);
    final (ct, tag) = c.aesGcm.seal(
        msgKey, nonce, Uint8List.fromList(utf8.encode(plaintext)));

    return AppMessage(
      groupId: state.groupId,
      epoch: state.epoch,
      senderDevice: self.deviceId,
      messageIndex: msgIdx,
      nonce: nonce,
      ct: ct,
      mac: tag,
    );
  }

  String receiveApp(OwnGroupState state, AppMessage msg) {
    if (msg.groupId != state.groupId) {
      throw StateError('app msg groupId mismatch');
    }
    Uint8List? secret;
    if (msg.epoch == state.epoch) {
      secret = state.groupSecret;
      state.msgsSinceCommit += 1;
    } else if (state.recentEpochSecrets.containsKey(msg.epoch)) {
      // Late-arriving message from a prior epoch — decrypt from cached secret.
      // Do NOT count it toward msgsSinceCommit (current epoch only).
      secret = state.recentEpochSecrets[msg.epoch];
    } else {
      throw StateError(
          'app msg epoch=${msg.epoch}, our state epoch=${state.epoch}, '
          'no cached secret (cache=${state.recentEpochSecrets.keys.toList()})');
    }
    final msgKey =
        _deriveAppKey(secret!, msg.senderDevice, msg.messageIndex);
    final pt = c.aesGcm.open(msgKey, msg.nonce, msg.ct, msg.mac);
    return utf8.decode(pt);
  }

  Uint8List _deriveAppKey(
      Uint8List groupSecret, String senderDevice, int msgIdx) {
    final info = Uint8List.fromList(utf8.encode('app|$senderDevice|$msgIdx'));
    return c.hkdf.derive(Uint8List(0), groupSecret, info, 32);
  }

  // ── External (cross-name) send/receive ────────────────────────────────────

  /// Sender (we are NOT in the target group). Encrypts a plaintext payload to
  /// peerInfo.externalHpkePk and signs with our identity ML-DSA key.
  ExternalAppMessage sendExternal({
    required GroupPublicInfo peerInfo,
    required String fromName,
    required String plaintext,
  }) {
    final info = Uint8List.fromList(
        utf8.encode('external|${peerInfo.groupId}|${peerInfo.epoch}'));
    final pt = Uint8List.fromList(utf8.encode(plaintext));
    final (enc, ct, tag) =
        c.hpke.seal(peerInfo.externalHpkePk, info, Uint8List(0), pt);

    final unsigned = ExternalAppMessage(
      fromName: fromName,
      fromDevice: self.deviceId,
      toGroupId: peerInfo.groupId,
      observedEpoch: peerInfo.epoch,
      enc: enc,
      ct: ct,
      tag: tag,
      signerPk: self.mlDsaPk,
      signature: Uint8List(0),
    );
    final sig = c.mlDsa.sign(self.mlDsaSk, unsigned.signedBytes());
    return ExternalAppMessage(
      fromName: unsigned.fromName,
      fromDevice: unsigned.fromDevice,
      toGroupId: unsigned.toGroupId,
      observedEpoch: unsigned.observedEpoch,
      enc: unsigned.enc,
      ct: unsigned.ct,
      tag: unsigned.tag,
      signerPk: unsigned.signerPk,
      signature: sig,
    );
  }

  /// Receiver (we ARE in the target group). Verifies the signature against a
  /// TOFU-pinned signer PK (if any), then opens with externalHpkeSk.
  ({String plaintext, bool firstSeenSigner}) receiveExternal({
    required OwnGroupState state,
    required ExternalAppMessage msg,
    required Map<String, Uint8List> trustedSignerPks,
  }) {
    if (msg.toGroupId != state.groupId) {
      throw StateError('external msg targeted at ${msg.toGroupId} but we are ${state.groupId}');
    }
    // TOFU check.
    final pinned = trustedSignerPks[msg.fromDevice];
    final firstSeen = pinned == null;
    if (!firstSeen && !bytesEqual(pinned, msg.signerPk)) {
      throw StateError(
          'TOFU mismatch: pinned signer pk for ${msg.fromName}/${msg.fromDevice} != msg signer');
    }
    if (!c.mlDsa.verify(msg.signerPk, msg.signedBytes(), msg.signature)) {
      throw StateError('external msg signature invalid');
    }

    // Open the HPKE ciphertext with our shared externalHpkeSk (X-Wing).
    final info = Uint8List.fromList(
        utf8.encode('external|${state.groupId}|${msg.observedEpoch}'));
    final pt = c.hpke.open(
        state.externalHpkeSk, msg.enc, info, Uint8List(0), msg.ct, msg.tag);
    return (plaintext: utf8.decode(pt), firstSeenSigner: firstSeen);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Recover an X-Wing PK from its SK. The SK layout is
  /// `ML-KEM SK (2400) || X25519 sk (32) || X25519 pk (32)`. The X25519 pk is
  /// stored verbatim; the ML-KEM pk is reconstructed by importing the SK and
  /// re-extracting the encoded public key (FIPS 203 SK includes PK material).
  Uint8List _xwingPkFromSk(Uint8List skBytes) {
    if (skBytes.length != XWingKem.skBytes) {
      throw ArgumentError('expected X-Wing sk size, got ${skBytes.length}');
    }
    final mlKemSk = Uint8List.sublistView(skBytes, 0, 2400);
    final x25519Pk = Uint8List.sublistView(skBytes, 2432);

    final ptr = c.mlKem.importSecretKey(Uint8List.fromList(mlKemSk));
    try {
      final mlKemPk = c.mlKem.extractEncodedPublicKey(ptr);
      final pk = Uint8List(XWingKem.pkBytes);
      pk.setAll(0, mlKemPk);
      pk.setAll(1184, x25519Pk);
      return pk;
    } finally {
      c.mlKem.freeKey(ptr);
    }
  }
}
