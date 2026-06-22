// Interactive chat — one actor per process.
//
// Usage:
//   dart run bin/chat.dart <self_name>:<self_device> <peer_name>
//
// Examples:
//   dart run bin/chat.dart alice:device1 bob       # alice's first device
//   dart run bin/chat.dart alice:device2 bob       # alice's second device
//   dart run bin/chat.dart bob:phone alice         # bob's phone
//   dart run bin/chat.dart bob:laptop alice        # bob's laptop
//
// All actors with the same <self_name> share an `<name>_store.db` SQLite file.
// `--reset` deletes all on-disk state for this actor before starting.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' show Database;

import '../lib/atserver.dart';
import '../lib/group_ratchet.dart';
import '../lib/keystore.dart';
import '../lib/openssl.dart';
import '../lib/transport.dart';
import '../lib/wire.dart';

// ── Verbose-but-concise log ────────────────────────────────────────────────

late final DateTime _t0;
String _ts() {
  final dt = DateTime.now().difference(_t0).inMilliseconds / 1000.0;
  return '[t+${dt.toStringAsFixed(3)}]';
}

String _ansi(String s, int code) => '\x1B[${code}m$s\x1B[0m';
String _dim(String s) => _ansi(s, 90);
String _cyan(String s) => _ansi(s, 36);
String _yellow(String s) => _ansi(s, 33);
String _green(String s) => _ansi(s, 32);
String _magenta(String s) => _ansi(s, 35);
String _red(String s) => _ansi(s, 31);

String _selfStr = '';

void logLine(String verb, String summary, [String? kv]) {
  print(
      '${_dim(_ts())}  ${_yellow(_selfStr.padRight(15))}  ${verb.padRight(6)}  ${summary.padRight(38)}${kv == null ? '' : _dim(kv)}');
}

void logRatchet(String summary, [String? kv]) =>
    print(
        '${_dim(_ts())}  ${_yellow(_selfStr.padRight(15))}  ${_cyan('ratch')}   ${summary.padRight(38)}${kv == null ? '' : _dim(kv)}');

void logEvent(String summary, [String? kv]) =>
    print(
        '${_dim(_ts())}  ${_yellow(_selfStr.padRight(15))}  ${_magenta('evt')}     ${summary.padRight(38)}${kv == null ? '' : _dim(kv)}');

void logErr(String msg) =>
    print('${_dim(_ts())}  ${_yellow(_selfStr.padRight(15))}  ${_red('err')}     $msg');

void logChat(String fromName, String fromDevice, String body) {
  print(
      '${_dim(_ts())}  ${_yellow(_selfStr.padRight(15))}  ${_green('chat')}    ${_green('<$fromName/$fromDevice> $body')}');
}

void usage() {
  print('Usage: dart run bin/chat.dart <name>:<device> <peer_name> [--reset]');
  exit(1);
}

