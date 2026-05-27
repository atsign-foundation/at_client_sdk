// Interactive two-terminal PQ chat demo.
//
// Run:
//   Terminal 1:  dart run bin/chat.dart alice bob
//   Terminal 2:  dart run bin/chat.dart bob alice
//
// Each party persists a JSON keystore (<name>_keystore.json) and a SQLite
// store (<name>_store.db) in the current working directory. The SQLite
// inbox/records tables stand in for a real network — peers write to each
// other's inbox table to deliver encrypted messages.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../lib/keystore.dart';
import '../lib/ratchet.dart';
import '../lib/store.dart';
import '../lib/transport.dart';
import '../lib/wire.dart';

void usage() {
  print('Usage: dart run bin/chat.dart <self> <peer>');
  print('  e.g.  dart run bin/chat.dart alice bob');
  exit(1);
}

void log(String s) => print('\x1B[90m[$s]\x1B[0m');
void ratchetLog(String s) => print('\x1B[36m[ratchet] $s\x1B[0m');

Future<void> main(List<String> args) async {
  if (args.length < 2) usage();
  final self = args[0].toLowerCase();
  final peer = args[1].toLowerCase();
  if (self.isEmpty || peer.isEmpty || self == peer) usage();

  print('═══ PQ chat demo ($self → $peer) ═══\n');

  // 1. Load or generate local keystore.
  final ks = await Keystore.loadOrGenerate(self);
  log('keystore loaded for "$self"  ('
      'identity=${ks.identity.ikDhPk.length}B pk, '
      '${ks.ratchets.length} ratchet(s) cached)');

  // 2. Open own SQLite store.
  final store = Store.open(self);
  log('opened ${self}_store.db');

  // 3. Publish own pre-key bundle.
  final bundleJson = jsonEncode(ks.identity.publicBundle());
  put(store, 'prekeyBundle', bundleJson);
  log('put "prekeyBundle" → records (${bundleJson.length}B)');

  // 4. Open peer's DB and wait for their bundle.
  Database? peerDb;
  PeerBundle? peerBundle;
  log('waiting for "$peer"\'s prekeyBundle…');
  for (var i = 0; i < 240; i++) {
    final f = File('${peer}_store.db');
    if (await f.exists()) {
      peerDb ??= Store.openPeer(peer);
      final v = peekPeer(peerDb, 'prekeyBundle');
      if (v != null) {
        peerBundle = PeerBundle.fromJson(jsonDecode(v) as Map<String, dynamic>);
        break;
      }
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (i > 0 && i % 10 == 0) log('  still waiting for $peer…');
  }
  if (peerBundle == null || peerDb == null) {
    print('Timed out waiting for $peer\'s bundle.');
    exit(1);
  }
  log('peeked "$peer"/prekeyBundle');

  // 5. Verify peer's SPK signature.
  final sigOk = await peerBundle.verifySignature();
  if (!sigOk) {
    print('[ABORT] $peer\'s SPK signature is INVALID.');
    exit(1);
  }
  log('verified $peer\'s SPK signature  ✓');

  // 6. Decide initiator vs responder by lexicographic name ordering.
  //    Tiebreaker prevents both sides from initiating simultaneously.
  final iAmInitiator = self.compareTo(peer) < 0;
  RatchetState? ratchet = ks.ratchets[peer];
  if (ratchet == null) {
    if (iAmInitiator) {
      ratchet = await pqxdhInitiate(ks.identity, peerBundle);
      ks.ratchets[peer] = ratchet;
      await ks.save();
      ratchetLog('PQXDH initiated (role: INITIATOR); first send carries init payload');
    } else {
      ratchetLog('waiting as RESPONDER; will reconstruct on first incoming init msg');
    }
  } else {
    ratchetLog('resumed existing ratchet state '
        '(role: ${iAmInitiator ? "INITIATOR" : "RESPONDER"}, '
        'sendN=${ratchet.sendN} recvN=${ratchet.recvN})');
  }

  print('\nType to send. Ctrl+C to quit.\n');

  // 7. Inbox polling loop.
  Timer.periodic(const Duration(milliseconds: 500), (_) async {
    final rows = pollInbox(store);
    for (final row in rows) {
      if (row.fromName != peer) continue;
      try {
        final msg = WireMessage.fromEncoded(row.value);
        // Responder side: first message arrives with isInit and we have no
        // ratchet state yet (cold start before anyone published).
        if (msg.isInit && ks.ratchets[peer] == null) {
          final s = await pqxdhRespond(ks.identity, msg);
          ks.ratchets[peer] = s;
          ratchetLog('PQXDH responded — reconstructed shared rootKey from first msg');
        }
        final r = await receiveMessage(ks.ratchets[peer]!, msg);
        await ks.save();
        switch (r.status) {
          case 'dh':
            ratchetLog('DH ratchet step on receive');
            break;
          case 'kem':
            ratchetLog('KEM ratchet receive (decapsed peer\'s kemCt)');
            break;
          case 'dh+kem':
            ratchetLog('DH + KEM ratchet receive');
            break;
        }
        print('[$peer → $self] ${r.plaintext}');
      } catch (e) {
        log('decrypt error on inbox row ${row.id}: $e');
      }
    }
  });

  // 8. Stdin loop.
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final st = ks.ratchets[peer];
    if (st == null) {
      log('cannot send yet — waiting for $peer\'s first message (we are RESPONDER)');
      continue;
    }
    final r = await sendMessage(st, line);
    final payload = r.msg.toEncoded();
    notifyPeer(peerDb, self, payload);
    await ks.save();
    switch (r.status) {
      case 'init':
        ratchetLog('sent init msg (carries PQXDH init payload, '
            '${r.msg.sizeBytes}B)');
        break;
      case 'kem':
        ratchetLog('KEM ratchet step on send (${r.msg.sizeBytes}B)');
        break;
    }
    print('[you] $line');
  }
}
