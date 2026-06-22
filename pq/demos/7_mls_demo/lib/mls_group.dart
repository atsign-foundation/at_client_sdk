import 'dart:convert';
import 'dart:typed_data';
import 'package:pq_demo_6/openssl.dart';
import 'mls_crypto.dart';
import 'epoch.dart';
import 'ratchet_tree.dart';
import 'secret_tree.dart';
import 'pqxdh.dart';
import 'key_package.dart';
import 'wire.dart';
import 'keystore.dart';

class MlsGroup {
  final Crypto _c;
  final Identity _self;
  GroupState state;
  EpochSecrets? _epochSecrets;
  SecretTree? _secretTree;   // sender ratchet (my leaf only, for encrypt)
  SecretTree? _receiveTree;  // receiver ratchets (other leaves, for decrypt)

  MlsGroup._(this._c, this._self, this.state);

  String get groupId => state.groupId;
  int get epoch => state.epoch;
  List<String> get memberDevices => state.memberLeafIndex.keys.toList();

  /// X-Wing public key for external commits, deterministically derived from
  /// the current epoch secret. Consistent across all group members.
  Uint8List get externalHpkePk => _externalKeypair().$1;

  /// Full X-Wing keypair for external HPKE operations (decaps).
  (Uint8List pk, Uint8List sk) _externalKeypair() {
    final seed32 = _epochSecrets?.externalHpkeSk ?? state.externalHpkeSk;
    if (seed32 == null) throw StateError('Epoch secrets not initialized');
    // Expand 32-byte epoch-derived seed to the 96 bytes X-Wing keygen needs:
    // [0:64] → ML-KEM-768 seed, [64:96] → X25519 private key.
    final seed96 = _c.hkdf.derive(
      Uint8List(32),
      seed32,
      Uint8List.fromList(utf8.encode('xwing-external-seed')),
      96,
    );
    return _c.xwing.keygenFromSeed(seed96);
  }

  int get myLeafIndex {
    final idx = state.memberLeafIndex[_self.deviceId];
    if (idx == null) throw StateError('Self not in group');
    return idx;
  }

  void _initEpochSecrets(EpochSecrets es) {
    _epochSecrets = es;
    _secretTree = SecretTree(_c.hmac, es.encryptionSecret, state.tree.numLeaves);
    _receiveTree = SecretTree(_c.hmac, es.encryptionSecret, state.tree.numLeaves);
    state.epochEncryptionSecrets[state.epoch] = es.encryptionSecret;
    state.senderDataSecret = es.senderDataSecret;
    state.externalHpkeSk = es.externalHpkeSk;
    const kCacheDepth = 2;
    if (state.epochEncryptionSecrets.length > kCacheDepth) {
      final sorted = state.epochEncryptionSecrets.keys.toList()..sort();
      while (state.epochEncryptionSecrets.length > kCacheDepth) {
        state.epochEncryptionSecrets.remove(sorted.removeAt(0));
      }
    }
  }

  GroupContext _groupContext() => GroupContext(
        groupId: state.groupId,
        epoch: state.epoch,
        treeHash: state.tree.treeHash(_c),
        confirmedTranscriptHash: state.confirmedTranscriptHash,
      );

  // ── Create group (solo bootstrap) ─────────────────────────────────────────

  static MlsGroup create(Crypto c, Identity self) {
    final groupId = '${self.name}_group';
    final tree = RatchetTree.empty();
    final leafIdx = tree.addLeaf(self.leafPk);
    final state = GroupState(
      groupId: groupId,
      epoch: 0,
      initSecret: Uint8List(32),
      confirmedTranscriptHash: Uint8List(32),
      tree: tree,
      memberLeafIndex: {self.deviceId: leafIdx},
      leafIndexMember: {leafIdx: self.deviceId},
    );
    final group = MlsGroup._(c, self, state);
    final ctx = group._groupContext().encode();
    final es = deriveEpochSecrets(c.hmac, state.initSecret, Uint8List(32), ctx);
    group._initEpochSecrets(es);
    state.initSecret = es.initSecret;
    return group;
  }

  // ── Restore from persisted state ──────────────────────────────────────────

