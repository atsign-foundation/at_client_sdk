import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/transport.dart';

const _alice = '@alice';
const _bob = '@bob';

/// One client's post-quantum providers over [ring], as a pqActive client
/// writes and reads with them.
class _Client {
  final InMemoryNskeyKeyRing ring;
  final ContentKeyCache cache = ContentKeyCache();
  late final NskeyProvider nskey = NskeyProvider(keyRing: ring, cache: cache);
  late final CkManager manager = CkManager(cache: cache, keyRing: ring);
  late final SymmetricAesGcmProvider data =
      SymmetricAesGcmProvider(cache: cache, ckManager: manager);

  _Client(this.ring);
}

/// Seeds a fresh keypair for [owner] in [namespace] and returns its kid.
Future<String> _hold(
    InMemoryNskeyKeyRing ring, String owner, String namespace) async {
  final pair = await XWingKeyPair.generate();
  return ring.seedKeypair(owner, namespace,
      publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
}

/// Publishes a fresh key for [owner] in [namespace] whose private [ring] does
/// not hold, and returns its kid.
Future<String> _publish(
    InMemoryNskeyKeyRing ring, String owner, String namespace) async {
  final pair = await XWingKeyPair.generate();
  return ring.seedPublicOnly(owner, namespace, publicKey: pair.publicKeyBytes);
}

/// A ring whose held namespaces are what [filing] lists, and nothing else, so
/// the keys it seals with and what it holds can be set apart.
class _FilingRing extends InMemoryNskeyKeyRing {
  final NskeyPrivateFiling filing;

  _FilingRing(this.filing);

  @override
  Future<Set<String>> heldNamespaces(String owner) async =>
      owner == filing.atSign ? filing.filedNamespaces() : const {};
}

/// Records every namespace it is asked for a published key in.
class _LookupRecordingRing extends InMemoryNskeyKeyRing {
  final List<String> lookedUp = [];

  @override
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace) {
    lookedUp.add(namespace);
    return super.currentPublic(owner, namespace);
  }
}

/// Counts the reads of the keyfile it holds.
class _CountingKeysIo extends InMemoryAtKeysIo {
  int reads = 0;

  @override
  FutureOr<AtKeys> read(String atsign) {
    reads++;
    return super.read(atsign);
  }
}

/// A filing over a fresh keyfile for [_alice], holding a private for each of
/// [namespaces] under made-up kids.
Future<NskeyPrivateFiling> _filing(InMemoryAtKeysIo io,
    [Iterable<String> namespaces = const []]) async {
  await io.write(_alice, AtKeys());
  final filing = NskeyPrivateFiling(keysIo: io, atSign: _alice);
  for (final namespace in namespaces) {
    await _file(filing, namespace);
  }
  return filing;
}

Future<void> _file(NskeyPrivateFiling filing, String namespace) async {
  expect(
      await filing.store(
          namespace: namespace,
          nskeyKid: 'kid${namespace.hashCode.toUnsigned(20)}',
          seed: NskeySeed(Uint8List(32))),
      isTrue);
}

class _FakeMonitor extends Fake implements Monitor {
  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;
  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;
  @override
  Future<void> start({int? lastNotificationTime}) async {}
  @override
  void stop() {}
  @override
  Stream<NotificationListenerState> get currentStateStream =>
      const Stream.empty();
}

