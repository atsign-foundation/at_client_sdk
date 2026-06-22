// MLS group chat — one terminal per actor.
//
// Usage:
//   dart run bin/chat.dart <name> [<device>] [--reset]
//
// Each actor owns their own MLS group (alice_group, bob_group, …).
// Multiple devices of the same actor share one DB and join the same group.
// Cross-actor messages are encrypted with the target group's externalHpkePk
// (X-Wing, epoch-derived) and delivered as mls_external to the target's inbox.
//
// End-to-end test:
//   Terminal 1: dart run bin/chat.dart alice          # creates alice_group
//   Terminal 2: dart run bin/chat.dart bob            # creates bob_group
//   Terminal 3: dart run bin/chat.dart alice phone    # joins alice_group
//
// Reset:
//   dart run bin/chat.dart alice --reset
//   dart run bin/chat.dart bob --reset

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/atserver.dart';
import '../lib/transport.dart';
import '../lib/keystore.dart';
import '../lib/mls_group.dart';
import '../lib/wire.dart';
import 'package:pq_demo_6/openssl.dart';

late final DateTime _t0;

String _ts() {
  final dt = DateTime.now().difference(_t0).inMilliseconds / 1000.0;
  return '[t+${dt.toStringAsFixed(3)}]';
}

String _ansi(String s, int code) => '\x1B[${code}m$s\x1B[0m';
String _dim(String s) => _ansi(s, 90);
String _yellow(String s) => _ansi(s, 33);
String _green(String s) => _ansi(s, 32);
String _red(String s) => _ansi(s, 31);

String _selfStr = '';

void logLine(String verb, String msg) =>
    print('${_dim(_ts())}  ${_yellow(_selfStr.padRight(14))}  ${verb.padRight(6)}  $msg');
void logChat(String from, String body) =>
    print('${_dim(_ts())}  ${_yellow(_selfStr.padRight(14))}  ${_green('chat')}    ${_green('<$from> $body')}');
void logErr(String msg) =>
    print('${_dim(_ts())}  ${_yellow(_selfStr.padRight(14))}  ${_red('err')}     $msg');

bool _verbose  = false;
bool _showTree = false;
late final Crypto _c;

void logVerbose(String verb, String msg) {
  if (!_verbose) return;
  print('${_dim(_ts())}  ${_yellow(_selfStr.padRight(14))}  ${_dim(verb.padRight(6))}  $msg');
}

void logTree(MlsGroup g, String trigger) {
  if (!_showTree) return;
  final leaves = g.state.tree.leafInfo();
  print('');
  print(_dim('─' * 64));
  print('  TREE  ${_yellow(g.groupId)}  epoch=${g.epoch}  trigger=$trigger');
  for (var i = 0; i < leaves.length; i++) {
    final dId = g.state.leafIndexMember[i] ?? '(unknown)';
    final info = leaves[i];
    final pkStr = info.pk == null ? '(blank)' : hex(info.pk!, maxBytes: 8);
    final me = dId == _selfStr ? '  ← me' : '';
    print('  leaf[$i]  ${dId.padRight(20)}  pk=$pkStr$me');
  }
  print('  treeHash=${hex(g.state.tree.treeHash(_c), maxBytes: 8)}');
  print(_dim('─' * 64));
  print('');
}

void usage() {
  print('Usage: dart run bin/chat.dart <name> [<device>] [--reset] [--tree] [--verbose]');
  exit(1);
}