  static MlsGroup restore(Crypto c, Identity self, GroupState gs) {
    final group = MlsGroup._(c, self, gs);
    final encSecret = gs.epochEncryptionSecrets[gs.epoch];
    if (encSecret != null) {
      group._secretTree = SecretTree(c.hmac, encSecret, gs.tree.numLeaves);
      group._receiveTree = SecretTree(c.hmac, encSecret, gs.tree.numLeaves);
      group._epochSecrets = EpochSecrets(
        senderDataSecret: gs.senderDataSecret ?? Uint8List(32),
        encryptionSecret: encSecret,
        exporterSecret: Uint8List(32),
        authenticationSecret: Uint8List(32),
        initSecret: gs.initSecret,
        resumptionPsk: Uint8List(32),
        membershipKey: Uint8List(32),
        externalHpkeSk: gs.externalHpkeSk ?? Uint8List(32),
      );
    }
    return group;
  }

  // ── Add member: generate Welcome + Commit ─────────────────────────────────

  ({MlsWelcome welcome, MlsCommit commit, GroupState newState}) addMember(
      KeyPackage joinerKp) {
    final newLeafSecret = _c.rand.bytes(32);
    final ctx = _groupContext();

    // Add joiner to tree
    final joinerLeafIdx = state.tree.addLeaf(joinerKp.leafPk);
    state.memberLeafIndex[joinerKp.deviceId] = joinerLeafIdx;
    state.leafIndexMember[joinerLeafIdx] = joinerKp.deviceId;

    final (commitPath, commitSecret) =
        state.tree.commitPath(_c, myLeafIndex, newLeafSecret, ctx.encode());

    // Advance transcript hash and epoch
    state.confirmedTranscriptHash = _c.sha256.hash(Uint8List.fromList([
      ...state.confirmedTranscriptHash,
      ...utf8.encode('${joinerKp.deviceId}|'),
    ]));
    final newEpoch = state.epoch + 1;

    final newCtx = GroupContext(
      groupId: state.groupId,
      epoch: newEpoch,
      treeHash: state.tree.treeHash(_c),
      confirmedTranscriptHash: state.confirmedTranscriptHash,
    );
    final es =
        deriveEpochSecrets(_c.hmac, state.initSecret, commitSecret, newCtx.encode());

    // PQXDH — derive masterSecret shared with joiner
    final (masterSecret, pqxdhEnv) = pqxdhSend(_c, _self.ikSk, joinerKp);

    // Welcome key from masterSecret
    final wKey = _c.hkdf.derive(
        Uint8List(32),
        masterSecret,
        Uint8List.fromList(utf8.encode('welcome-key')),
        32);
    final wNonce = _c.hkdf.derive(
        Uint8List(32),
        masterSecret,
        Uint8List.fromList(utf8.encode('welcome-nonce')),
        12);

    // Serialize minimal group state for joiner
    final gsJson = jsonEncode({
      'groupId': state.groupId,
      'epoch': newEpoch,
      'initSecret': base64Encode(es.initSecret),
      'cth': base64Encode(state.confirmedTranscriptHash),
      'tree': state.tree.toJson(),
      'memberLeafIndex': state.memberLeafIndex,
      'leafIndexMember':
          state.leafIndexMember.map((k, v) => MapEntry(k.toString(), v)),
      'encryptionSecret': base64Encode(es.encryptionSecret),
      'senderDataSecret': base64Encode(es.senderDataSecret),
      'externalHpkeSk': base64Encode(es.externalHpkeSk),
    });
    final gsPlain = Uint8List.fromList(utf8.encode(gsJson));
    final (gsCt, gsTag) =
        _c.aesGcm.seal(wKey, wNonce, gsPlain, aad: Uint8List(0));

    final sigBytes = Uint8List.fromList(
        utf8.encode('${state.groupId}:$newEpoch:${joinerKp.deviceId}'));
    final sig = _c.mlDsa.sign(_self.mlDsaSk, sigBytes);

    final welcome = MlsWelcome(
      groupId: state.groupId,
      epoch: newEpoch,
      targetDevice: joinerKp.deviceId,
      pqxdhEkPk: pqxdhEnv.ekPk,
      pqxdhKemCt: pqxdhEnv.kemCt,
      ct: gsCt,
      tag: gsTag,
      nonce: wNonce,
      senderIkPk: _self.ikPk,
      signerDevice: _self.deviceId,
      signature: sig,
    );

    final commit = MlsCommit(
      groupId: state.groupId,
      newEpoch: newEpoch,
      addedDevices: [joinerKp.deviceId],
      removedDevices: [],
      newMemberKps: [joinerKp],
      commitPath: commitPath,
      signerDevice: _self.deviceId,
      signature: sig,
    );

    state.epoch = newEpoch;
    state.initSecret = es.initSecret;
    _initEpochSecrets(es);

    return (welcome: welcome, commit: commit, newState: state);
  }