/// A value whose key names a dotted namespace in full, or only its last
/// label, is sealed to the namespace key of the most specific namespace the
/// writer holds or the key names; the walk goes up from there.
///
/// Catalogue: features/at_client/pq_dotted_namespace.feature
void main() {
  final logs = RecordedLogs();
  late MockAtClient atClient;
  late CryptoContext context;
  late Map<String, ({AtKey key, String value})> store;

  /// Whose `at/nskey` provider opens a conveyance read back; the writer's
  /// unless a test names a reader.
  _Client? opener;

  setUpAll(() {
    logs.installOn(level: 'info');
    registerFallbackValue(AtKey());
    registerFallbackValue(PutRequestOptions());
    registerFallbackValue(GetRequestOptions());
  });

  setUp(() {
    store = {};
    opener = null;
    logs.records.clear();
    atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
    context = CryptoContext(atClient: atClient);
  });

  /// Wires the mock so a conveyance [writer] puts is sealed by its `at/nskey`
  /// provider and kept, and a later get replays it from the wire.
  void wire(_Client writer) {
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = inv.positionalArguments[1] as String;
      final options =
          inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
      final sealed = options?.alreadyEncrypted == true
          ? value
          : await writer.nskey.encrypt(context, key, value);
      store[key.toString()] = (key: key, value: sealed);
      return true;
    });
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      final asked = inv.positionalArguments[0] as AtKey;
      final held = store[asked.toString()];
      if (held == null) throw KeyNotFoundException(asked.toString());
      final reparsed = AtKey.fromString(held.key.toString())
        ..metadata.appMetadata = held.key.metadata.appMetadata;
      await (opener ?? writer).nskey.decrypt(context, reparsed, held.value);
      return AtValue()..value = held.value;
    });
  }

  /// [key] as the write pipeline seals it: the content-key pre-pass, then the
  /// data provider.
  Future<String> write(_Client c, AtKey key, String plaintext) async {
    await c.manager.ensureCurrent(context, key);
    return c.data.encrypt(context, key, plaintext);
  }

  /// [written] as a reader sees it: re-parsed from the wire, with the
  /// metadata the writer stamped.
  AtKey fromWire(AtKey written) => AtKey.fromString(written.toString())
    ..metadata.appMetadata = written.metadata.appMetadata;

  Map<String, dynamic> stamped(AtKey written) =>
      written.metadata.appMetadata!.additional!;

  /// The conveyance records sealed under [namespace]'s key.
  Iterable<String> conveyancesIn(String namespace) =>
      store.keys.where((k) => k.contains('.__ck.$namespace@'));

  test(
      'A key read from its string form is sealed like one built with its '
      'namespace', () async {
    final c = _Client(InMemoryNskeyKeyRing());
    final kid = await _hold(c.ring, _alice, 'todos.demos');
    wire(c);

    final parsed = AtKey.fromString('x.todos.demos$_alice');
    await write(c, parsed, 'parsed');
    final built = AtKey()
      ..key = 'y'
      ..namespace = 'todos.demos'
      ..sharedBy = _alice;
    await write(c, built, 'built');

    expect(stamped(parsed)['ckNs'], 'todos.demos',
        reason: 'sealed at the namespace the key names in full, not its '
            'last label');
    expect(stamped(parsed)['ckKid'], stamped(built)['ckKid'],
        reason: 'under the very content key a key built with its namespace '
            'uses');
    expect(stamped(parsed)['ns'], 'todos.demos',
        reason: 'the value records the level its walk started at');
    expect(
        store[conveyancesIn('todos.demos').single]!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        kid);
  });

  test(
      'An explicit narrower namespace under a broader holding starts at the '
      'narrower level', () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'demos');
    await _publish(c.ring, _bob, 'demos');
    final bobsNarrower = await _publish(c.ring, _bob, 'todos.demos');
    atClient.getPreferences().crypto = CryptoConfig.nskey(keyRing: c.ring);
    wire(c);

    final key = AtKey()
      ..key = 'x'
      ..namespace = 'todos.demos'
      ..sharedBy = _alice
      ..sharedWith = _bob;
    await write(c, key, 'shared');

    expect(stamped(key)['ckNs'], 'todos.demos',
        reason: 'the key names the narrower level, so its walk starts there '
            'whatever the writer holds');
    expect(
        store['$_bob:${stamped(key)['ckKid']}.__ck.todos.demos$_alice']!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        bobsNarrower,
        reason: "sealed under bob's todos.demos key");
  });

  test(
      "The writer's level absent at the recipient seals at the recipient's "
      'broader level', () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'todos.demos');
    final bobsDemos = await _publish(c.ring, _bob, 'demos');
    wire(c);
    when(() => atClient.ensureReachable(any(), timeout: any(named: 'timeout')))
        .thenAnswer((_) async => AtReachabilityResult(AtReachability.failed,
            error: AtException('this enrollment is not authorised for '
                'demos')));

    final key = AtKey.fromString('$_bob:x.todos.demos$_alice');
    await write(c, key, 'shared');

    expect(stamped(key)['ckNs'], 'demos',
        reason: "the walk goes up from alice's level to the one bob publishes");
    expect(
        store[conveyancesIn('demos').single]!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        bobsDemos);
    expect(
        store.keys
            .where((k) => k.contains('.__ck.') && !k.startsWith('$_bob:')),
        isEmpty,
        reason: 'alice holds no key covering demos, so the share has no '
            'sibling copy');
    expect(
        logs
            .at('WARNING')
            .where((m) => m.contains('demos') && m.contains('no sibling copy')),
        hasLength(1));
  });

  test("A name that only ends with a held namespace's letters is not covered",
      () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'demos');
    wire(c);

    await expectLater(
        c.manager.ensureCurrent(context, AtKey.fromString('x.mydemos$_alice')),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.namespace, 'namespace', 'mydemos')));
    expect(conveyancesIn('demos'), isEmpty);
  });

  test('A bare namespace as a key is not covered by that namespace', () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'todos.demos');
    wire(c);

    await expectLater(
        c.manager
            .ensureCurrent(context, AtKey.fromString('todos.demos$_alice')),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.namespace, 'namespace', 'demos')));
    expect(store, isEmpty, reason: 'no content key is cut');
    expect(c.cache.current(_alice, 'todos.demos'), isNull);
  });

  test(
      'Of two held levels, the more specific seals, and the writer reads it '
      'back', () async {
    // NOTE: grants are the atServer's check; what this client holds is what
    // decides where a value is sealed.
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'demos');
    await _hold(c.ring, _alice, 'todos.demos');
    wire(c);

    final key = AtKey.fromString('x.todos.demos$_alice');
    final ciphertext = await write(c, key, 'memo');

    expect(stamped(key)['ckNs'], 'todos.demos');
    expect(conveyancesIn('demos'), isEmpty);
    expect(await c.data.decrypt(context, fromWire(key), ciphertext), 'memo');
  });

  test(
      'A broader-grant reader without the narrower private cannot open the '
      'value', () async {
    // NOTE: bob shares with alice, so the reader is an enrollment of alice's
    // that a notification of the value reaches.
    final pair = await XWingKeyPair.generate();
    final writer = _Client(InMemoryNskeyKeyRing());
    await _hold(writer.ring, _bob, 'todos.demos');
    writer.ring
        .seedPublicOnly(_alice, 'todos.demos', publicKey: pair.publicKeyBytes);
    when(() => atClient.getCurrentAtSign()).thenReturn(_bob);
    atClient.getPreferences().crypto = CryptoConfig.nskey(keyRing: writer.ring);
    wire(writer);
    final key = AtKey.fromString('$_alice:x.todos.demos$_bob');
    final ciphertext = await write(writer, key, 'memo');
    expect(stamped(key)['ckNs'], 'todos.demos',
        reason: "the precondition: sealed under alice's todos.demos key");

    final reader = _Client(InMemoryNskeyKeyRing());
    await _hold(reader.ring, _alice, 'demos');
    reader.ring
        .seedPublicOnly(_alice, 'todos.demos', publicKey: pair.publicKeyBytes);
    when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
    opener = reader;

    await expectLater(
        reader.data.decrypt(context, fromWire(key), ciphertext),
        throwsA(isA<NskeyPrivateUnavailableException>()
            .having((e) => e.namespace, 'namespace', 'todos.demos')));

    expect(NotificationServiceImpl.parkTtl, const Duration(minutes: 6),
        reason: 'how long a notification waits for the private');
    final service = await _notificationsFor(reader, store);
    addTearDown(service.stopAllSubscriptions);
    final dropped = <DroppedNotification>[];
    service.droppedEvents.listen(dropped.add);
    service.subscribe(shouldDecrypt: true).listen((_) {});
    NotificationServiceImpl.parkTtl = const Duration(milliseconds: 50);
    addTearDown(() => NotificationServiceImpl.parkTtl =
        NskeyPrivateFiling.conveyanceWait + const Duration(minutes: 1));

    await service.handleNotificationReceipt(_frame(key, ciphertext, 'n-1'));
    await Future<void>.delayed(Duration.zero);
    expect(service.parkedCount, 1, reason: 'parked first');
    expect(dropped, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    await service.handleNotificationReceipt(_frame(key, ciphertext, 'n-2'));
    await Future<void>.delayed(Duration.zero);
    expect(dropped.single.reason,
        allOf(contains('todos.demos'), contains('did not arrive within')),
        reason: 'then dropped once the park ttl passes');
    expect(logs.at('WARNING').where((m) => m.contains('Dropping parked')),
        hasLength(1));
  });

  test(
      'Rotating the content key of a key read from its string form rotates '
      'at the start level', () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'todos.demos');
    wire(c);
    final key = AtKey.fromString('x.todos.demos$_alice');
    await write(c, key, 'memo');
    final first = stamped(key)['ckKid'];

    final rotated = await c.manager
        .rotateContentKey(context, AtKey.fromString('x.todos.demos$_alice'));

    expect(rotated.ckKid, isNot(first));
    expect(c.cache.current(_alice, 'todos.demos')!.ckKid, rotated.ckKid,
        reason: 'cut at todos.demos, the level the value was sealed at');
    expect(conveyancesIn('todos.demos'), hasLength(2));
    expect(conveyancesIn('demos'), isEmpty);
  });

  test('A key outside every held namespace is not sealed to a narrower one',
      () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'todos.demos');
    wire(c);

    await expectLater(
        c.manager.ensureCurrent(context, AtKey.fromString('x.demos$_alice')),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.namespace, 'namespace', 'demos')));
    expect(conveyancesIn('todos.demos'), isEmpty);
  });

  test("A key's name cannot steer the seal to a broader namespace's key",
      () async {
    final c = _Client(InMemoryNskeyKeyRing());
    await _hold(c.ring, _alice, 'todos.demos');
    await _publish(c.ring, _alice, 'demos');
    wire(c);

    final key = AtKey.fromString('x.todos.demos$_alice');
    await write(c, key, 'memo');

    expect(stamped(key)['ckNs'], 'todos.demos');
    expect(conveyancesIn('demos'), isEmpty,
        reason: "the demos key another enrollment published is not this "
            "value's");
  });

  test('A value written before the fix still opens', () async {
    final before = _Client(InMemoryNskeyKeyRing());
    final pair = await XWingKeyPair.generate();
    before.ring.seedKeypair(_alice, 'demos',
        publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
    wire(before);
    final key = AtKey.fromString('x.todos.demos$_alice');
    final ciphertext = await write(before, key, 'memo');
    expect(stamped(key)['ckNs'], 'demos',
        reason: 'the precondition: written where the last label sealed it');

    final after = _Client(InMemoryNskeyKeyRing());
    after.ring.seedKeypair(_alice, 'demos',
        publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
    await _hold(after.ring, _alice, 'todos.demos');
    opener = after;

    expect(await after.data.decrypt(context, fromWire(key), ciphertext), 'memo',
        reason: 'the reader opens it under the recorded ckNs');
  });

  test('A grant spelt in capitals covers its key', () async {
    final c = _Client(_FilingRing(await _filing(InMemoryAtKeysIo(), [
      'Todos.Demos',
    ])));
    await _hold(c.ring, _alice, 'todos.demos');
    wire(c);

    final key = AtKey.fromString('x.todos.demos$_alice');
    await write(c, key, 'memo');

    expect(stamped(key)['ckNs'], 'todos.demos');
  });

  test('The start level is worked out offline', () async {
    final io = _CountingKeysIo();
    final filing = await _filing(io, ['todos.demos']);
    final resolver =
        NskeyResolver(PublishedNskeyKeyRing(atClient, privateFiling: filing));
    final key = AtKey.fromString('x.todos.demos$_alice');
    io.reads = 0;

    expect(await resolver.startLevelOf(_alice, key), 'todos.demos');
    expect(await resolver.startLevelOf(_alice, key), 'todos.demos');

    expect(io.reads, 1,
        reason: 'what it has filed is read from the keyfile once, and kept');
    verifyNever(() => atClient.getRemoteSecondary());
    verifyNever(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions')));
    expect(await resolver.startLevelOf(_bob, key), 'demos',
        reason: "another atSign's privates are never this client's");
  });

  group('Given a client holding a filed todos.demos private', () {
    test(
        'when its atSign is spelt in another case, then its start level is '
        'still worked out from what it holds', () async {
      final ring = PublishedNskeyKeyRing(atClient,
          privateFiling: await _filing(InMemoryAtKeysIo(), ['todos.demos']));
      final key = AtKey.fromString('x.todos.demos$_alice');

      expect(
          await NskeyResolver(ring).startLevelOf('@ALICE', key), 'todos.demos');
      final inMemory = InMemoryNskeyKeyRing();
      await _hold(inMemory, _alice, 'todos.demos');
      expect(await NskeyResolver(inMemory).startLevelOf('@ALICE', key),
          'todos.demos');
    });
  });

  test('A namespace private filed after start is used from the next write',
      () async {
    final filing = await _filing(InMemoryAtKeysIo(), ['demos']);
    final c = _Client(_FilingRing(filing));
    await _hold(c.ring, _alice, 'demos');
    await _hold(c.ring, _alice, 'todos.demos');
    wire(c);
    final before = AtKey.fromString('x.todos.demos$_alice');
    await write(c, before, 'before');
    expect(stamped(before)['ckNs'], 'demos',
        reason: 'the precondition: what it held at start decides');

    await _file(filing, 'todos.demos');
    final after = AtKey.fromString('x.todos.demos$_alice');
    await write(c, after, 'after');

    expect(stamped(after)['ckNs'], 'todos.demos');
  });

  group('Given a client holding a todos.demos private', () {
    test(
        "when it writes a note in a todo's notes sub-collection, then no "
        'namespace key is looked up at a level named after the todo', () async {
      final ring = _LookupRecordingRing();
      final c = _Client(ring);
      await _hold(ring, _alice, 'todos.demos');
      wire(c);
      // NOTE: the key AtCollection composes for item n1 of the notes
      // sub-collection of todo t3 in the todos collection.
      final note = AtKey.fromString('n1.notes.t3.todos.todos.demos$_alice');

      await write(c, note, 'a note');

      expect(stamped(note)['ckNs'], 'todos.demos');
      expect(ring.lookedUp, isNotEmpty, reason: 'the positive control');
      expect(ring.lookedUp.where((ns) => ns.contains('t3')), isEmpty,
          reason: 'looked up: ${ring.lookedUp}');
    });
  });

  group('Given a client holding a todos.demos private only', () {
    late _Client c;

    setUp(() async {
      c = _Client(InMemoryNskeyKeyRing());
      await _hold(c.ring, _alice, 'todos.demos');
      wire(c);
    });

    test(
        'when it writes x.mytodos.demos, which ends with todos.demos but not '
        'after a dot, then its walk starts at demos', () async {
      await expectLater(
          c.manager.ensureCurrent(
              context, AtKey.fromString('x.mytodos.demos$_alice')),
          throwsA(isA<NamespaceKeyUnavailableException>()
              .having((e) => e.namespace, 'namespace', 'demos')));
      expect(store, isEmpty);
    });
  });

  group('Given a client holding a private in a reserved namespace', () {
    late _Client c;

    setUp(() async {
      c = _Client(InMemoryNskeyKeyRing());
      for (final reserved in ['e1.a.__e', '__manage', '__atserver']) {
        await _hold(c.ring, _alice, reserved);
      }
      wire(c);
    });

    test(
        'when it writes a key under that namespace, then its walk starts at '
        "the key's own namespace", () async {
      await expectLater(
          c.manager
              .ensureCurrent(context, AtKey.fromString('x.e1.a.__e$_alice')),
          throwsA(isA<NamespaceKeyUnavailableException>()
              .having((e) => e.namespace, 'namespace', '__e')));
      expect(store, isEmpty);
    });
  });

  group('Given bob publishing a key for todos.demos', () {
    test(
        'when the readiness check is asked about Todos.Demos, then it answers '
        'for todos.demos', () async {
      final c = _Client(InMemoryNskeyKeyRing());
      await _publish(c.ring, _bob, 'todos.demos');

      expect(await c.data.isReadyFor(context, _bob, 'Todos.Demos'), isTrue);
    });
  });
}

/// A notification service whose crypto is [reader]'s, reading conveyances
/// back from [store] the way the reader's atClient would.
Future<NotificationServiceImpl> _notificationsFor(
    _Client reader, Map<String, ({AtKey key, String value})> store) async {
  final atClient = MockAtClientImpl();
  final context = CryptoContext(atClient: atClient);
  when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
  when(() => atClient.atSign).thenReturn(_alice.toAtsign());
  final preference = AtClientPreference(posture: PqPosture.pqActive)
    ..namespace = 'todos.demos'
    ..crypto = CryptoConfig(
      defaultProviderId: reader.data.id,
      providers: [reader.data, reader.nskey],
      keyRing: reader.ring,
    );
  when(() => atClient.getPreferences()).thenReturn(preference);
  when(() => atClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions')))
      .thenAnswer((_) async => true);
  when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions')))
      .thenAnswer((inv) async {
    final asked = inv.positionalArguments[0] as AtKey;
    final held = store[asked.toString()];
    if (held == null) throw KeyNotFoundException(asked.toString());
    final reparsed = AtKey.fromString(held.key.toString())
      ..metadata.appMetadata = held.key.metadata.appMetadata;
    await reader.nskey.decrypt(context, reparsed, held.value);
    return AtValue()..value = held.value;
  });
  return await NotificationServiceImpl.create(atClient,
      monitor: _FakeMonitor(),
      secondaryAddressFinder: defaultAtDirectory) as NotificationServiceImpl;
}

/// A notification of [key], which [_bob] shared with [_alice], carrying
/// [ciphertext] and the metadata it was sealed with.
String _frame(AtKey key, String ciphertext, String id) =>
    'notification: ${jsonEncode({
          'id': id,
          'key': key.toString(),
          'from': _bob,
          'to': _alice,
          'epochMillis': DateTime.now().millisecondsSinceEpoch,
          'value': ciphertext,
          'operation': 'update',
          'messageType': MessageTypeEnum.key.toString(),
          AtConstants.isEncrypted: true,
          'metadata': {
            AtConstants.appMetadata:
                Metadata.encodeAppMetadata(key.metadata.appMetadata!),
          },
        })}\n';