Future<void> main(List<String> args) async {
  _t0 = DateTime.now();
  if (args.length < 2) usage();
  final selfSpec = args[0];
  final peer = args[1].toLowerCase();
  final reset = args.contains('--reset');
  final colonIdx = selfSpec.indexOf(':');
  if (colonIdx <= 0) {
    print('first arg must be <name>:<device>');
    exit(1);
  }
  final selfName = selfSpec.substring(0, colonIdx).toLowerCase();
  final selfDevice = selfSpec.substring(colonIdx + 1).toLowerCase();
  if (selfName == peer) usage();
  _selfStr = '$selfName/$selfDevice';

  if (reset) {
    for (final f in [
      '$selfName-${selfDevice}_keystore.json',
      '${selfName}_store.db',
      '${selfName}_store.db-journal',
      '${selfName}_store.db-shm',
      '${selfName}_store.db-wal',
    ]) {
      final fh = File(f);
      if (await fh.exists()) await fh.delete();
    }
    logEvent('--reset: cleared local state');
  }

  print('═══ pq mls demo — $_selfStr ↔ $peer ═══');
  final c = Crypto.load();
  logEvent('openssl loaded',
      'ml-kem-768 + ml-dsa-65 + hpke + aes-gcm + hkdf via libcrypto');

  // ── 1. Load keystore + open own atServer DB ─────────────────────────────
  final ks = await Keystore.loadOrGenerate(c, selfName, selfDevice);
  logEvent('keystore',
      ks.ownGroup == null ? 'identity loaded, no group yet' : 'identity + ownGroup epoch=${ks.ownGroup!.epoch} members=${ks.ownGroup!.members.length}');

  final store = Store.open(selfName);
  logEvent('store', '${selfName}_store.db (WAL)');

  // Publish own identity bundle.
  final bundleJson = jsonEncode({
    'deviceId': selfDevice,
    'mlDsaPk': base64Encode(ks.identity.mlDsaPk),
    'hpkeKemPk': base64Encode(ks.identity.hpkeKemPk),
  });
  put(store, 'bundle.$selfDevice.pqdemo', bundleJson);
  logEvent('put record',
      'bundle.$selfDevice.pqdemo  (${bundleJson.length}B)');

  final ratchet = GroupRatchet(c, ks.identity);

  // ── 2. Decide group role ────────────────────────────────────────────────
  if (ks.ownGroup == null) {
    // Check own store for an existing group.
    final existing = get(store, 'group.pqdemo');
    if (existing != null) {
      // Someone else (same name) is already running. Request to join.
      final req = JoinRequest(
        groupId: selfName,
        fromDevice: selfDevice,
        mlDsaPk: ks.identity.mlDsaPk,
        hpkeKemPk: ks.identity.hpkeKemPk,
      );
      notifyBroadcast(store.db, selfName, selfDevice, 'join_request',
          jsonEncode(req.toJson()));
      logRatchet('join_request broadcast',
          'awaiting Welcome from an existing $selfName member');
    } else {
      // No group yet — bootstrap solo.
      ks.ownGroup = ratchet.bootstrap(selfName);
      put(store, 'group.pqdemo', ks.ownGroup!.toPublicInfo().encode());
      await ks.save();
      logRatchet('bootstrap solo',
          'epoch=0 members=1 extPk=${hex(ks.ownGroup!.externalHpkePk, maxBytes: 4)}');
    }
  } else {
    logRatchet('resume',
        'epoch=${ks.ownGroup!.epoch} members=${ks.ownGroup!.members.length}');
  }

  // ── 3. Open peer store + cache peer's group public info ─────────────────
  Database? peerDb;
  PeerCache peerCache = ks.peerCaches[peer] ?? PeerCache();
  ks.peerCaches[peer] = peerCache;

  Future<void> refreshPeerInfo() async {
    final f = File('${peer}_store.db');
    if (!await f.exists()) {
      return;
    }
    peerDb ??= Store.openPeer(peer);
    final raw = peekPeer(peerDb!, 'group.pqdemo');
    if (raw == null) return;
    final info = GroupPublicInfo.decode(raw);
    final prev = peerCache.groupInfo;
    if (prev == null || prev.epoch != info.epoch) {
      peerCache.groupInfo = info;
      await ks.save();
      logEvent('peer group',
          '$peer epoch=${info.epoch} members=${info.members.length} extPk=${hex(info.externalHpkePk, maxBytes: 4)}');
    }
  }

  // Initial peer-info wait (up to 120s).
  logEvent('waiting', 'for ${peer}_store.db + group.pqdemo');
  for (var i = 0; i < 240; i++) {
    await refreshPeerInfo();
    if (peerCache.groupInfo != null) break;
    await Future.delayed(const Duration(milliseconds: 500));
  }
  if (peerCache.groupInfo == null) {
    logErr('timed out waiting for peer group info; will keep retrying in background');
  }

  // ── 4. Inbox polling loop ───────────────────────────────────────────────
  Timer.periodic(const Duration(milliseconds: 500), (_) async {
    await refreshPeerInfo();
    final rows = pollInbox(store, selfDevice);
    for (final row in rows) {
      try {
        final v = jsonDecode(row.value) as Map<String, dynamic>;
        switch (row.msgType) {
          case 'commit':
            await _handleCommit(c, ks, ratchet, store, peerDb, Commit.fromJson(v));
            break;
          case 'welcome':
            await _handleWelcome(c, ks, ratchet, store, Welcome.fromJson(v));
            break;
          case 'app':
            _handleApp(c, ks, ratchet, AppMessage.fromJson(v));
            break;
          case 'external_app':
            await _handleExternalApp(c, ks, ratchet, ExternalAppMessage.fromJson(v));
            break;
          case 'join_request':
            await _handleJoinRequest(c, ks, ratchet, store, JoinRequest.fromJson(v));
            break;
          default:
            logEvent('inbox', 'unknown msg_type=${row.msgType}');
        }
      } catch (e) {
        logErr('inbox row id=${row.id} type=${row.msgType}: $e');
      }
    }
  });

  // ── 5. Stdin loop ───────────────────────────────────────────────────────
  print(_dim('\nType messages to send. /quit, /remove <id>, /heartbeat (manual PCS rotation).\n'));
  final stdinLines =
      stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final raw in stdinLines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line == '/quit') break;
    if (line.startsWith('/add ')) {
      logErr('manual /add not implemented (devices join via join_request flow)');
      continue;
    }
    if (line.startsWith('/remove ')) {
      final target = line.substring('/remove '.length).trim();
      if (ks.ownGroup == null) {
        logErr('no group to remove from');
        continue;
      }
      await _doRemove(c, ks, ratchet, store, target);
      continue;
    }
    if (line == '/heartbeat') {
      if (ks.ownGroup == null) {
        logErr('no group to heartbeat');
        continue;
      }
      await _doHeartbeat(c, ks, ratchet, store, manual: true);
      continue;
    }
    if (ks.ownGroup == null) {
      logErr('cannot send yet — still waiting to join $selfName\'s group');
      continue;
    }
    await _doSend(c, ks, ratchet, store, peerDb, peer, peerCache, line);
    // Auto PCS heartbeat: if I'm the lowest-deviceId member and we've
    // accumulated enough in-epoch traffic, rotate the group secret.
    if (ks.ownGroup!.shouldHeartbeat(ks.identity.deviceId)) {
      await _doHeartbeat(c, ks, ratchet, store);
    }
  }
}

