// The enrollment key-package surface is @experimental; driving it is how each
// cell gets an enrollment of its own.
// ignore_for_file: experimental_member_use

@Timeout(Duration(minutes: 25))
@Tags(['pq'])
library;

import 'dart:io';

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
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
  /// this namespace is why. Reads and decryption are maximal under every
  /// posture and are not settable at all, so the only thing a receiver's
  /// posture changes for a write *toward* it is whether it published a
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

  // The receiver side. Three postures in ONE namespace is deliberate: it is
  // both what makes [nsReady] seeded and the two-installs-of-one-app shape,
  // and the second enrollment to start must ADOPT the published key rather
  // than mint a rival generation.
  for (final entry in <String, PqPosture>{
    'legacy': PqPosture.legacy,
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
      {required String role, PqPosture? posture}) {
    final storage = 'test/hive/pqprobe/$role-${slug(name)}';
    final preference = TestUtils.getPreference(atSign, posture: posture)
      ..hiveStoragePath = storage
      ..commitLogPath = storage;
    if (role == 'cell') storagePaths[name] = storage;
    return preference;
  }

  /// The atSign's primary, holding a registered key package in [namespace].
  ///
  /// One per cell rather than one per atSign: `register()` takes no namespace
  /// and files into the client's own, and pq-mode approval has the approver
  /// mint the enrollment's symmetric key and seal it to the enrollee's
  /// advertised package — so the approver must hold one itself.
  ///
  /// Built through `AtClientManager`'s PUBLIC constructor. The singleton's
  /// `setCurrentAtSign` stops the outgoing client, so the singleton route
  /// would stop each of these as the next one came up.
  Future<AtClient> approverFor(String name, String atSign,
      String namespace) async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, preferenceFor(name, atSign, role: 'approver'),
        atKeysIo: keysIo,
        atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(manager.atClient, atSign);
    await AtClientSecretSharing.forClient(manager.atClient).register();
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
      final approver =
          await approverFor('ap-$name', spec.atSign, approverNamespace);
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
    final readers = ['r-legacy', 'r-pqReady', 'r-pqActive'];
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
        expect('$e', contains('no nskey private held'),
            reason: '$readerName failed for a reason that is NOT a pending '
                'conveyance. Reads are maximal under every posture by '
                'construction, so any other failure here is a real one: $e');
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
    // BEFORE it switches writes over. "Reads are maximal under every posture"
    // is a statement about the crypto path, and this is the key-acquisition
    // path — a distinction nothing else in the suite exercises.
    final shouldRead = [
      for (final r in readers)
        if (cellSpec[r]!.posture.seedNamespaceKeys) r
    ];
    final shouldNotRead =
        readers.where((r) => !shouldRead.contains(r)).toList();

    expect(read, shouldRead,
        reason: 'the enrollments that seed $nsReady must hold its private and '
            'read. If one of them cannot, seeding published an advertisement '
            'whose private half nothing kept, and every peer sealing to this '
            'atSign is writing data it can never open');
    expect(pending, shouldNotRead,
        reason: 'an enrollment that does not seed never acquires the private, '
            'so it must be pending rather than reading. If it READ, seeding '
            'is not what governs key acquisition and the rollout ordering '
            'this project rests on is not what the postures describe');
    expect(shouldRead, isNotEmpty,
        reason: 'no reader was expected to read, so this cell discriminates '
            'nothing - the receiving side needs at least one seeding posture');
    expect(shouldNotRead, isNotEmpty,
        reason: 'no reader was expected to fail, so the negative arm is '
            'absent and this would pass for a client that reads everything');
  });
}
