// The enrollment key-package surface is @experimental; driving it is how each
// cell gets an enrollment of its own.
// ignore_for_file: experimental_member_use

@Timeout(Duration(minutes: 25))
@Tags(['pq'])
library;

import 'dart:async' show Completer;
import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
// ignore: implementation_imports
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
// ignore: implementation_imports
import 'package:at_client/src/service/notification_service_impl.dart'
    show NotificationServiceImpl;
// ignore: implementation_imports
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show EnrolledClient, enrolAndAuthenticate;
import 'package:test/test.dart';

import 'test_utils.dart';

/// Arm 2, the posture grid — its provisioning, and the assertions that keep it
/// meaningful.
///
/// Two things it settles, neither of which any run had observed before:
///
/// 1. **Six clients in one process.** `AtClientImpl` keys its cache by
///    `(atSign, enrollmentId)` and `AtClientManager` has a public constructor
///    holding its own client, so six should be six cache entries. Three has
///    been run (`pq_stage_arm_test.dart`); six across two atSigns has not.
///
/// 2. **The nskey advertisement is per-namespace.** It is published at
///    `public:__nskey.<ns>@<owner>` and resolved by `(owner, namespace)` with
///    no atSign-level fallback, so three postures on ONE atSign should be able
///    to hold disjoint seeding state provided each has its own namespace. If
///    that holds, the grid needs two atSigns rather than six.
///
/// Storage is isolated **per client**, not per atSign: `TestUtils.getPreference`
/// keys `hiveStoragePath` on the atSign alone, so the three enrollments of one
/// atSign would otherwise share one Hive box and one commit log.
///
/// Every client is built through `AtClientManager`'s public constructor.
/// `getInstance().setCurrentAtSign` calls `previousAtClient?.stop()`
/// (`at_client_manager.dart:165`), so the singleton route would stop each
/// client as the next one came up.
/// A distinguishable "nothing arrived" for the notification cell's first
/// attempt — a distinct instance rather than null, because null is a value a
/// notification could legitimately carry.
final AtNotification _absent = AtNotification.empty();

