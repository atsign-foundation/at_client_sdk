// ignore_for_file: implementation_imports, avoid_print, experimental_member_use
// A reproduction harness for an OPEN defect, not a passing test.
//
// ⛔ @Skip, deliberately: it reproduces roughly one cycle in five, so leaving
// it live would make the functional pack red at that rate. Run it by hand:
//
//   cd tests/at_functional_test
//   dart test test/pq_conveyance_at_value_address_test.dart --concurrency=1
//
// ⚠️ Recycle the virtualenv first. One that has been up ~2 hours starts
// failing unrelated tests on the 30s default timeout, and a batch that begins
// timing out is spent rather than evidence.
//
// ## What it shows
//
// A conveyance payload sits at a VALUE record's address. Captured at the
// moment of the read rather than afterwards, 2026-08-24:
//
//   asked=@bob:rate28.<ns>@alice   got=@bob:rate28.<ns>@alice
//   len=1564  providerId: at/nskey/XWING/AES/GCM, recipientKind: nskey
//   healthy:  len=6204  providerId: at/symmetric/AES/GCM
//
// The key asked for is the key returned, so the read is faithful. What sits at
// that address is a 1564-byte X-Wing sealed envelope carrying a content key,
// stamped with the CONVEYANCE provider — so `get` routes to
// `NskeyProvider.decrypt`, which returns the content key it is designed to
// return. The 44-character value an app sees is the correct decryption of the
// wrong record.
//
// ## The condition
//
// Several content keys alive for one `(nskeyOwner, namespace)` scope. A CK is
// scoped that way, so a fresh namespace per cycle guarantees exactly one — and
// 200 cycles built that way never failed. This file uses ONE namespace with
// three senders, each cutting its own CK.
//
// ## Ruled out, with evidence — do not re-derive
//
// - **the read path**: the key requested is the key returned, and a
//   CONVEYANCE-FOR-VALUE probe inside `GetResponseTransformer` never fired
// - **transport**: 200 cycles of concurrent reads, three enrollments, a live
//   monitor and interleaved `_apsk` lookups, all clean; no timeouts, no socket
//   errors, and no AT0014 in any failing run
// - **the shared AtKey object** between the put and the get: 150 cycles with
//   it, clean
// - **concurrent nskey seeding**: serialising provisioning did not help
//   (non-ok 74%, 88%, 98%, 82% across four serialised runs)
//
// ## The control this file carries
//
// Every read records which provider it routed through, and the test FAILS if
// any cycle routed legacy: a legacy cycle never touches the content-key path,
// so counting it would inflate the denominator with attempts that could not
// have failed. That mattered — an early run read as 1-in-50 while a third of
// its cycles had gone legacy, and the real figure was 1-in-34.
@Skip('reproduces an open defect ~1 cycle in 5; run by hand, see the header')
@Tags(['pq'])
library;

import 'dart:convert' show jsonDecode;

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'dart:async' show Completer, StreamSubscription;

import 'package:at_client/at_client.dart';
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_client/src/service/notification_service_impl.dart'
    show NotificationServiceImpl;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show EnrolledClient, enrolAndAuthenticate;
import 'package:test/test.dart';

import 'test_utils.dart';

/// How many put/get cycles to run. Each uses its OWN namespace, so the content
/// key is never cached from a previous iteration and every read resolves it
/// through a nested `__ck` conveyance read — the path the live failure takes.
const iterations = 50;

/// Whether the same [AtKey] object is handed to both the put and the get.
///
/// The grid does this, and it is the suspected vector: the put pipeline stamps
/// `atKey.metadata.appMetadata` in place, and `GetResponseTransformer` gives
/// the returned `AtValue` the *same* `Metadata` object it puts on the key — so
/// anything still holding that key can change what a completed read appears to
/// have returned. Flip to false for the control arm.
const shareAtKeyObject = bool.fromEnvironment('shareKey', defaultValue: true);