  // ── Apply Commit (existing non-committer member) ───────────────────────────

  void applyCommit(MlsCommit commit) {
    // Capture GroupContext BEFORE mutating the tree — must match what the
    // committer used in commitPath (which also captures ctx before addLeaf).
    final preCommitCtx = _groupContext().encode();

    for (final kp in commit.newMemberKps) {
      if (!state.memberLeafIndex.containsKey(kp.deviceId)) {
        final leafIdx = state.tree.addLeaf(kp.leafPk);
        state.memberLeafIndex[kp.deviceId] = leafIdx;
        state.leafIndexMember[leafIdx] = kp.deviceId;
      }
    }
    for (final deviceId in commit.removedDevices) {
      final leafIdx = state.memberLeafIndex.remove(deviceId);
      if (leafIdx != null) {
        state.leafIndexMember.remove(leafIdx);
        state.tree.removeLeaf(leafIdx);
      }
    }

    final senderLeafIdx =
        state.memberLeafIndex[commit.signerDevice] ?? myLeafIndex;
    final commitSecret = state.tree.applyCommitPath(
        _c, senderLeafIdx, commit.commitPath, myLeafIndex, _self.leafSk,
        preCommitCtx);

    // CTH format must match addMember/removeMember: "${addTag}|${remTag}"
    final addTag = commit.addedDevices.join(',');
    final remTag = commit.removedDevices.join(',');
    state.confirmedTranscriptHash = _c.sha256.hash(Uint8List.fromList([
      ...state.confirmedTranscriptHash,
      ...utf8.encode('$addTag|$remTag'),
    ]));

    state.epoch = commit.newEpoch;
    final newCtx = _groupContext();
    final es =
        deriveEpochSecrets(_c.hmac, state.initSecret, commitSecret, newCtx.encode());
    state.initSecret = es.initSecret;
    _initEpochSecrets(es);
  }

  // ── Apply Welcome (joiner) ─────────────────────────────────────────────────