// ── Handlers ───────────────────────────────────────────────────────────────

Future<void> _handleCommit(Crypto c, Keystore ks, GroupRatchet r, Store store,
    Database? peerDb, Commit commit) async {
  if (commit.groupId != ks.identity.name) {
    logEvent('commit (ignored)', 'groupId=${commit.groupId} not ours');
    return;
  }
  if (commit.signerDevice == ks.identity.deviceId) {
    // Our own broadcast — we already applied it in-process.
    return;
  }
  if (ks.ownGroup != null && commit.newEpoch <= ks.ownGroup!.epoch) {
    // Already at or past this epoch (probably we co-authored it).
    return;
  }
  if (ks.ownGroup == null) {
    logEvent('commit (queued)',
        'no own group yet; epoch=${commit.newEpoch} signer=${commit.signerDevice}');
    return;
  }
  final newState = r.applyCommit(ks.ownGroup!, commit);
  ks.ownGroup = newState;
  put(store, 'group.pqdemo', newState.toPublicInfo().encode());
  await ks.save();
  logRatchet(
      'commit applied',
      'epoch=${newState.epoch} members=${newState.members.length} '
          'add=${commit.additions.length} rem=${commit.removals.length} '
          'signer=${commit.signerDevice}');
}

Future<void> _handleWelcome(Crypto c, Keystore ks, GroupRatchet r, Store store,
    Welcome welcome) async {
  if (welcome.groupId != ks.identity.name) return;
  if (welcome.targetDevice != ks.identity.deviceId) return;
  final newState = r.applyWelcome(welcome);
  ks.ownGroup = newState;
  // Publish the now-current group info from our perspective.
  put(store, 'group.pqdemo', newState.toPublicInfo().encode());
  await ks.save();
  logRatchet(
      'welcome accepted',
      'epoch=${newState.epoch} members=${newState.members.length} '
          'signer=${welcome.signerDevice}');
}