/// The grid signs an envelope per cell and verifies it three times, each
/// verification fetching the signer's `_apsk` over the wire. Those lookups
/// interleave with the value read, and the probe had none of them.
class _ProbeSigner with ApkamSigning, EnvelopeSigning {
  _ProbeSigner(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('rateProbeEnvelope');

  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;
}

void main() {
  const rootDomain = 'vip.ve.atsign.zone';
  final atSigns = <String>[
    ConfigUtil.getYaml()['atSign']['firstAtSign'] as String,
    ConfigUtil.getYaml()['atSign']['secondAtSign'] as String,
  ];
  final sender = atSigns[0];
  final receiver = atSigns[1];
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  // ⚠️ ONE namespace for every cycle, not one each. A content key is scoped to
  // (nskeyOwner, namespace), so a fresh namespace per cycle guarantees exactly
  // ONE CK is ever alive for a scope — and 200 cycles built that way found
  // nothing. The grid has three senders writing into one namespace, each
  // cutting its own CK, so several coexist and a read must pick by ckKid.
  // That is the condition being added.
  final sharedNs = 'rp${runId}s';
  final namespaces = [for (var i = 0; i < iterations; i++) sharedNs];

  late EnrolledClient senderCell;
  final senderSiblings = <EnrolledClient>[];
  late EnrolledClient receiverCell;
  // Siblings of [receiverCell] on the same atSign. The grid has three receiver
  // enrollments and reproduces; this probe had one and did not. A content key
  // is conveyed PER ENROLLMENT, so three readers means three `__ck` records
  // carrying the same CK, and a resolve that picks up a sibling's is exactly
  // the shape of the failure.
  final receiverSiblings = <EnrolledClient>[];
  // ignore: unused_local_variable
  StreamSubscription<AtNotification>? monitorSub;

  Future<AtClient> primaryFor(String name, String atSign, String ns) async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final storage = 'test/hive/ratesprobe/$name';
    final preference = TestUtils.getPreference(atSign)
      ..hiveStoragePath = storage
      ..commitLogPath = storage;
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, ns, preference,
        atKeysIo: keysIo,
        atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(manager.atClient, atSign);
    await AtClientSecretSharing.forClient(manager.atClient).register();
    return manager.atClient;
  }

