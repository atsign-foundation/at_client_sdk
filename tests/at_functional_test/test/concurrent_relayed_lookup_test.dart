// ignore_for_file: avoid_print
// Two cross-atSign lookups in flight at once on one atServer get each other's
// answers.
//
// ⛔ @Skip, deliberately: every atServer build carrying the defect fails this,
// so leaving it live would make the pack permanently red. Run it by hand:
//
//   cd tests/at_functional_test
//   dart test test/concurrent_relayed_lookup_test.dart --concurrency=1 \
//     --run-skipped
//
// ## What it shows
//
// Four sockets on @bob🛠 each ask @bob🛠's atServer for a different record
// belonging to @alice🛠, all at the same moment, and repeat. Measured
// 2026-08-24 against `at_virtual_env:local`, with @alice🛠's atServer under
// concurrent write load:
//
//   width 1 (one lookup in flight): 120 requests, 120 ok
//   width 4:                        480 requests,  41 ok
//                                   35 answered with ANOTHER record's content
//                                   404 refused or timed out
//
// The 35 are the dangerous ones: no exception is raised, and the caller is
// handed a well-formed record that is not the one it asked for. The refusals
// name the same event from the other side — 250 `AT0011-Internal server
// exception : Connection failed to @alice🛠`, 18 `AT0023-Timeout waiting for
// response`, 16 `AT0003-Invalid syntax` in reply to a `lookup:all:` this same
// test sends cleanly 120 times in the width-1 arm.
//
// ## Why
//
// An atServer relays a `lookup:` for another atSign's record through
// `AtCacheManager`, which holds ONE `DummyInboundConnection` and passes it to
// `OutboundClientManager.getClient(otherAtSign, thatConnection)`.
// `OutboundClientPool.get` matches a pooled client with
// `client.inboundConnection.equals(...)`, and `DummyInboundConnection.equals`
// answers true for any other `DummyInboundConnection` — so every relayed
// lookup to a given atSign, from every client connection, is handed the same
// `OutboundClient` and therefore the same socket.
//
// `OutboundClient.lookUp` then writes its request and reads whatever the
// listener queues next, with no mutex across the pair: concurrent callers
// interleave their commands on the wire and take each other's responses.
// (Read in at_server at a0deee69, the revision `at_virtual_env:local` was
// built from, and unchanged on its trunk at a37e3e3b.) The client half of the
// same conversation does hold such a lock — `AtLookupImpl._process` keeps
// `requestResponseMutex` across `_sendCommand` + `messageListener.read`.
//
// ## The control
//
// The width-1 arm is the same sockets, the same commands and the same
// background load, with only one lookup in flight. It must be clean; anything
// in it is a broken probe rather than a finding.
@Skip('reproduces an open atServer defect; run by hand, see the header')
@Tags(['pq'])
library;