void _handleApp(Crypto c, Keystore ks, GroupRatchet r, AppMessage msg) {
  if (msg.senderDevice == ks.identity.deviceId) {
    // our own broadcast — skip
    return;
  }
  if (ks.ownGroup == null) return;
  try {
    final pt = r.receiveApp(ks.ownGroup!, msg);
    logChat(ks.identity.name, msg.senderDevice, pt);
  } catch (e) {
    logErr('app msg #${msg.messageIndex} from ${msg.senderDevice} epoch=${msg.epoch}: $e');
  }
}

Future<void> _handleExternalApp(Crypto c, Keystore ks, GroupRatchet r,
    ExternalAppMessage msg) async {
  if (msg.toGroupId != ks.identity.name) return;
  if (ks.ownGroup == null) {
    logEvent('external (queued)', 'no own group yet');
    return;
  }
  final peerCache = ks.peerCaches.putIfAbsent(msg.fromName, () => PeerCache());
  try {
    final res = r.receiveExternal(
      state: ks.ownGroup!,
      msg: msg,
      trustedSignerPks: peerCache.trustedSignerPks,
    );
    if (res.firstSeenSigner) {
      peerCache.trustedSignerPks[msg.fromDevice] = msg.signerPk;
      await ks.save();
      logEvent('TOFU pin',
          '${msg.fromName}/${msg.fromDevice} signer pk pinned');
    }
    logChat(msg.fromName, msg.fromDevice, res.plaintext);
  } catch (e) {
    logErr('external msg from ${msg.fromName}/${msg.fromDevice}: $e');
  }
}

Future<void> _handleJoinRequest(Crypto c, Keystore ks, GroupRatchet r,
    Store store, JoinRequest req) async {
  if (req.groupId != ks.identity.name) return;
  if (req.fromDevice == ks.identity.deviceId) return; // our own request
  if (ks.ownGroup == null) {
    logEvent('join_request (skipped)',
        'we are not a member ourselves; another existing member will respond');
    return;
  }
  // Only the lowest-deviceId current member commits — avoids race.
  final lowest = ks.ownGroup!.members
      .map((m) => m.deviceId)
      .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
  if (lowest != ks.identity.deviceId) {
    logEvent('join_request (defer)',
        'leader is $lowest; not us');
    return;
  }
  // Avoid duplicate add if already a member.
  if (ks.ownGroup!.members.any((m) => m.deviceId == req.fromDevice)) {
    logEvent('join_request (dup)',
        '${req.fromDevice} already a member');
    return;
  }
  final newMember = MemberDesc(
    deviceId: req.fromDevice,
    mlDsaPk: req.mlDsaPk,
    hpkeKemPk: req.hpkeKemPk,
  );
  logRatchet('commit (adding)',
      '${req.fromDevice}; current epoch=${ks.ownGroup!.epoch}');
  final cw = r.commit(current: ks.ownGroup!, additions: [newMember]);
  ks.ownGroup = cw.newState;
  put(store, 'group.pqdemo', cw.newState.toPublicInfo().encode());
  await ks.save();
  // Broadcast the Commit so all current members (incl. us) advance epoch.
  // Note: our own state was already advanced in-process; broadcasting still
  // lets others advance, but we shouldn't re-apply it. Track via consumed_by
  // on broadcast inbox — we'll mark ourselves consumed.
  notifyBroadcast(store.db, ks.identity.name, ks.identity.deviceId, 'commit',
      jsonEncode(cw.commit.toJson()));
  for (final w in cw.welcomes) {
    notifyDevice(store.db, w.targetDevice, ks.identity.name,
        ks.identity.deviceId, 'welcome', jsonEncode(w.toJson()));
  }
  logRatchet(
      'commit broadcast',
      'epoch=${cw.newState.epoch} wraps=${cw.commit.wraps.length} welcomes=${cw.welcomes.length}');
}