Future<void> main(List<String> args) async {
  _t0 = DateTime.now();

  final positionals = args.where((a) => !a.startsWith('-')).toList();
  if (positionals.isEmpty) usage();

  final actorName = positionals[0].toLowerCase();
  final device = positionals.length > 1 ? positionals[1].toLowerCase() : 'main';
  final deviceId = '$actorName:$device';
  final reset   = args.contains('--reset');
  final verbose  = args.contains('--verbose');
  final showTree = args.contains('--tree');
  _selfStr   = deviceId;
  _verbose   = verbose;
  _showTree  = showTree;

  final c = Crypto.load();
  _c = c;

  if (reset) {
    final ksFile = File('${actorName}_${deviceId}_mls7_ks.json');
    if (await ksFile.exists()) await ksFile.delete();
    final dbFile = File('${actorName}.db');
    if (await dbFile.exists()) await dbFile.delete();
    logLine('reset', 'cleared keystore + ${actorName}.db');
    exit(0);
  }

  final ks = await Keystore.loadOrGenerate(c, actorName, deviceId);
  logLine('init',
      'identity loaded  device=$deviceId  ml-dsa.pk=${hex(ks.identity.mlDsaPk, maxBytes: 6)}');

  final store = Store.open(actorName);

  // Publish our KeyPackage so peers can inspect our public keys.
  final myKp = ks.identity.toKeyPackage();
  put(store, 'kp:$deviceId', myKp.encode());
  logLine('pub', 'KeyPackage published');

  MlsGroup? group;

  if (ks.groupState != null) {
    final gs = ks.groupState!;
    final expectedGroupId = '${actorName}_group';
    if (gs.groupId == expectedGroupId) {
      group = MlsGroup.restore(c, ks.identity, gs);
    } else {
      // Stale state from old architecture (e.g., bob was in alice_group).
      // Discard and create own group below.
      logLine('group', 'discarding stale groupId=${gs.groupId} (expected $expectedGroupId)');
      ks.groupState = null;
      await ks.save();
    }
  }

  void publishGroupInfo() {
    if (group == null) return;
    final info = GroupPublicInfo(
      groupId: group!.groupId,
      epoch: group!.epoch,
      memberDevices: group!.memberDevices,
      treeHash: group!.state.tree.treeHash(c),
    );
    put(store, 'group:$deviceId', info.encode());
    put(store, 'group:active', info.encode());
    put(store, 'group:external_pk', base64Encode(group!.externalHpkePk));
  }

  /// Deliver a message to each device currently in the group by device ID.
  /// Uses targeted delivery so new joiners don't receive messages from before
  /// they were members.
  void broadcastToGroup(String msgType, String value) {
    if (group == null) return;
    for (final d in group!.memberDevices) {
      final actor = d.split(':').first;
      notifyActorDevice(actor, d, actorName, deviceId, msgType, value);
    }
  }

  // ── Group bootstrap ──────────────────────────────────────────────────────────
  //
  // Each actor always owns their own group (${actorName}_group).
  // Same-actor multi-device: second device reads 'group:active' from shared DB
  //   and sends a JoinRequest into the same DB's inbox.
  // Cross-actor messaging is handled via mls_external — never via group join.
  //
  // Priority:
  //   1. Restored multi-member group → refresh rendezvous.
  //   2. Restored solo group → host it (wait for same-actor devices to join).
  //   3. No saved state + own DB has 'group:active' → same-actor second device,
  //      send JoinRequest into own inbox.
  //   4. No saved state + no 'group:active' → first device, create own group.

  if (group != null && group.memberDevices.length > 1) {
    // Already in a multi-member group — refresh rendezvous.
    publishGroupInfo();
    logLine('group',
        'restored epoch=${group.epoch} members=${group.memberDevices.join(',')}');
  } else if (group != null && group.memberDevices.length == 1) {
    // Solo restored group — host it and wait for same-actor peers.
    publishGroupInfo();
    logLine('group', 'hosting groupId=${group.groupId} — waiting for peers');
  } else {
    // No saved state. Check own DB for an existing group (same actor, other device).
    final ownActive = get(store, 'group:active');
    if (ownActive != null) {
      // Another device of this actor already created the group — join it.
      final info = GroupPublicInfo.decode(ownActive);
      group = MlsGroup.create(c, ks.identity);
      ks.groupState = group.state;
      await ks.save();
      final jr = JoinRequest(
          groupId: info.groupId, fromDevice: deviceId, keyPackage: myKp);
      notifyActorBroadcast(actorName, actorName, deviceId, 'mls_join_request', jr.encode());
      logLine('join', 'JoinRequest → own group ${info.groupId} (waiting for Welcome)');
    } else {
      // First device of this actor — create own group.
      group = MlsGroup.create(c, ks.identity);
      ks.groupState = group.state;
      await ks.save();
      publishGroupInfo();
      logLine('group', 'created groupId=${group.groupId} epoch=0 (host)');
    }
  }

  // PCS: rotate leaf key every 3 sent messages.
  int _msgsSinceUpdate = 0;
  const int kUpdateInterval = 3;

  // Guard against re-entrant handleInbox calls.
  bool _handling = false;

  Future<void> handleInbox() async {
    if (_handling) return;
    _handling = true;
    try {
      final rows = pollInbox(store, deviceId);
      for (final row in rows) {
        try {
          final j = jsonDecode(row.value) as Map<String, dynamic>;
          final type = j['type'] as String?;

          // ── Join request: admit a new member ──────────────────────────────
          if (type == 'mls_join_request') {
            if (group == null) continue;
            final jr = JoinRequest.decode(row.value);
            if (jr.fromDevice == deviceId) continue;
            if (jr.groupId != group!.groupId) continue;
            if (group!.memberDevices.contains(jr.fromDevice)) continue;

            // Only the lexicographically first current member acts as host.
            final sorted = group!.memberDevices.toList()..sort();
            if (sorted.first != deviceId) continue;

            logLine('join', 'JoinRequest from ${jr.fromDevice}');

            final result = group!.addMember(jr.keyPackage);
            ks.groupState = result.newState;
            await ks.save();
            publishGroupInfo();

            // Broadcast Commit to all current members (pre-add member list).
            broadcastToGroup('mls_commit', result.commit.encode());
            logLine('commit', 'broadcast epoch=${result.commit.newEpoch}');

            // Send Welcome directly to the joiner's actor DB.
            final joinerActor = jr.fromDevice.split(':').first;
            notifyActorDevice(joinerActor, jr.fromDevice, actorName, deviceId,
                'mls_welcome', result.welcome.encode());
            logLine('welcome', 'sent to ${jr.fromDevice}');

          // ── Welcome: bootstrap into the group ─────────────────────────────
          } else if (type == 'mls_welcome') {
            final w = MlsWelcome.decode(row.value);
            if (w.targetDevice != deviceId) continue;
            if (group != null && group!.memberDevices.contains(deviceId) &&
                group!.memberDevices.length > 1) continue;

            logLine('welcome', 'received from ${w.signerDevice}');
            try {
              group = MlsGroup.applyWelcome(c, ks.identity, w);
              ks.groupState = group!.state;
              await ks.save();
              publishGroupInfo();
              logLine('group',
                  'joined epoch=${group!.epoch} members=${group!.memberDevices.join(',')}');
            } catch (e) {
              logErr('Welcome apply failed: $e');
            }

          // ── Commit: advance epoch (existing members only) ─────────────────
          } else if (type == 'mls_commit') {
            if (group == null) continue;
            final commit = MlsCommit.decode(row.value);
            if (commit.signerDevice == deviceId) continue;
            if (commit.newEpoch <= group!.epoch) continue;
            if (!group!.memberDevices.contains(commit.signerDevice)) continue;

            logLine('commit',
                'applying epoch=${commit.newEpoch} from ${commit.signerDevice}');
            try {
              group!.applyCommit(commit);
              ks.groupState = group!.state;
              await ks.save();
              publishGroupInfo();
            } catch (e) {
              logErr('Commit apply failed: $e');
            }

          // ── App message: decrypt and display ──────────────────────────────
          } else if (type == 'mls_app') {
            if (group == null) continue;
            final msg = MlsCiphertext.decode(row.value);
            if (msg.groupId != group!.groupId) continue;
            if (msg.epoch > group!.epoch) continue;
            try {
              final r = group!.decrypt(msg);
              if (r.senderDevice == deviceId) continue;
              logChat(r.senderDevice, r.plaintext);
            } catch (e) {
              logErr('decrypt failed: $e');
            }

          // ── External message: cross-group X-Wing HPKE ─────────────────────
          } else if (type == 'mls_external') {
            if (group == null) continue;
            final targetEpoch = j['targetEpoch'] as int?;
            if (targetEpoch != null && targetEpoch != group!.epoch) continue;
            try {
              final kemCt = base64Decode(j['kemCt'] as String);
              final nonce  = base64Decode(j['nonce'] as String);
              final ct     = base64Decode(j['ct'] as String);
              final tag    = base64Decode(j['tag'] as String);
              final from   = j['from'] as String;
              final plain  = group!.externalDecrypt(kemCt, nonce, ct, tag);
              logChat(from, utf8.decode(plain));
            } catch (e) {
              logErr('externalDecrypt failed: $e');
            }
          }
        } catch (e) {
          logErr('inbox row parse error: $e');
        }
      }
    } catch (e) {
      logErr('pollInbox error: $e');
    } finally {
      _handling = false;
    }
  }

  final pollTimer =
      Timer.periodic(const Duration(milliseconds: 250), (_) { handleInbox(); });

  // ── stdin chat loop ────────────────────────────────────────────────────────
  logLine('ready', 'type a message and press Enter  (Ctrl+C to quit)');

  final _quit = Completer<void>();
  ProcessSignal.sigint.watch().first.then((_) => _quit.complete());

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    final text = line.trim();
    if (text.isEmpty) return;
    if (group == null) {
      logErr('not in a group yet — waiting for Welcome');
      return;
    }
    try {
      // Intra-group: MLS app message to own group members.
      final ct = group!.encrypt(text);
      broadcastToGroup('mls_app', ct.encode());

      // Cross-group: X-Wing HPKE to each peer actor's group.
      for (final peer in discoverPeerActors(actorName)) {
        final peerPkB64 = peekActorKey(peer, 'group:external_pk');
        if (peerPkB64 == null) continue;
        final peerActiveJson = peekActorKey(peer, 'group:active');
        final peerEpoch = peerActiveJson != null
            ? GroupPublicInfo.decode(peerActiveJson).epoch
            : 0;
        final peerPk = base64Decode(peerPkB64);
        final (kemCt, nonce, appCt, tag) =
            group!.externalEncrypt(peerPk, utf8.encode(text));
        final payload = jsonEncode({
          'type': 'mls_external',
          'from': deviceId,
          'targetEpoch': peerEpoch,
          'kemCt': base64Encode(kemCt),
          'nonce': base64Encode(nonce),
          'ct': base64Encode(appCt),
          'tag': base64Encode(tag),
        });
        notifyActorBroadcast(peer, actorName, deviceId, 'mls_external', payload);
      }

      logLine('send', 'epoch=${ct.epoch} gen=${ct.generation} len=${text.length}B');

      // PCS: rotate leaf key every kUpdateInterval messages.
      _msgsSinceUpdate++;
      if (_msgsSinceUpdate >= kUpdateInterval && group!.memberDevices.length > 1) {
        _msgsSinceUpdate = 0;
        try {
          final updateCommit = group!.updateLeafKey();
          ks.groupState = group!.state;
          ks.save().ignore();
          publishGroupInfo();
          broadcastToGroup('mls_commit', updateCommit.encode());
          logLine('update', 'leaf key rotated epoch=${group!.epoch}');
        } catch (e) {
          logErr('leaf key update failed: $e');
        }
      }
    } catch (e) {
      logErr('encrypt failed: $e');
    }
  });

  await _quit.future;

  pollTimer.cancel();
  while (_handling) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  store.close();
}
