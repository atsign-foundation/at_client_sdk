// In-process simulation: alice bootstraps her group, adds a second device,
// bob bootstraps his group, alice and bob exchange external messages.
//
// Run: dart run bin/ratchet_test.dart

import 'dart:io';
import '../lib/group_ratchet.dart';
import '../lib/keystore.dart' show Identity, kHeartbeatMsgThreshold;
import '../lib/openssl.dart';

final _failures = <String>[];

void check(String label, bool ok, [String? detail]) {
  final mark = ok ? '[PASS]' : '[FAIL]';
  print('$mark $label${detail != null ? "  $detail" : ""}');
  if (!ok) _failures.add(label);
}

void main() {
  final c = Crypto.load();

  // ── Alice: device1 bootstraps the group ─────────────────────────────────
  final alice1 = Identity.generate(c, 'alice', 'device1');
  final r1 = GroupRatchet(c, alice1);
  var ag = r1.bootstrap('alice');
  check('alice/device1 bootstrap',
      ag.epoch == 0 && ag.members.length == 1, 'epoch=${ag.epoch} members=${ag.members.length}');

  // ── Alice: device2 joins via Commit + Welcome ───────────────────────────
  final alice2 = Identity.generate(c, 'alice', 'device2');
  final r1b = GroupRatchet(c, alice1);   // committer is device1
  final cw = r1b.commit(current: ag, additions: [alice2.toMemberDesc()]);
  check('alice commitAdd → epoch advanced',
      cw.newState.epoch == 1 && cw.newState.members.length == 2,
      'epoch=${cw.newState.epoch} members=${cw.newState.members.length}');
  check('alice produced 1 welcome',
      cw.welcomes.length == 1 && cw.welcomes.first.targetDevice == 'device2');

  // alice/device1 applies its own commit locally (it didn't author its own wrap;
  // it just adopts the newState it built).
  ag = cw.newState;

  // alice/device2 applies the welcome
  final r2 = GroupRatchet(c, alice2);
  var ag2 = r2.applyWelcome(cw.welcomes.first);
  check('alice/device2 joined via welcome',
      ag2.epoch == 1 && ag2.members.length == 2 &&
          bytesEqual(ag2.groupSecret, ag.groupSecret),
      'epoch=${ag2.epoch} secrets-match=${bytesEqual(ag2.groupSecret, ag.groupSecret)}');

  // ── In-group app message: device1 → device2 ─────────────────────────────
  final appMsg = r1.sendApp(ag, 'hello other-device');
  final received = r2.receiveApp(ag2, appMsg);
  check('in-group app msg roundtrip',
      received == 'hello other-device', '"$received"');

  // ── Bob: device1 bootstraps bob's group ─────────────────────────────────
  final bob1 = Identity.generate(c, 'bob', 'phone');
  final rb1 = GroupRatchet(c, bob1);
  var bg = rb1.bootstrap('bob');
  check('bob/phone bootstrap',
      bg.epoch == 0 && bg.members.length == 1);

  // ── External: alice/device1 → bob's group ───────────────────────────────
  final ext = r1.sendExternal(
    peerInfo: bg.toPublicInfo(),
    fromName: 'alice',
    plaintext: 'hi bob, msg from alice',
  );
  check('alice built external_app: enc=1120B (X-Wing)?',
      ext.enc.length == 1120, 'got ${ext.enc.length}');
  final res = rb1.receiveExternal(
      state: bg, msg: ext, trustedSignerPks: {});
  check('bob received external msg',
      res.plaintext == 'hi bob, msg from alice', '"${res.plaintext}"');
  check('bob first-seen signer (TOFU on first contact)', res.firstSeenSigner);

  // ── Bob adds device2 (laptop) via Commit + Welcome ──────────────────────
  final bob2 = Identity.generate(c, 'bob', 'laptop');
  final cb = rb1.commit(current: bg, additions: [bob2.toMemberDesc()]);
  bg = cb.newState;
  final rb2 = GroupRatchet(c, bob2);
  var bg2 = rb2.applyWelcome(cb.welcomes.first);
  check('bob/laptop joined',
      bg2.epoch == 1 && bytesEqual(bg2.groupSecret, bg.groupSecret));

  // External from alice now uses bob's NEW externalHpkePk.
  final ext2 = r1.sendExternal(
    peerInfo: bg.toPublicInfo(),
    fromName: 'alice',
    plaintext: 'hi all bob devices',
  );
  final resPhone = rb1.receiveExternal(state: bg, msg: ext2, trustedSignerPks: {
    'device1': alice1.mlDsaPk
  });
  final resLaptop = rb2.receiveExternal(state: bg2, msg: ext2, trustedSignerPks: {
    'device1': alice1.mlDsaPk
  });
  check('bob/phone decrypts external msg #2',
      resPhone.plaintext == 'hi all bob devices');
  check('bob/laptop decrypts external msg #2',
      resLaptop.plaintext == 'hi all bob devices');
  check('TOFU honored (not first-seen this time)',
      !resPhone.firstSeenSigner && !resLaptop.firstSeenSigner);

  // ── Alice Removes device2 ───────────────────────────────────────────────
  final cwR = r1.commit(current: ag, removals: ['device2']);
  ag = cwR.newState;
  check('alice removed device2 → epoch advanced',
      ag.epoch == 2 && ag.members.length == 1);

  // device1 sends — device2 cannot decrypt (it has stale state).
  final msgAfter = r1.sendApp(ag, 'just me now');
  try {
    r2.receiveApp(ag2, msgAfter);
    check('device2 fails to decrypt post-removal', false, 'unexpectedly succeeded');
  } catch (_) {
    check('device2 fails to decrypt post-removal', true);
  }

  // ── Patch 2: out-of-order delivery via epoch cache ──────────────────────
  // bob/phone is at epoch 1 (after laptop joined). Compose an app msg at
  // epoch 1, then trigger a heartbeat commit that advances to epoch 2, then
  // attempt to decrypt the epoch-1 message on the now-epoch-2 state.
  final lateMsg = rb1.sendApp(bg, 'late msg from phone');
  check('lateMsg sent at epoch 1', lateMsg.epoch == 1, 'epoch=${lateMsg.epoch}');
  // laptop is the lowest deviceId ("laptop" < "phone"), so laptop is leader.
  bg.msgsSinceCommit = kHeartbeatMsgThreshold;
  check('laptop is heartbeat leader at threshold',
      bg.shouldHeartbeat('laptop') && !bg.shouldHeartbeat('phone'),
      'msgsSinceCommit=${bg.msgsSinceCommit}');
  final hb = rb1.commit(current: bg);
  bg = hb.newState;
  // Laptop applies the heartbeat commit.
  bg2 = rb2.applyCommit(bg2, hb.commit);
  check('heartbeat → epoch advanced',
      bg.epoch == 2 && bg2.epoch == 2, 'phone=${bg.epoch} laptop=${bg2.epoch}');
  check('laptop has prior-epoch secret cached',
      bg2.recentEpochSecrets.containsKey(1),
      'cache=${bg2.recentEpochSecrets.keys.toList()}');
  // Now decrypt the epoch-1 message on the epoch-2 state (should fall back
  // to the cached prior secret).
  final lateDecoded = rb2.receiveApp(bg2, lateMsg);
  check('out-of-order app msg from prior epoch decrypts via cache',
      lateDecoded == 'late msg from phone', '"$lateDecoded"');

  // After 2 more commits, epoch 1 should fall out of the depth-2 cache.
  final hb2 = rb1.commit(current: bg);
  bg = hb2.newState;
  final hb3 = rb1.commit(current: bg);
  bg = hb3.newState;
  check('cache trimmed to kEpochCacheDepth (=2)',
      bg.recentEpochSecrets.length == 2 &&
          !bg.recentEpochSecrets.containsKey(1),
      'kept=${bg.recentEpochSecrets.keys.toList()}');

  // Summary
  print('\n=== Summary ===');
  if (_failures.isEmpty) {
    print('[PASS] ratchet end-to-end.');
  } else {
    print('[FAIL] ${_failures.length} failure(s):');
    for (final f in _failures) print('  - $f');
    exit(1);
  }
}