  static MlsGroup applyWelcome(Crypto c, Identity self, MlsWelcome welcome) {
    final joinerSk = self.toKeyPackageSk();
    final pqxdhEnv = PqxdhEnvelope(welcome.pqxdhEkPk, welcome.pqxdhKemCt);
    final masterSecret =
        pqxdhReceive(c, joinerSk, welcome.senderIkPk, pqxdhEnv);

    final wKey = c.hkdf.derive(
        Uint8List(32),
        masterSecret,
        Uint8List.fromList(utf8.encode('welcome-key')),
        32);

    final gsMap = jsonDecode(utf8.decode(
            c.aesGcm.open(wKey, welcome.nonce, welcome.ct, welcome.tag, aad: Uint8List(0))))
        as Map<String, dynamic>;

    final tree = RatchetTree.fromJson(gsMap['tree'] as Map<String, dynamic>);
    final memberLeafIndex = Map<String, int>.from(
        (gsMap['memberLeafIndex'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int)));
    final leafIndexMember = Map<int, String>.from(
        (gsMap['leafIndexMember'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(int.parse(k), v as String)));
    final encryptionSecret =
        base64Decode(gsMap['encryptionSecret'] as String);
    final senderDataSecret =
        base64Decode(gsMap['senderDataSecret'] as String);
    final externalHpkeSk =
        base64Decode(gsMap['externalHpkeSk'] as String);

    final gs = GroupState(
      groupId: gsMap['groupId'] as String,
      epoch: gsMap['epoch'] as int,
      initSecret: base64Decode(gsMap['initSecret'] as String),
      confirmedTranscriptHash: base64Decode(gsMap['cth'] as String),
      tree: tree,
      memberLeafIndex: memberLeafIndex,
      leafIndexMember: leafIndexMember,
      senderDataSecret: senderDataSecret,
      externalHpkeSk: externalHpkeSk,
    );
    gs.epochEncryptionSecrets[gs.epoch] = encryptionSecret;

    final group = MlsGroup._(c, self, gs);
    group._secretTree = SecretTree(c.hmac, encryptionSecret, tree.numLeaves);
    group._receiveTree = SecretTree(c.hmac, encryptionSecret, tree.numLeaves);
    group._epochSecrets = EpochSecrets(
      senderDataSecret: senderDataSecret,
      encryptionSecret: encryptionSecret,
      exporterSecret: Uint8List(32),
      authenticationSecret: Uint8List(32),
      initSecret: gs.initSecret,
      resumptionPsk: Uint8List(32),
      membershipKey: Uint8List(32),
      externalHpkeSk: externalHpkeSk,
    );
    return group;
  }

  // ── Encrypt message ────────────────────────────────────────────────────────

  MlsCiphertext encrypt(String plaintext) {
    final es = _epochSecrets;
    final st = _secretTree;
    if (es == null || st == null) throw StateError('Group not ready for encryption');

    final leafIdx = myLeafIndex;
    final ratchet = st.getRatchet(leafIdx);
    final gen = ratchet.generation;
    final mk = ratchet.deriveMessageKey(gen);
    final ctx = _groupContext();

    final (ct, tag) = _c.aesGcm.seal(
        mk.key, mk.nonce, Uint8List.fromList(utf8.encode(plaintext)),
        aad: ctx.encode());

    // Sender data: AES-GCM seal (leafIndex || generation) under key derived from senderDataSecret
    final sdNonce = _c.rand.bytes(12);
    final sdKey =
        expandWithLabel(_c.hmac, es.senderDataSecret, 'key', sdNonce, 32);
    final sdPlain = Uint8List(8)
      ..[0] = (leafIdx >> 24) & 0xff
      ..[1] = (leafIdx >> 16) & 0xff
      ..[2] = (leafIdx >> 8) & 0xff
      ..[3] = leafIdx & 0xff
      ..[4] = (gen >> 24) & 0xff
      ..[5] = (gen >> 16) & 0xff
      ..[6] = (gen >> 8) & 0xff
      ..[7] = gen & 0xff;
    final (sdCt, sdTag) =
        _c.aesGcm.seal(sdKey, sdNonce, sdPlain, aad: Uint8List(0));

    final senderDataCtFull = Uint8List(sdCt.length + sdTag.length);
    senderDataCtFull.setAll(0, sdCt);
    senderDataCtFull.setAll(sdCt.length, sdTag);

    return MlsCiphertext(
      groupId: state.groupId,
      epoch: state.epoch,
      leafIndex: leafIdx,
      generation: gen,
      senderDataNonce: sdNonce,
      senderDataCt: senderDataCtFull,
      ct: ct,
      tag: tag,
    );
  }

  // ── Decrypt message ────────────────────────────────────────────────────────

  ({String plaintext, String senderDevice}) decrypt(MlsCiphertext msg) {
    if (msg.groupId != state.groupId) throw StateError('Wrong group');

    Uint8List encSecret;
    SecretTree st;
    Uint8List senderDataSecret;

    if (msg.epoch == state.epoch) {
      final es = _epochSecrets ??
          (throw StateError('Epoch secrets not initialized'));
      encSecret = es.encryptionSecret;
      senderDataSecret = es.senderDataSecret;
      st = _receiveTree ?? SecretTree(_c.hmac, encSecret, state.tree.numLeaves);
    } else {
      encSecret = state.epochEncryptionSecrets[msg.epoch] ??
          (throw StateError('No stored secret for epoch ${msg.epoch}'));
      senderDataSecret =
          deriveSecret(_c.hmac, encSecret, 'sender data restore');
      st = SecretTree(_c.hmac, encSecret, state.tree.numLeaves);
    }

    // Decrypt sender data to get leafIndex + generation
    final sdKey =
        expandWithLabel(_c.hmac, senderDataSecret, 'key', msg.senderDataNonce, 32);
    final sdCt = msg.senderDataCt.sublist(0, msg.senderDataCt.length - 16);
    final sdTag = msg.senderDataCt.sublist(msg.senderDataCt.length - 16);
    final sdPlain =
        _c.aesGcm.open(sdKey, msg.senderDataNonce, sdCt, sdTag, aad: Uint8List(0));

    final leafIdx =
        (sdPlain[0] << 24) | (sdPlain[1] << 16) | (sdPlain[2] << 8) | sdPlain[3];
    final gen =
        (sdPlain[4] << 24) | (sdPlain[5] << 16) | (sdPlain[6] << 8) | sdPlain[7];

    final mk = st.getRatchet(leafIdx).deriveMessageKey(gen);

    final ctx = GroupContext(
      groupId: state.groupId,
      epoch: msg.epoch,
      treeHash: state.tree.treeHash(_c),
      confirmedTranscriptHash: state.confirmedTranscriptHash,
    );
    final plain =
        _c.aesGcm.open(mk.key, mk.nonce, msg.ct, msg.tag, aad: ctx.encode());

    final senderDevice =
        state.leafIndexMember[leafIdx] ?? 'unknown@$leafIdx';
    return (plaintext: utf8.decode(plain), senderDevice: senderDevice);
  }

  // ── Cross-group HPKE (external sender) ───────────────────────────────────

  /// Encrypt [plaintext] to a peer group using their X-Wing external public key.
  (Uint8List kemCt, Uint8List nonce, Uint8List ct, Uint8List tag) externalEncrypt(
      Uint8List targetPk, Uint8List plaintext) {
    final (kemCt, ss) = _c.xwing.encaps(targetPk);
    final msgKey = _c.hkdf.derive(
        Uint8List(32), ss, Uint8List.fromList(utf8.encode('mls-external-msg')), 32);
    final nonce = _c.rand.bytes(12);
    final (ct, tag) = _c.aesGcm.seal(msgKey, nonce, plaintext, aad: Uint8List(0));
    return (kemCt, nonce, ct, tag);
  }

  /// Decrypt an mls_external message using this group's epoch-bound X-Wing sk.
  Uint8List externalDecrypt(
      Uint8List kemCt, Uint8List nonce, Uint8List ct, Uint8List tag) {
    final (_, sk) = _externalKeypair();
    final ss = _c.xwing.decaps(sk, kemCt);
    final msgKey = _c.hkdf.derive(
        Uint8List(32), ss, Uint8List.fromList(utf8.encode('mls-external-msg')), 32);
    return _c.aesGcm.open(msgKey, nonce, ct, tag, aad: Uint8List(0));
  }

  // ── Update leaf key (PCS — periodic key rotation) ─────────────────────────

  MlsCommit updateLeafKey() {
    final newLeafSecret = _c.rand.bytes(32);
    final ctx = _groupContext();
    final (commitPath, commitSecret) =
        state.tree.commitPath(_c, myLeafIndex, newLeafSecret, ctx.encode());

    // Update commit: no members added or removed → CTH tag is '|'
    state.confirmedTranscriptHash = _c.sha256.hash(Uint8List.fromList([
      ...state.confirmedTranscriptHash,
      ...utf8.encode('|'),
    ]));
    state.epoch++;

    final newCtx = _groupContext();
    final es =
        deriveEpochSecrets(_c.hmac, state.initSecret, commitSecret, newCtx.encode());
    state.initSecret = es.initSecret;
    _initEpochSecrets(es);

    final sig = _c.mlDsa.sign(_self.mlDsaSk,
        Uint8List.fromList(utf8.encode('${state.groupId}:${state.epoch}:update')));

    return MlsCommit(
      groupId: state.groupId,
      newEpoch: state.epoch,
      addedDevices: [],
      removedDevices: [],
      newMemberKps: [],
      commitPath: commitPath,
      signerDevice: _self.deviceId,
      signature: sig,
    );
  }

  // ── Remove member ──────────────────────────────────────────────────────────

  MlsCommit removeMember(String deviceId) {
    final leafIdx = state.memberLeafIndex.remove(deviceId);
    if (leafIdx != null) {
      state.leafIndexMember.remove(leafIdx);
      state.tree.removeLeaf(leafIdx);
    }

    final newLeafSecret = _c.rand.bytes(32);
    final ctx = _groupContext();
    final (commitPath, commitSecret) =
        state.tree.commitPath(_c, myLeafIndex, newLeafSecret, ctx.encode());

    state.confirmedTranscriptHash = _c.sha256.hash(Uint8List.fromList([
      ...state.confirmedTranscriptHash,
      ...utf8.encode('|$deviceId'),
    ]));
    state.epoch++;

    final newCtx = _groupContext();
    final es =
        deriveEpochSecrets(_c.hmac, state.initSecret, commitSecret, newCtx.encode());
    state.initSecret = es.initSecret;
    _initEpochSecrets(es);

    final sig = _c.mlDsa.sign(_self.mlDsaSk,
        Uint8List.fromList(utf8.encode('${state.groupId}:${state.epoch}:remove:$deviceId')));

    return MlsCommit(
      groupId: state.groupId,
      newEpoch: state.epoch,
      addedDevices: [],
      removedDevices: [deviceId],
      newMemberKps: [],
      commitPath: commitPath,
      signerDevice: _self.deviceId,
      signature: sig,
    );
  }
}