  setUpAll(() async {
    print('##RATE## shareAtKeyObject=$shareAtKeyObject '
        'iterations=$iterations');
    final grants = {sharedNs: 'rw'};

    Future<EnrolledClient> cell(String name, String atSign, PqPosture posture) async {
      final approver = await primaryFor('ap-$name', atSign, namespaces.first);
      final storage = 'test/hive/ratesprobe/$name';
      final enrolled = await enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespaces.first,
        preference: TestUtils.getPreference(atSign, posture: posture)
          ..hiveStoragePath = storage
          ..commitLogPath = storage,
        rootDomain: rootDomain,
        rootPort: TestUtils.rootServerPort,
        deviceName: '$name-$runId',
        namespaces: grants,
        atKeysIo: InMemoryAtKeysIo(),
      );
      // ⚠️ SERIALISED. Awaiting each client's startup before building the next
      // means no two enrollments seed the namespace concurrently. Built the
      // other way — every cell created, then every startup awaited — runs came
      // out 0% to 92% non-ok, and a run's fate was settled during provisioning
      // rather than per read.
      await (enrolled.client as AtClientImpl).pqBootstrap!.startupComplete;
      return enrolled;
    }

    senderCell = await cell('snd', sender, PqPosture.pqActive);
    // ⚠️ pqActive, NOT pqReady. `pqReady.writesPqByDefault` is false, so a
    // pqReady sender writes LEGACY — 16 of 50 cycles took that path and never
    // touched the content-key machinery at all. Every sender must be pqActive
    // or the denominator is not what it looks like.
    senderSiblings.add(await cell('snd2', sender, PqPosture.pqActive));
    senderSiblings.add(await cell('snd3', sender, PqPosture.pqActive));
    receiverCell = await cell('rcv', receiver, PqPosture.pqReady);
    // Two more enrollments on the receiving atSign, at the other postures, so
    // the namespace key is conveyed to three holders as it is in the grid.
    receiverSiblings.add(await cell('rcv2', receiver, PqPosture.legacy));
    receiverSiblings.add(await cell('rcv3', receiver, PqPosture.pqActive));
    // A live monitor, as the grid runs one throughout.
    final listener =
        receiverSiblings.last.client.notificationService
            as NotificationServiceImpl;
    final monitorLive = Completer<void>();
    monitorSub = listener.subscribe(shouldDecrypt: true).listen((n) {
      if (!monitorLive.isCompleted) monitorLive.complete();
    });
    print('##RATE## provisioned; ${namespaces.length} namespaces granted, '
        '${receiverSiblings.length + 1} receiver enrollments, monitor live');
  });

  test('put then get, $iterations times, a fresh namespace each cycle',
      () async {
    var ok = 0, wrong = 0, errored = 0;
    final failures = <String>[];
    // The positive control: which provider each read actually routed through.
    // A run that never touched at/symmetric would score 50/50 while measuring
    // nothing at all.
    final providers = <String, int>{};

    // Cycles run CONCURRENTLY in batches. Serially, 50 of them found nothing —
    // and the grid, which does reproduce, has nine clients reading and writing
    // at once. Overlapping reads are the condition being added.
    const batch = int.fromEnvironment('batch', defaultValue: 5);

    Future<void> cycle(int i) async {
      final ns = namespaces[i];
      // Signed, so the write carries an envelope and the reads below have an
      // `_apsk` fetch to interleave with — as they do in the grid.
      final payload = await _ProbeSigner(
              [senderCell, ...senderSiblings][i % (1 + senderSiblings.length)]
                  .client)
          .wrapAndSignAndJsonEncode({'cycle': i, 'ns': ns});

      final writeKey = AtKey()
        ..key = 'rate$i'
        ..namespace = ns
        ..sharedWith = receiver
        ..sharedBy = sender;

      final writers = [senderCell, ...senderSiblings];
      final writer = writers[i % writers.length];
      try {
        await writer.client.put(writeKey, payload,
            putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
      } catch (e) {
        errored++;
        failures.add('cycle $i PUT threw: $e');
        return;
      }

      // The varied thing, and the only one: which AtKey object the get is
      // handed. Same fields either way.
      final readKey = shareAtKeyObject
          ? writeKey
          : (AtKey()
            ..key = 'rate$i'
            ..namespace = ns
            ..sharedWith = receiver
            ..sharedBy = sender);

      try {
        final got = await receiverCell.client.get(readKey,
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
        final raw = got.value as String;
        final pid = '${got.metadata?.appMetadata?.providerId}';
        providers[pid] = (providers[pid] ?? 0) + 1;
        // A wrong value is the finding; it need not throw.
        try {
          jsonDecode(raw);
          if (raw == payload) {
            ok++;
            // Verify from every receiver enrollment, which is what puts
            // concurrent `_apsk` lookups beside the next cycle's read.
            for (final sib in [receiverCell, ...receiverSiblings]) {
              try {
                await _ProbeSigner(sib.client).verifyEnvelopeSignature(
                    SignedEnvelope.fromJson(jsonDecode(raw) as Map),
                    signerAtSign: sender);
              } catch (_) {
                // Verification failures are not what this probe counts.
              }
            }
          } else {
            wrong++;
            failures.add('cycle $i WRONG-VALUE len=${raw.length} '
                'provider=${got.metadata?.appMetadata?.providerId}');
          }
        } on FormatException {
          wrong++;
          failures.add('cycle $i NOT-JSON len=${raw.length} '
              'provider=${got.metadata?.appMetadata?.providerId} '
              'head=${raw.substring(0, raw.length > 20 ? 20 : raw.length)}');
        }
      } catch (e) {
        errored++;
        failures.add('cycle $i GET threw: ${'$e'.split('\n').first}');
      }
    }

    for (var start = 0; start < namespaces.length; start += batch) {
      final end = (start + batch).clamp(0, namespaces.length);
      await Future.wait([for (var i = start; i < end; i++) cycle(i)]);
      print('##RATE## $ok ok, $wrong wrong, $errored errored after $end');
    }
    print('##RATE## providers routed: $providers');
    // The denominator is the claim. A cycle that routed legacy never touched
    // the content-key path, so counting it would inflate the denominator with
    // attempts that could not have failed.
    expect(providers['legacy'] ?? 0, 0,
        reason: 'cycles routed legacy and so never exercised the CK path; the '
            'rate below would be measured over the wrong denominator');

    print('##RATE## FINAL shareAtKeyObject=$shareAtKeyObject '
        'ok=$ok wrong=$wrong errored=$errored of ${namespaces.length}');
    for (final f in failures.take(20)) {
      print('##RATE##   $f');
    }
    // A probe reports; it does not judge. The rate is the output.
    expect(ok + wrong + errored, namespaces.length);
  }, timeout: Timeout(Duration(minutes: 30)));
}