import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  final atSigns = <String>[
    ConfigUtil.getYaml()['atSign']['firstAtSign'] as String,
    ConfigUtil.getYaml()['atSign']['secondAtSign'] as String,
  ];
  final alice = atSigns[0];
  final bob = atSigns[1];
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final ns = 'xp$runId';

  /// How many sockets ask concurrently, each for its OWN record.
  const fanOut = int.fromEnvironment('fanOut', defaultValue: 4);
  const rounds = int.fromEnvironment('rounds', defaultValue: 30);
  const controlRounds = 60;

  /// Record `i` is one repeated digit and its own length, so which record came
  /// back is readable from the payload with no bookkeeping.
  String markerOf(int i) => '$i' * (400 * (i + 1) + 137);
  String signatureOf(int i) => '$i' * 8;

  late AtClient aliceClient;
  late AtClient bobClient;
  final bobSockets = <RemoteSecondary>[];
  late RemoteSecondary aliceChurn;

  Future<AtClient> primaryFor(String name, String atSign) async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final storage = 'test/hive/relayprobe/$name';
    final preference = TestUtils.getPreference(atSign)
      ..hiveStoragePath = storage
      ..commitLogPath = storage;
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, ns, preference,
        atKeysIo: keysIo, atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(manager.atClient, atSign);
    return manager.atClient;
  }

  setUpAll(() async {
    aliceClient = await primaryFor('alice', alice);
    bobClient = await primaryFor('bob', bob);
    // Raw `update:`, so nothing is encrypted and what the atServer holds is the
    // literal marker. Whatever comes back is the record, not a decryption of it.
    final writer = (aliceClient as AtClientImpl).getRemoteSecondary()!;
    for (var i = 0; i < fanOut; i++) {
      await writer.executeCommand(
          'update:$bob:probe$i.$ns$alice ${markerOf(i)}\n',
          auth: true);
    }
    for (var i = 0; i < fanOut; i++) {
      bobSockets.add((bobClient as AtClientImpl).buildRemoteSecondary());
    }
    aliceChurn = (aliceClient as AtClientImpl).buildRemoteSecondary();
    print('##X## $fanOut sockets, ns=$ns');
  });

  /// One round: [width] sockets each ask for their own record, together.
  ///
  /// Nothing throws out of here — a refusal is a result, and the shapes are
  /// counted rather than aborted on, because the silent crossings are the
  /// finding and an early throw would hide them.
  Future<List<String>> oneRound(int width) async {
    Future<String> ask(int i) async {
      try {
        final got =
            '${await bobSockets[i].executeCommand('lookup:all:probe$i.$ns$alice\n', auth: true)}';
        if (got.contains(signatureOf(i))) return 'ok';
        for (var j = 0; j < fanOut; j++) {
          if (j != i && got.contains(signatureOf(j))) {
            return 'CROSSED probe$i answered with probe$j';
          }
        }
        return 'ODD ${got.substring(0, got.length > 60 ? 60 : got.length)}';
      } catch (e) {
        final flat = '$e'.replaceAll('\n', ' ');
        // Bucket by which failure it is, because the mix between them is the
        // finding rather than the total. ⚠️ Match the MESSAGE, not the `ATnnnn`
        // code: the codes are what the atServer puts on the wire, and
        // at_client has already translated them into text by the time a caller
        // sees the exception. A regex for `AT\d{4}` here matches nothing and
        // buckets every refusal as "other" — measured, 100 of them.
        final code = flat.contains('Invalid syntax')
            ? 'AT0003-invalid-syntax'
            : flat.contains('Timeout waiting for response')
                ? 'AT0023-timeout'
                : flat.contains('Internal server exception')
                    ? 'AT0011-internal'
                    : 'other';
        return 'REFUSED-$code ${flat.substring(0, flat.length > 60 ? 60 : flat.length)}';
      }
    }

    return await Future.wait([for (var i = 0; i < width; i++) ask(i)]);
  }

  Future<Map<String, int>> arm(String label, int width, int howMany) async {
    final tally = <String, int>{};
    final examples = <String>[];
    for (var r = 0; r < howMany; r++) {
      for (final outcome in await oneRound(width)) {
        final bucket = outcome.split(' ').first;
        tally[bucket] = (tally[bucket] ?? 0) + 1;
        if (bucket != 'ok' && examples.length < 6)
          examples.add('round $r: $outcome');
      }
    }
    print('##X## $label width=$width '
        'requests=${tally.values.fold(0, (a, b) => a + b)} $tally');
    for (final e in examples) {
      print('##X##   $e');
    }
    return tally;
  }

  test('concurrent cross-atSign lookups are answered pairwise', () async {
    // @alice🛠's atServer under write load for both arms, so the only thing
    // that differs between them is how many lookups are in flight.
    var churning = true;
    unawaited(() async {
      var n = 0;
      while (churning) {
        try {
          await aliceChurn.executeCommand(
              'update:$bob:churn${n++ % 8}.$ns$alice ${'z' * 3000}\n',
              auth: true);
        } catch (_) {
          // The churn is load, not a measurement.
        }
      }
    }());

    final control = await arm('WIDTH-1 (control)', 1, controlRounds);
    final wide = await arm('WIDTH-$fanOut', fanOut, rounds);
    churning = false;

    expect(control['ok'], controlRounds,
        reason: 'one lookup at a time must always be answered with the record '
            'it asked for; a failure here is a broken probe, not a finding');
    expect(wide['ok'], rounds * fanOut,
        reason: 'a cross-atSign lookup was answered with another request\'s '
            'record, refused as malformed, or left waiting — concurrent '
            'relays share one outbound connection with no request/response '
            'pairing');
  }, timeout: Timeout(Duration(minutes: 20)));
}