// ── Send (in-group + external) ─────────────────────────────────────────────

Future<void> _doSend(
    Crypto c,
    Keystore ks,
    GroupRatchet r,
    Store store,
    Database? peerDb,
    String peer,
    PeerCache peerCache,
    String line) async {
  // 1. In-group broadcast (so our own other devices see it).
  final appMsg = r.sendApp(ks.ownGroup!, line);
  notifyBroadcast(store.db, ks.identity.name, ks.identity.deviceId, 'app',
      jsonEncode(appMsg.toJson()));
  logRatchet('send (in-group)',
      'epoch=${appMsg.epoch} msgIdx=${appMsg.messageIndex} size=${appMsg.sizeBytes}B');

  // 2. External send to the peer name's group.
  if (peerDb == null || peerCache.groupInfo == null) {
    logErr('cannot external-send: peer group info unknown');
    print('  ${_green('[you]')} $line');
    return;
  }
  final ext = r.sendExternal(
    peerInfo: peerCache.groupInfo!,
    fromName: ks.identity.name,
    plaintext: line,
  );
  notifyBroadcast(peerDb, ks.identity.name, ks.identity.deviceId,
      'external_app', jsonEncode(ext.toJson()));
  logRatchet(
      'send (external)',
      '→ $peer/epoch=${ext.observedEpoch}  enc=${ext.enc.length}B '
          'ct=${ext.ct.length}B sig=${ext.signature.length}B');
  await ks.save();

  print('  ${_green('[you]')} $line');
}

// ── /heartbeat — empty Commit, rotates group_secret + externalHpkeSk ───────

Future<void> _doHeartbeat(Crypto c, Keystore ks, GroupRatchet r, Store store,
    {bool manual = false}) async {
  final before = ks.ownGroup!.epoch;
  final cw = r.commit(current: ks.ownGroup!); // no additions, no removals
  ks.ownGroup = cw.newState;
  put(store, 'group.pqdemo', cw.newState.toPublicInfo().encode());
  await ks.save();
  notifyBroadcast(store.db, ks.identity.name, ks.identity.deviceId, 'commit',
      jsonEncode(cw.commit.toJson()));
  logRatchet(manual ? 'commit (heartbeat /cmd)' : 'commit (heartbeat auto)',
      'epoch=$before→${cw.newState.epoch} wraps=${cw.commit.wraps.length} PCS-rotated');
}

// ── /remove implementation ─────────────────────────────────────────────────

Future<void> _doRemove(Crypto c, Keystore ks, GroupRatchet r, Store store,
    String target) async {
  if (!ks.ownGroup!.members.any((m) => m.deviceId == target)) {
    logErr('not a member: $target');
    return;
  }
  final cw = r.commit(current: ks.ownGroup!, removals: [target]);
  ks.ownGroup = cw.newState;
  put(store, 'group.pqdemo', cw.newState.toPublicInfo().encode());
  await ks.save();
  notifyBroadcast(store.db, ks.identity.name, ks.identity.deviceId, 'commit',
      jsonEncode(cw.commit.toJson()));
  logRatchet('commit (remove)',
      '$target  epoch=${cw.newState.epoch} wraps=${cw.commit.wraps.length}');
}

// expose hex from openssl.dart via a local shim (we already export it)
String hexLocal(Uint8List b) => hex(b);