/// The smallest thing that can hold [EnvelopeSigning].
///
/// Signing and verifying share one class because they share one `_apsk`
/// address: a verifier resolving the record differently from the signer would
/// be testing two spellings rather than one exchange.
class _GridEnvelopeSigner with ApkamSigning, EnvelopeSigning {
  _GridEnvelopeSigner(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('pqGridEnvelope');

  /// Null: a cached public key would let one cell verify against a key a
  /// previous cell published, which is exactly the confusion a grid over
  /// postures exists to expose.
  @override
  final ({Duration cacheExpiry, bool resetOnLookup})? publicKeyCacheSettings =
      null;
}

void main() {
  final atSigns = <String>[
    ConfigUtil.getYaml()['atSign']['firstAtSign'] as String,
    ConfigUtil.getYaml()['atSign']['secondAtSign'] as String,
  ];

  /// The stage no named constant expresses: post-quantum writes with the
  /// legacy fallback still permitted.
  ///
  /// `disallowLegacyEncryption` is settable only through a posture, and every
  /// named stage either writes legacy or refuses it — so the rows about an
  /// opted-in fallback are unreachable from the three constants. The unnamed
  /// constructor exists for exactly this.
  final pqFallback = PqPosture(
    authenticationKeyAlgorithm: PqPosture.pqActive.authenticationKeyAlgorithm,
    dataSigningKeyAlgorithms: PqPosture.pqActive.dataSigningKeyAlgorithms,
    seedNamespaceKeys: true,
    keyExchangeMode: PqPosture.pqActive.keyExchangeMode,
    writesPqByDefault: true,
    configuresPqProviders: true,
    disallowLegacyEncryption: false,
    mintLegacyMaterial: true,
    sealsToKeyAlgorithms: PqPosture.pqActive.sealsToKeyAlgorithms,
    keyEstablishmentAlgorithms: PqPosture.pqActive.keyEstablishmentAlgorithms,
  );

  /// Namespaces are RUN-UNIQUE, and that is a correctness requirement rather
  /// than hygiene.
  ///
  /// A namespace key is minted once and then adopted: a client starting into a
  /// namespace that already advertises one takes the published advertisement
  /// rather than re-minting, because re-minting would rotate the key out from
  /// under every peer that had already fetched it. Adopting conveys no
  /// private half.
  ///
  /// So against a virtualenv that outlives one run — which is every local run
  /// after the first — a fixed namespace means this run's enrollments adopt a
  /// generation whose private belongs to a previous run's clients, and every
  /// reader fails with "no nskey private held". Measured: with fixed
  /// namespaces, ZERO of three authorised readers could read, including the
  /// one that appeared to have seeded.
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// The namespace every peer has a namespace key for.
  final nsReady = 'pqgr$runId';

  /// The namespace the RECEIVER has never seeded.
  ///
  /// The receiver's posture is not the second axis of a data-path grid, and
  /// this namespace is why. What a receiver's posture changes for a write
  /// *toward* it is only whether it published a
  /// namespace key. That is a property of `(receiver, namespace)`, not of
  /// which enrollment eventually reads — so the axis is **readiness**, and it
  /// is expressed by which namespace the write targets.
  ///
  /// Seeded on the sender and not on the receiver, which is what makes it
  /// asymmetric: an enrollment seeds every namespace it is authorised for, so
  /// a sender able to write here necessarily seeds it on its own atSign. Only
  /// the receiver's side is asserted absent.
  final nsUnready = 'pqgn$runId';

  /// One cell of the provisioning: which atSign, which posture, and which
  /// namespaces the enrollment is authorised for.
  ///
  /// The senders hold both namespaces so the same client can be offered a
  /// ready peer and an unready one, which is the whole differential. The
  /// receivers are what decide readiness: [nsReady] carries seeding postures
  /// on both sides, [nsUnready] carries a legacy receiver alone.
  final cellSpec = <String,
      ({String atSign, PqPosture posture, Map<String, String> namespaces})>{};

  final sender = atSigns[0];
  final receiver = atSigns[1];

  final senderPostures = <String, PqPosture>{
    'legacy': PqPosture.legacy,
    'pqReady': PqPosture.pqReady,
    'pqActive': PqPosture.pqActive,
    'fallback': pqFallback,
  };
  for (final entry in senderPostures.entries) {
    cellSpec['s-${entry.key}'] = (
      atSign: sender,
      posture: entry.value,
      namespaces: {nsReady: 'rw', nsUnready: 'rw'},
    );
  }
  // A second enrollment at one posture, so the rows asserting that EVERY
  // authorised enrollment reads are not measuring n = 1, where they pass
  // whether or not the mechanism works.
  cellSpec['s-pqActive2'] = (
    atSign: sender,
    posture: PqPosture.pqActive,
    namespaces: {nsReady: 'rw', nsUnready: 'rw'},
  );

  // The receiver side. Four postures in ONE namespace is deliberate: it is
  // both what makes [nsReady] seeded and the two-installs-of-one-app shape,
  // and the second enrollment to start must ADOPT the published key rather
  // than mint a rival generation.
  //
  // `legacy` and `pqReading` fail to read for DIFFERENT reasons, and keeping
  // both is what stops one masking the other: `legacy` configures no
  // post-quantum provider, so it is refused on the crypto path before any key
  // is looked for; `pqReading` configures them and never seeds, so it is
  // refused on the key-acquisition path. With only the first, nothing here
  // would exercise the second at all.
  for (final entry in <String, PqPosture>{
    'legacy': PqPosture.legacy,
    'pqReading': legacyPlusPqProviders,
    'pqReady': PqPosture.pqReady,
    'pqActive': PqPosture.pqActive,
  }.entries) {
    cellSpec['r-${entry.key}'] = (
      atSign: receiver,
      posture: entry.value,
      namespaces: {nsReady: 'rw'},
    );
  }
  // The unready receiver: legacy alone, so nothing on this atSign ever seeds
  // [nsUnready].
  cellSpec['r-unready'] = (
    atSign: receiver,
    posture: PqPosture.legacy,
    namespaces: {nsUnready: 'rw'},
  );


  /// Keyed by cell name, so a failure says which cell produced it.
  final cells = <String, EnrolledClient>{};
  final storagePaths = <String, String>{};

  /// One keyfile per cell, and it is not optional.
  ///
  /// `AtClient.atKeysIo` is where a minted nskey private is FILED. Without
  /// one it is null, the mint publishes an advertisement whose private half
  /// nothing kept, and every reader — the minter included — then fails with
  /// "no nskey private held". Measured: with no `atKeysIo`, ZERO of three
  /// authorised readers could read a record sealed to their own atSign's
  /// published key.
  final keyfiles = <String, InMemoryAtKeysIo>{};

  /// A path safe on disk — the demo atSigns carry an emoji.
  String slug(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');

  AtClientPreference preferenceFor(String name, String atSign,
      {required String role, required PqPosture posture}) {
    final storage = 'test/hive/pqprobe/$role-${slug(name)}';
    final preference = TestUtils.getPreference(atSign, posture: posture)
      ..hiveStoragePath = storage
      ..commitLogPath = storage;
    if (role == 'cell') storagePaths[name] = storage;
    return preference;
  }

  /// The atSign's primary, holding a registered key package in [namespace].
  ///
  /// ⚠️ **One per atSign, and the code cannot give one per cell.**
  /// `AtClientImpl.atClientInstanceMap` is **static** and keyed by
  /// `(atSign, enrollmentId)`, so the second call for an atSign gets the first
  /// call's client whatever preference it is handed — the public
  /// `AtClientManager` constructor separates the managers, not the clients.
  /// Memoised here so that is explicit rather than accidental.
  ///
  /// This said "one per cell rather than one per atSign" until 2026-08-29 and
  /// asked for a per-cell `hiveStoragePath` that was silently dropped: every
  /// approver after the first ran on the first cell's store. It surfaced when
  /// `AtClientImpl.refuseChangedStoragePath` started refusing exactly that,
  /// and nothing else in the suite would have shown it — the grid was green
  /// throughout.
  ///
  /// `register()` takes no namespace and files into the client's own, and is
  /// idempotent (it logs "have already published"), so one registration for
  /// the atSign is what the cells need and all they ever got.
  ///
  /// Built through `AtClientManager`'s PUBLIC constructor. The singleton's
  /// `setCurrentAtSign` stops the outgoing client, so the singleton route
  /// would stop each of these as the next one came up.
  final approvers = <String, AtClient>{};
  Future<AtClient> approverFor(String atSign, String namespace) async {
    final memoised = approvers[atSign];
    if (memoised != null) return memoised;
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign,
        namespace,
        // ⚠️ legacy, and this is the grid's readiness axis. Seeding is the
        // only posture-gated step in the PQ bootstrap, so an approver at any
        // other posture publishes `public:__nskey.<ns>@<atSign>` before a
        // single cell runs — minting the namespace key the grid is measuring
        // and moving its private into the approver's keyfile. Every readback
        // assertion would then pass for the wrong reason, and nothing would
        // go red.
        preferenceFor(slug(atSign), atSign,
            role: 'approver', posture: legacyPlusPqProviders),
        atKeysIo: keysIo,
        atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(manager.atClient, atSign);
    await AtClientSecretSharing.forClient(manager.atClient).register();
    approvers[atSign] = manager.atClient;
    return manager.atClient;
  }

  /// Whether `public:__nskey.<namespace>@<atSign>` exists, read over the wire.
  ///
  /// Tri-state rather than a bool: a lookup that fails for a reason other than
  /// absence must not read as "unseeded", which is the verdict this rests on.
  Future<({bool present, String detail})> advertisement(
      AtClient reader, String atSign, String namespace) async {
    try {
      final response = await TestUtils.executeCommandAndParse(
          reader, 'llookup:public:__nskey.$namespace$atSign',
          auth: true);
      final value = response?.trim() ?? '';
      return (present: value.isNotEmpty, detail: 'len ${value.length}');
    } on Object catch (e) {
      final text = '$e';
      final isAbsent = text.contains('AT0015') ||
          text.toLowerCase().contains('key not found') ||
          text.contains('does not exist');
      return (present: false, detail: isAbsent ? 'absent' : 'ERROR: $text');
    }
  }

  setUpAll(() async {
    for (final entry in cellSpec.entries) {
      final name = entry.key;
      final spec = entry.value;
      // The approver rides the first authorised namespace; the conveyance
      // path is namespace-scoped and this is where the enrollee's package is
      // registered.
      final approverNamespace = spec.namespaces.keys.first;
      stdout.writeln('##GRID## building $name on ${spec.atSign} '
          'in ${spec.namespaces.keys.join("+")}');
      final approver = await approverFor(spec.atSign, approverNamespace);
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(spec.atSign, AtKeys());
      keyfiles[name] = keysIo;
      cells[name] = await enrolAndAuthenticate(
        approver: approver,
        atSign: spec.atSign,
        namespace: approverNamespace,
        preference: preferenceFor(name, spec.atSign,
            role: 'cell', posture: spec.posture),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        // Authorised for exactly these namespaces. `{'*': 'rw'}` would be
        // fully privileged AND would seed nothing: `NskeySeeding` skips the
        // wildcard, so such an enrollment publishes no namespace key and then
        // refuses every write it makes.
        namespaces: spec.namespaces,
        // The enrollment mode follows the cell's own posture, which is the
        // one axis of it this harness can apply: a legacy cell submits a
        // legacy request and so is not sealed to at approval time. ⚠️ That
        // does NOT make it an un-upgraded install — the client still registers
        // a key package at startup — so read a legacy cell here as "an app
        // that asked for the legacy stage", never as "a peer without the
        // capability". The faithful peer is `pq_released_peer_test.dart`.
        keyExchangeMode: spec.posture.keyExchangeMode,
        // `(appName, deviceName)` is one-shot server state.
        deviceName: 'pqgrid-$name-'
            '${DateTime.now().microsecondsSinceEpoch}',
        // The cell's own keyfile. Without it there is nowhere to file a minted
        // namespace private, and the cell measures an inert client.
        atKeysIo: keysIo,
      );
      stdout.writeln('##GRID## up: $name '
          'enrolledAs=${cells[name]!.enrollmentId} '
          'runningAs=${cells[name]!.client.enrollmentId}');
    }
  });

  test('every client stands up together, each with its own store', () async {
    expect(cells, hasLength(cellSpec.length));
    expect(storagePaths.values.toSet(), hasLength(cellSpec.length),
        reason: 'one hiveStoragePath per client. TestUtils.getPreference keys '
            'storage on the atSign alone, so without the override the '
            'enrollments of one atSign share a Hive box and a commit log');
    for (final entry in storagePaths.entries) {
      expect(Directory(entry.value).existsSync(), isTrue,
          reason: '${entry.key}: no store at ${entry.value}');

      // ⚠️ A DIRECTORY IS NOT A STORE, and this test was named for something
      // it did not check until 2026-08-29. `hiveStoragePath` used to be
      // ignored for the second client of an atSign in one process — every
      // client attached to the first one's Hive box — and yet each named
      // directory still appeared, because the encryption-secret file
      // `<sha>.hash` is written at the path a client asks for even when its
      // box is opened somewhere else entirely. So "each with its own store"
      // was green while all six shared one.
      //
      // The `.hive` file is the store. Asserting it is what makes this row
      // mean its own name.
      final files = Directory(entry.value)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(files.where((n) => n.endsWith('.hive')), isNotEmpty,
          reason: '${entry.key}: ${entry.value} holds no .hive file, so this '
              'client is not storing here — its box is open somewhere else '
              'and this directory has only the secret beside it. Found: '
              '$files');
    }
    expect(
        cells.values.map((c) => c.client.enrollmentId).toSet(),
        hasLength(cellSpec.length),
        reason: 'every client must run as its own enrollment. Reading '
            'EnrolledClient.enrollmentId here would compare the ids they were '
            'ENROLLED as, which for a pq posture is not the id it runs under');
  });

  test('readiness is a property of (receiver, namespace), and the receiver '
      'side of the unready namespace really is unseeded', () async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    late ({bool present, String detail}) readyOnReceiver;
    late ({bool present, String detail}) unreadyOnReceiver;
    late ({bool present, String detail}) unreadyOnSender;

    final reader = cells['r-legacy']!.client;
    final senderReader = cells['s-legacy']!.client;

    while (true) {
      readyOnReceiver = await advertisement(reader, receiver, nsReady);
      unreadyOnReceiver = await advertisement(reader, receiver, nsUnready);
      unreadyOnSender = await advertisement(senderReader, sender, nsUnready);
      if (readyOnReceiver.present && unreadyOnSender.present) break;
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    stdout.writeln('##GRID## nskey $receiver/$nsReady: $readyOnReceiver');
    stdout.writeln('##GRID## nskey $receiver/$nsUnready: $unreadyOnReceiver');
    stdout.writeln('##GRID## nskey $sender/$nsUnready: $unreadyOnSender');

    for (final o in [readyOnReceiver, unreadyOnReceiver, unreadyOnSender]) {
      expect(o.detail.startsWith('ERROR:'), isFalse,
          reason: 'a lookup failed for a reason that is not absence, so this '
              'measured nothing — ${o.detail}');
    }

    expect(readyOnReceiver.present, isTrue,
        reason: '$receiver holds seeding postures in $nsReady, so it must '
            'advertise a namespace key there — without it every cell is an '
            'unready cell and the grid has one column');
    expect(unreadyOnReceiver.present, isFalse,
        reason: '$receiver holds only a legacy enrollment in $nsUnready, so '
            'it must advertise nothing there. If it does, readiness is not '
            'separable from posture and the differential below has one arm');
    // The asymmetry, asserted rather than assumed: the sender seeds what it is
    // authorised for, and that is why readiness is directional.
    expect(unreadyOnSender.present, isTrue,
        reason: '$sender is authorised for $nsUnready and holds seeding '
            'postures, so it seeds its OWN side. A cell refusing a write into '
            '$nsUnready must therefore be refusing on the RECIPIENT\'s '
            'missing key, not on its own');
  });

  /// Whether a sender at [posture] must be REFUSED a write toward a peer that
  /// has published no namespace key.
  ///
  /// Derived from the posture rather than tabulated, so a new posture needs no
  /// new row here — and so the expectation is the product's own statement
  /// rather than a transcription of a run. A client that writes post-quantum
  /// by default has no legacy path to fall back to unless the fallback is
  /// separately opted into, and no post-quantum scheme can address a
  /// recipient that advertises no key.
  ///
  /// It still discriminates: were the wiring to break so that a pqActive
  /// client wrote legacy, the cell would succeed while this predicate — read
  /// from the constant — still demanded a refusal.
  bool mustRefuseUnready(PqPosture posture) => posture.writesPqByDefault;

  test('a cross-atSign write is refused exactly when the sender writes PQ and '
      'the recipient has published no namespace key', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final wrote = <String, AtKey>{};

    for (final entry
        in cellSpec.entries.where((e) => e.key.startsWith('s-'))) {
      final name = entry.key;
      final posture = entry.value.posture;
      final client = cells[name]!.client;

      for (final ns in [nsReady, nsUnready]) {
        final key = AtKey()
          ..key = 'xw$stamp${slug(name)}'
          ..namespace = ns
          ..sharedWith = receiver
          ..sharedBy = sender;
        final expectRefusal = ns == nsUnready && mustRefuseUnready(posture);

        if (expectRefusal) {
          await expectLater(
              () => client.put(key, 'v-$name',
                  putRequestOptions: PutRequestOptions()
                    ..useRemoteAtServer = true),
              throwsA(isA<NamespaceKeyUnavailableException>()),
              reason: '$name writes post-quantum by default and $receiver has '
                  'published no $ns key, so there is no recipient to seal to '
                  'and no legacy path opted into. A write that SUCCEEDED here '
                  'went out under a scheme this posture was built to refuse');
        } else {
          expect(
              await client.put(key, 'v-$name',
                  putRequestOptions: PutRequestOptions()
                    ..useRemoteAtServer = true),
              isTrue,
              reason: '$name -> $ns must write: '
                  '${ns == nsReady ? "the recipient has published a key" : "this posture writes legacy, which needs none"}');
          wrote['$name -> $ns'] = key;
        }
      }
    }

    // The refusals are only meaningful beside writes that went through: an
    // arm where everything failed would satisfy the throwsA above just as
    // well, and would mean the harness was broken rather than the posture
    // working.
    expect(wrote, isNotEmpty,
        reason: 'every cell refused, so the refusing cells prove nothing '
            'about the posture — this is a broken harness, not a passing grid');
    stdout.writeln('##GRID## wrote ${wrote.length} of '
        '${cellSpec.keys.where((k) => k.startsWith("s-")).length * 2} cells');
  });

  test('the recipient enrollment holding the namespace private reads what was '
      'written, and its siblings are pending conveyance rather than broken',
      () async {
    // Three receiving enrollments share one namespace deliberately, and only
    // ONE of them can read at this point — which is the finding, not a
    // shortcoming of the grid.
    //
    // Minting a namespace key is what puts its private in a keyfile. A second
    // enrollment starting later ADOPTS the published advertisement, which is
    // correct — re-minting would rotate the key out from under peers that
    // already fetched it — but adopting conveys no private. Siblings get it
    // over the secret-sharing substrate, whose serve is driven by a HOLDER'S
    // START-TIME SWEEP: the holder consumes pending requests when it comes up.
    // Every client here came up in setUpAll, so no holder starts after the
    // ask, and no answer can arrive.
    //
    // So "every authorised enrollment reads" is not a static property and
    // cannot be a cell of this grid — it needs a restart, which is arm 3's.
    // What this asserts is the pair arm 3 needs an after-state for: exactly
    // one reader reads, and the others fail for the conveyance-pending reason
    // SPECIFICALLY rather than for any reason at all.
    final readers = ['r-legacy', 'r-pqReading', 'r-pqReady', 'r-pqActive'];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final senderName = 's-pqActive';

    final key = AtKey()
      ..key = 'rb$stamp'
      ..namespace = nsReady
      ..sharedWith = receiver
      ..sharedBy = sender;
    const value = 'readback-payload';
    expect(
        await cells[senderName]!.client.put(key, value,
            putRequestOptions: PutRequestOptions()..useRemoteAtServer = true),
        isTrue,
        reason: '$senderName could not write the record to be read back');

    final read = <String>[];
    final pending = <String>[];
    for (final readerName in readers) {
      try {
        final got = await cells[readerName]!.client.get(key,
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
        expect(got.value, value,
            reason: '$readerName returned a value that is not what was '
                'written, which is neither a read nor a pending conveyance');
        read.add(readerName);
      } on Object catch (e) {
        // Which refusal is itself a claim about the stage, so it is asserted
        // rather than accepted: a reader that configures the providers can
        // only be short of the key, and one that does not can only be short
        // of the provider. Accepting either message for either reader would
        // pass for a client failing on the wrong layer.
        final expected =
            cellSpec[readerName]!.posture.configuresPqProviders
                ? 'no nskey private held'
                : 'is not registered';
        expect('$e', contains(expected),
            reason: '$readerName failed for a reason that is neither a '
                'pending conveyance nor the refusal its own stage implies, '
                'so this is a real failure: $e');
        pending.add(readerName);
      }
    }

    stdout.writeln('##GRID## readback: read=$read pending=$pending');

    // Predicted from the posture, not transcribed from a run. An enrollment
    // that seeds ends up holding the namespace private — by minting it, or by
    // pulling it while seeding finds one already published. One that does not
    // seed never acquires it, and so cannot open data sealed to its own
    // atSign's namespace key.
    //
    // That is not a hole: it is the pre-capability install of UC-B4.3, whose
    // remedy is upgrading that install, and it is why a rollout seeds a stage
    // BEFORE it switches writes over. Two routes reach it, and the grid holds
    // one reader for each — the crypto path, where a stage configuring no
    // post-quantum provider is refused before any key is sought, and the
    // key-acquisition path, where a stage that configures them never acquired
    // the namespace private. Nothing else in the suite exercises the second.
    final shouldRead = [
      for (final r in readers)
        if (cellSpec[r]!.posture.seedNamespaceKeys) r
    ];
    final shouldNotRead =
        readers.where((r) => !shouldRead.contains(r)).toList();

    // ⚠️ Only the MINTER is deterministic here. A second seeding enrollment
    // adopts the published advertisement — correct, since re-minting rotates
    // the key out from under peers that already fetched it — and then has to
    // be CONVEYED the private, which is served off a holder's start-time
    // sweep. Whether that lands inside one run is a race.
    //
    // Measured: consecutive runs of this file gave read=[r-pqReady, r-pqActive]
    // and read=[r-pqReady]. Asserting both would be asserting a rate. What is
    // invariant is the pair below, and the sibling's acquisition belongs to
    // arm 3, where a restart makes it deterministic.
    expect(read, isNotEmpty,
        reason: 'no enrollment of $receiver could read a record sealed to its '
            'own atSign. Seeding published an advertisement whose private half '
            'nothing kept, so every peer sealing to this atSign is writing '
            'data nobody can open');
    for (final r in read) {
      expect(cellSpec[r]!.posture.seedNamespaceKeys, isTrue,
          reason: '$r reads $nsReady but does not seed. Then seeding is not '
              'what governs key acquisition, and the rollout ordering this '
              'project rests on is not what the postures describe');
    }
    for (final r in shouldNotRead) {
      expect(pending, contains(r),
          reason: '$r does not seed, so it can never have acquired the '
              'namespace private and must have failed — on the crypto path '
              'or the key-acquisition one. If it READ, the pre-capability '
              'install of UC-B4.3 is not the failure mode the catalogue says '
              'it is');
    }
    expect(shouldRead, isNotEmpty,
        reason: 'no reader was expected to read, so this cell discriminates '
            'nothing - the receiving side needs at least one seeding posture');
    expect(shouldNotRead, isNotEmpty,
        reason: 'no reader was expected to fail, so the negative arm is '
            'absent and this would pass for a client that reads everything');
  });

  test('a self write is stamped with the provider its posture selects',
      () async {
    // The cross-atSign cells assert an OUTCOME - written or refused. This one
    // asserts the MECHANISM: which crypto provider actually encrypted the
    // value, read back off the record's own `appMetadata`. A grid that only
    // checked outcomes would pass for a build where every posture wrote the
    // same way, because a legacy write to a seeded peer succeeds exactly as a
    // post-quantum one does.
    //
    // Self rather than cross deliberately: a cross-atSign lookup returns a
    // null providerId, so the stamp is only observable on the writer's side.
    final stamp = DateTime.now().microsecondsSinceEpoch;

    for (final entry
        in cellSpec.entries.where((e) => e.key.startsWith('s-'))) {
      final name = entry.key;
      final posture = entry.value.posture;
      final client = cells[name]!.client;

      final key = AtKey()
        ..key = 'self$stamp${slug(name)}'
        ..namespace = nsReady
        ..sharedBy = sender;

      expect(await client.put(key, 'self-$name'), isTrue,
          reason: '$name could not write to its own atSign in $nsReady, '
              'which its own enrollment seeded');

      final read = await client.get(key);
      expect(read.value, 'self-$name',
          reason: '$name could not read back what it just wrote');

      final expected = posture.writesPqByDefault
          ? symmetricAesGcmCryptoProviderId
          : legacyCryptoProviderId;
      expect(read.metadata?.appMetadata?.providerId, expected,
          reason: '$name has writesPqByDefault=${posture.writesPqByDefault}, '
              'so its value must carry $expected. A posture whose write is '
              'stamped with the other provider is not running the era default '
              'it names - and every cross-atSign cell above would still pass');
      stdout.writeln('##GRID## self $name: '
          'providerId=${read.metadata?.appMetadata?.providerId}');
    }
  });

  test('a notification crosses atSigns and its value decrypts, for every '
      'sender posture', () async {
    // Listener before trigger — and the listener that matters is the
    // atServer's, not this stream. `subscribe()` returns before the monitor's
    // socket has connected, PKAMed and written `monitor:`, and the atServer's
    // inbound stream is a BROADCAST stream with no backlog, so a notification
    // enqueued in that window is never delivered to that connection at all.
    // Waiting on a notification actually arriving is the only sufficient
    // gate; `currentListenerState == listening` is set straight after writing
    // the command and says nothing about the atServer having processed it.
    //
    // The atServer emits `statsNotification` every ~11s to every listening
    // monitor, which makes it both the readiness signal and the positive
    // control: seeing it and not ours distinguishes a monitor that receives
    // nothing from one that receives everything except the thing under test.
    final listener = cells['r-pqActive']!.client.notificationService
        as NotificationServiceImpl;

    final seen = <String>[];
    final monitorProvenLive = Completer<void>();
    final arrived = <String, Completer<AtNotification>>{};

    final subscription =
        listener.subscribe(shouldDecrypt: true).listen((n) {
      seen.add(n.key);
      if (!monitorProvenLive.isCompleted) monitorProvenLive.complete();
      for (final entry in arrived.entries) {
        if (n.key.toLowerCase().contains(entry.key) &&
            !entry.value.isCompleted) {
          entry.value.complete(n);
        }
      }
    });
    addTearDown(subscription.cancel);

    await monitorProvenLive.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw StateError(
          'no notification of any kind reached the listener within 90s, so '
          'the monitor is not up. Notifying now would repeat the race this '
          'gate exists to close, and a delivery failure afterwards would be '
          'attributed to the posture rather than to readiness'),
    );

    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (final entry
        in cellSpec.entries.where((e) => e.key.startsWith('s-'))) {
      final name = entry.key;
      // Lowercased: the atServer lowercases record names, so a marker
      // carrying an uppercase letter never matches what comes back — and it
      // fails as 'never arrived' while the monitor's own log shows it did.
      final marker = 'ntfy$stamp${slug(name)}'.toLowerCase();
      arrived[marker] = Completer<AtNotification>();

      final key = AtKey()
        ..key = marker
        ..namespace = nsReady
        ..sharedWith = receiver
        ..sharedBy = sender
        ..metadata = (Metadata()..ttr = 60000);
      final value = 'notified-by-$name';

      Future<void> send() async {
        final result = await cells[name]!.client.notificationService.notify(
            NotificationParams.forUpdate(key, value: value));
        expect(result.notificationStatusEnum, NotificationStatusEnum.delivered,
            reason: '$name could not deliver a notification to $receiver');
      }

      await send();

      // ONE re-send if the first does not arrive, and the retry is the
      // discriminator rather than a way of making the test pass. Monitor
      // delivery in this pack drops notifications at a measurable rate — the
      // family 14.34 tracks — so a notification that a re-send recovers is
      // that flakiness. One that does NOT survive a re-send is a finding
      // about the posture, and fails below with both attempts named.
      var notification = await arrived[marker]!.future
          .timeout(const Duration(seconds: 60), onTimeout: () => _absent);
      if (identical(notification, _absent)) {
        stdout.writeln('##GRID## notify $name: first attempt did not arrive '
            'in 60s; re-sending once');
        await send();
        notification = await arrived[marker]!.future.timeout(
          const Duration(seconds: 90),
          onTimeout: () => throw StateError(
              "$name's notification did not reach the receiver on EITHER of "
              'two sends, 150s in total, and both notifies reported '
              'delivered. Two independent drops is not the delivery '
              'flakiness this retry exists to absorb.\n'
              '  the monitor saw ${seen.length}: $seen\n'
              '${seen.isNotEmpty ? "  It IS receiving, so this is not monitor readiness." : "  It received NOTHING, not even statsNotification, so the monitor is not up and this says nothing about delivery."}'),
        );
      }

      expect(notification.value, value,
          reason: "$name's notification arrived but its value did not "
              'decrypt to what was sent. The receiver decrypts with whatever '
              'the sender sealed with, and every receiver in this grid '
              'configures the providers its senders use — so a mismatch here '
              'is a real cross-posture failure');
      stdout.writeln('##GRID## notify $name: delivered and decrypted');
    }

    // The positive control, asserted rather than assumed.
    expect(seen, isNotEmpty,
        reason: 'the monitor recorded no notification at all, so every '
            'delivery above was measured by a listener that was never live');
  });

  test('UC-G1.15 · every posture verifies every other posture\'s signed '
      'envelope, and the algorithms are what the stage names', () async {
    // The claim: the rollout ladder SWAPS signing algorithms rather than
    // overlapping them, so a pqActive sender emits an ML-DSA-65 signature
    // alone and a pqReady receiver — which signs RSA-2048 — must still verify
    // it. That is a claim about an ungated verifier, and this is what settles
    // it. Verification fetches the signer's `_apsk` from the atServer, so the
    // sender's advertisement, the receiver's reader and the algorithm both
    // ends agree on are all exercised.
    //
    // ⚠️ The nine cells are NOT what proves the stages differ. Mutating
    // pqActive to resolve as pqReady leaves all nine passing, because a sender
    // signing RSA-2048 verifies everywhere too. The algorithm pins at the end
    // are the only thing that discriminates, and a change dropping them would
    // leave a grid that passes for an inert harness.
    const senders = ['s-legacy', 's-pqReady', 's-pqActive'];
    const receivers = ['r-legacy', 'r-pqReady', 'r-pqActive'];
    // Whichever receiving enrollment seeded first holds the namespace private;
    // the read below only needs one of them, and a sibling that has not been
    // conveyed it yet is arm 3's subject rather than this row's.
    const envelopeReader = 'r-pqReady';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    // Nullable elements deliberately: `alg` is String? and a null would mean
    // an envelope whose header names no algorithm at all. Filtering it out
    // here would turn that finding into a shorter list.
    final emitted = <String, List<String?>>{};

    for (final senderName in senders) {
      final client = cells[senderName]!.client;
      final signer = _GridEnvelopeSigner(client);

      // The startup mint is fire-and-forget, and the sign path falls back to
      // the APKAM authentication key while the keyfile holds no signing key —
      // so signing before the mint has FILED produces an envelope carrying a
      // key the freshly published advertisement just withdrew, and the cell
      // fails on a race rather than on anything the stage means. Bounded and
      // loud: a mint that never settles is a finding, not a wait.
      final wanted = client.getPreferences()!.dataSigningKeyAlgorithms;
      if (wanted.isNotEmpty) {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (true) {
          final held =
              (await signer.heldSigningKeys).map((k) => k.algorithm).toSet();
          if (held.containsAll(wanted)) break;
          if (DateTime.now().isAfter(deadline)) {
            throw StateError(
                '$senderName: the startup mint never settled — the stage '
                'names $wanted and the keyfile holds $held after 60s. '
                'Signing now would fall back to the authentication key and '
                'measure a race, not the stage');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      final envelopeJson = await signer.wrapAndSignAndJsonEncode(
          {'runId': '$stamp', 'from': senderName});
      final key = AtKey()
        ..key = 'env$stamp${slug(senderName)}'
        ..namespace = nsReady
        ..sharedWith = receiver
        ..sharedBy = sender;
      expect(
          await client.put(key, envelopeJson,
              putRequestOptions: PutRequestOptions()..useRemoteAtServer = true),
          isTrue,
          reason: '$senderName could not leave its envelope for $receiver');

      // Parsed back from the JSON that was actually written, so what is
      // recorded is what the peer will read rather than what this process
      // meant to send.
      final parsed = SignedEnvelope.fromJson(jsonDecode(envelopeJson) as Map);
      emitted[senderName] = [for (final sig in parsed.signatures) sig.alg];
      stdout.writeln('##GRID## envelope $senderName emitted '
          '${emitted[senderName]}');

      // Read from the atServer ONCE, by the enrollment that holds the
      // namespace private. The record is sealed to the receiver's namespace
      // key, so re-reading it per receiver measures whether that private has
      // been CONVEYED to each sibling — a start-time-sweep race that has
      // nothing to do with this row. Measured: requiring all three to read
      // made this file fail 1 run in 5 on "no nskey private held".
      //
      // What UC-G1.15 claims is about the VERIFIER, and verification fetches
      // the signer's `_apsk`, which is public. So the wire read happens once
      // and every posture's verifier is then run against the same bytes —
      // which is the claim, and is now independent of the conveyance.
      final raw = (await cells[envelopeReader]!.client.get(key,
              getRequestOptions: GetRequestOptions()..useRemoteAtServer = true))
          .value as String;
      final envelope = SignedEnvelope.fromJson(jsonDecode(raw) as Map);

      // The round trip itself, asserted rather than printed. Verification
      // takes the STRONGEST shared signature, so an envelope that lost one of
      // two on the way through the atServer would verify exactly as well as
      // one that did not — every cell below would stay green while the
      // receiver was reading something other than what the sender emitted.
      expect([for (final sig in envelope.signatures) sig.alg],
          emitted[senderName],
          reason: '$senderName: the algorithms the receiver reads back must '
              'be the ones the sender emitted');

      for (final receiverName in receivers) {
        final verifier = _GridEnvelopeSigner(cells[receiverName]!.client);
        await verifier.verifyEnvelopeSignature(envelope, signerAtSign: sender);
        stdout.writeln('##GRID## envelope $senderName -> $receiverName: '
            'verified ${[for (final sig in envelope.signatures) sig.alg]}');
      }
    }

    // The pins. Without these the nine cells above pass for a harness where no
    // stage does anything.
    expect(emitted['s-pqActive'], ['ML-DSA-65'],
        reason: 'a pqActive enrollment mints an ML-DSA-65 signing key and '
            'signs with it alone. A second, weaker signature would only ever '
            'be the one a verifier passes over');
    expect(emitted['s-legacy'], isNot(contains('ML-DSA-65')),
        reason: 'a legacy enrollment files no signing key of its own and '
            'signs with its APKAM authentication key, which is RSA. If this '
            'carries ML-DSA-65 the stages are not distinct and every cell '
            'above verified for the wrong reason');
    for (final entry in emitted.entries) {
      expect(entry.value, hasLength(1),
          reason: '${entry.key}: no posture names two signing algorithms, so '
              'no envelope may carry two signatures');
    }
  });
}