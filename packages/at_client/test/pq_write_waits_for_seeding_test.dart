import 'dart:async';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/start_up_seeding.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

const _alice = '@alice';
const _bob = '@bob';

/// A ring whose held namespaces are [held], set as a start-up would leave
/// them, which counts the keys seeded into it and records each lookup.
class _Ring extends InMemoryNskeyKeyRing {
  final Set<String> held = {};
  int mints = 0;
  final List<String> lookups = [];

  @override
  Future<Set<String>> heldNamespaces(String owner) async =>
      owner == _alice ? {...held} : const {};

  @override
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace) {
    lookups.add('$owner:$namespace');
    return super.currentPublic(owner, namespace);
  }
}

/// A ring whose atServer cannot be reached.
class _UnreachableRing extends _Ring {
  @override
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace) =>
      throw AtException('$owner:$namespace could not be read: the atServer '
          'is unreachable');
}

/// One client's providers over [ring], with [seeding] in the part its
/// start-up plays.
class _Client {
  final _Ring ring;
  final ContentKeyCache cache = ContentKeyCache();
  late final NskeyProvider nskey = NskeyProvider(keyRing: ring, cache: cache);
  late final CkManager manager = CkManager(cache: cache, keyRing: ring);
  late final SymmetricAesGcmProvider data =
      SymmetricAesGcmProvider(cache: cache, ckManager: manager);
  final StartUpSeeding seeding = StartUpSeeding();

  _Client(this.ring) {
    manager.startUpSeeding = seeding;
  }

  /// What start-up does for [namespace]: mints, files and publishes its key.
  Future<String> seed(String namespace) async {
    final pair = await XWingKeyPair.generate();
    ring.mints++;
    final kid = ring.seedKeypair(_alice, namespace,
        publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
    ring.held.add(namespace);
    return kid;
  }
}

/// Alice's self key [key] in [namespace], built with its namespace in full.
AtKey _built(String key, String namespace) => AtKey()
  ..key = key
  ..namespace = namespace
  ..sharedBy = _alice;

Future<String> _publish(_Ring ring, String owner, String namespace) async {
  final pair = await XWingKeyPair.generate();
  return ring.seedPublicOnly(owner, namespace, publicKey: pair.publicKeyBytes);
}

/// Whether [future] is still running after the event queue has drained.
Future<bool> _pending(Future<void> future) async {
  var done = false;
  unawaited(future.then((_) => done = true, onError: (_) => done = true));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return !done;
}

/// A pqActive write that finds no namespace key while its client's start-up
/// has still to seed one waits for that seeding, bounded, and then resolves
/// again.
///
/// Catalogue: features/at_client/pq_write_waits_for_seeding.feature
void main() {
  late MockAtClient atClient;
  late CryptoContext context;
  late Map<String, ({AtKey key, String value})> store;

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(PutRequestOptions());
    registerFallbackValue(GetRequestOptions());
  });

  setUp(() {
    store = {};
    atClient = MockAtClient(posture: PqPosture.pqActive);
    when(() => atClient.getCurrentAtSign()).thenReturn(_alice);
    context = CryptoContext(atClient: atClient);
  });

  tearDown(() => StartUpSeeding.wait = const Duration(seconds: 30));

  /// Wires the mock so a conveyance [c] puts is sealed and kept.
  void wire(_Client c) {
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = inv.positionalArguments[1] as String;
      final options =
          inv.namedArguments[#putRequestOptions] as PutRequestOptions?;
      store[key.toString()] = (
        key: key,
        value: options?.alreadyEncrypted == true
            ? value
            : await c.nskey.encrypt(context, key, value)
      );
      return true;
    });
    when(() => atClient.ensureReachable(any(), timeout: any(named: 'timeout')))
        .thenAnswer((_) async =>
            const AtReachabilityResult(AtReachability.postureDoesNotSeed));
  }

  Future<String> write(_Client c, AtKey key) async {
    await c.manager.ensureCurrent(context, key);
    return c.data.encrypt(context, key, 'memo');
  }

  Map<String, dynamic> stamped(AtKey key) =>
      key.metadata.appMetadata!.additional!;

  Matcher refusedNaming(String namespace) =>
      throwsA(isA<NamespaceKeyUnavailableException>()
          .having((e) => e.namespace, 'namespace', namespace));

  /// [future], failing the test rather than waiting past a second.
  Future<T> atOnce<T>(Future<T> future) =>
      future.timeout(const Duration(seconds: 1),
          onTimeout: () => fail('it waited, and was to answer at once'));

  test(
      "A write in the client's namespace right after it opens waits for "
      "start-up's key", () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);
    final key = AtKey.fromString('x.todos.demos$_alice');

    final writing = write(c, key);
    expect(await _pending(writing), isTrue,
        reason: 'it waits while start-up has not published the key');
    final kid = await c.seed('todos.demos');
    c.seeding.finish();
    await writing;

    expect(stamped(key)['ckNs'], 'todos.demos');
    expect(
        store[store.keys.singleWhere((k) => k.contains('.__ck.todos.demos'))]!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        kid);
  });

  test("An enrollment's write in a namespace it is granted waits the same way",
      () async {
    final c = _Client(_Ring());
    wire(c);
    final key = AtKey.fromString('x.todos.demos$_alice');

    final writing = write(c, key);
    expect(await _pending(writing), isTrue,
        reason: 'it waits for start-up to read its grants');
    c.seeding.seeding({'todos.demos'});
    expect(await _pending(writing), isTrue,
        reason: 'then for start-up to seed the granted namespace');
    await c.seed('todos.demos');
    c.seeding.finish();
    await writing;

    expect(stamped(key)['ckNs'], 'todos.demos');
  });

  test(
      "A share right after opening waits for the writer's own start-up before "
      'choosing where to seal', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    final bobs = await _publish(c.ring, _bob, 'todos.demos');
    atClient.getPreferences().crypto = CryptoConfig.nskey(keyRing: c.ring);
    wire(c);
    final key = AtKey.fromString('$_bob:x.todos.demos$_alice');

    final writing = write(c, key);
    expect(await _pending(writing), isTrue);
    await c.seed('todos.demos');
    c.seeding.finish();
    await writing;

    expect(stamped(key)['ckNs'], 'todos.demos');
    expect(
        store['$_bob:${stamped(key)['ckKid']}.__ck.todos.demos$_alice']!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        bobs,
        reason: "sealed under bob's todos.demos key");
  });

  test('A notification right after opening waits the same way', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    await _publish(c.ring, _bob, 'todos.demos');
    atClient.getPreferences()
      ..namespace = 'todos.demos'
      ..crypto = CryptoConfig(
        defaultProviderId: c.data.id,
        providers: [c.data, c.nskey],
        keyRing: c.ring,
      );
    wire(c);
    // NOTE: marked encrypted as notify's default encryptValue marks it before
    // the transformer runs.
    final key = AtKey.fromString('$_bob:x.todos.demos$_alice')
      ..metadata.isEncrypted = true;

    final notifying = NotificationRequestTransformer(atClient)
        .transform(NotificationParams.forUpdate(key, value: 'memo'));
    expect(await _pending(notifying), isTrue);
    await c.seed('todos.demos');
    c.seeding.finish();
    final builder = await notifying;

    expect(builder.value, isNotNull);
    expect(key.metadata.appMetadata!.additional!['ckNs'], 'todos.demos');
  });

  test(
      'A share to a recipient that has published nothing refuses without '
      'waiting', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    await c.seed('todos.demos');
    c.seeding.finish();
    wire(c);

    await expectLater(
        atOnce(write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'))),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.atSign, 'atSign', _bob)
            .having((e) => e.namespace, 'namespace', 'todos.demos')));
  });

  test(
      'A write in a namespace start-up will not seed refuses without waiting '
      'for a mint', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);

    await expectLater(
        atOnce(write(c, _built('x', 'other.app'))), refusedNaming('other.app'));
  });

  test('A write after start-up has finished seeding refuses at once', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    c.seeding.finish();
    wire(c);

    await expectLater(atOnce(write(c, _built('x', 'todos.demos'))),
        refusedNaming('todos.demos'));
    expect(c.ring.lookups, ['$_alice:todos.demos', '$_alice:demos'],
        reason: 'one walk, and no second one after the seeding it missed');
  });

  test('A client whose start-up seeds nothing refuses at once', () async {
    final c = _Client(_Ring());
    c.manager.startUpSeeding = null;
    wire(c);

    await expectLater(atOnce(write(c, _built('x', 'todos.demos'))),
        refusedNaming('todos.demos'));
  });

  test('The wait is bounded', timeout: const Timeout(Duration(seconds: 10)),
      () async {
    expect(StartUpSeeding.wait, const Duration(seconds: 30));
    StartUpSeeding.wait = const Duration(milliseconds: 200);
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);

    await expectLater(
        write(c, AtKey.fromString('x.todos.demos$_alice')),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.namespace, 'namespace', 'todos.demos')
            .having((e) => e.message, 'message',
                contains('start-up has not yet published'))));
  });

  test('A first write with no atServer ends at once', () async {
    final c = _Client(_UnreachableRing())..seeding.seeding({'todos.demos'});
    wire(c);

    await expectLater(
        atOnce(write(c, AtKey.fromString('x.todos.demos$_alice'))),
        throwsA(isA<AtException>()
            .having((e) => e.message, 'message', contains('unreachable'))));
  });

  test('A write the offline restart already allows does not wait', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    await c.seed('todos.demos');
    wire(c);
    final key = AtKey.fromString('x.todos.demos$_alice');

    await atOnce(write(c, key));

    expect(stamped(key)['ckNs'], 'todos.demos');
  });

  test('Stopping the client ends a waiting write', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);
    final writing = write(c, AtKey.fromString('x.todos.demos$_alice'));
    expect(await _pending(writing), isTrue);

    c.seeding.stop();

    await expectLater(atOnce(writing), throwsA(isA<StoppedException>()));
  });

  test('Writes waiting together share one seeding', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);
    final keys = [
      for (var i = 0; i < 5; i++) AtKey.fromString('x$i.todos.demos$_alice')
    ];
    final writing = [for (final key in keys) write(c, key)];
    expect(await _pending(Future.wait(writing)), isTrue);

    await c.seed('todos.demos');
    c.seeding.finish();
    await Future.wait(writing);

    expect({for (final key in keys) stamped(key)['ckNs']}, {'todos.demos'});
    expect(c.ring.mints, 1, reason: 'start-up minted it once');
    verifyNever(
        () => atClient.ensureReachable(any(), timeout: any(named: 'timeout')));
  });

  test('A seeding that fails ends the wait with its reason', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);
    final writing = write(c, AtKey.fromString('x.todos.demos$_alice'));
    expect(await _pending(writing), isTrue);

    c.seeding.failed('todos.demos', 'the mint lock is held elsewhere');
    c.seeding.finish();

    await expectLater(
        atOnce(writing),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.namespace, 'namespace', 'todos.demos')
            .having((e) => e.message, 'message',
                contains('the mint lock is held elsewhere'))));
  });

  test(
      'A key another enrollment minted first is the one a waiting write seals '
      'to', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);
    final key = AtKey.fromString('x.todos.demos$_alice');
    final writing = write(c, key);
    expect(await _pending(writing), isTrue);

    // NOTE: the other enrollment's generation, conveyed to this one, is what
    // start-up adopts; this client mints nothing.
    final pair = await XWingKeyPair.generate();
    final adopted = c.ring.seedKeypair(_alice, 'todos.demos',
        publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
    c.ring.held.add('todos.demos');
    c.seeding.finish();
    await writing;

    expect(c.ring.mints, 0);
    expect(
        store[store.keys.singleWhere((k) => k.contains('.__ck.todos.demos'))]!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        adopted);
  });

  group('Given a share to a recipient that has published nothing', () {
    test(
        "when the writer's own seeding fails, then the share is refused "
        'naming the recipient', () async {
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      wire(c);
      final writing = write(c, AtKey.fromString('$_bob:x.todos.demos$_alice'));
      expect(await _pending(writing), isTrue);

      c.seeding.failed('todos.demos', 'the mint lock is held elsewhere');
      c.seeding.finish();

      await expectLater(
          atOnce(writing),
          throwsA(isA<NamespaceKeyUnavailableException>()
              .having((e) => e.atSign, 'atSign', _bob)));
    });

    test(
        "when the wait for the writer's own start-up runs out, then the share "
        'is refused naming the recipient',
        timeout: const Timeout(Duration(seconds: 10)), () async {
      StartUpSeeding.wait = const Duration(milliseconds: 200);
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      wire(c);

      await expectLater(
          write(c, AtKey.fromString('$_bob:x.todos.demos$_alice')),
          throwsA(isA<NamespaceKeyUnavailableException>()
              .having((e) => e.atSign, 'atSign', _bob)
              .having(
                  (e) => e.message, 'message', isNot(contains('start-up')))));
    });
  });

  group(
      'Given start-up will seed todos.demos and the search finds only demos '
      'published', () {
    Future<void> waitsThenSealsAtTodosDemos(_Client c) async {
      wire(c);
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue,
          reason: 'it waits for seeding rather than sealing at demos');

      await c.seed('todos.demos');
      c.seeding.finish();
      await atOnce(writing);

      expect(stamped(key)['ckNs'], 'todos.demos');
    }

    test(
        'when a write under todos.demos is made before seeding finishes, then '
        'it waits for seeding and seals at todos.demos', () async {
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      await c.seed('demos');

      await waitsThenSealsAtTodosDemos(c);
    });

    test(
        'when a write under todos.demos is made before seeding finishes, and '
        'this enrollment holds no demos private, then it waits for seeding and '
        'seals at todos.demos', () async {
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      await _publish(c.ring, _alice, 'demos');

      await waitsThenSealsAtTodosDemos(c);
    });

    test(
        'when the wait runs out before seeding finishes, then the write '
        'resolves again and seals at todos.demos once that is published',
        timeout: const Timeout(Duration(seconds: 10)), () async {
      StartUpSeeding.wait = const Duration(milliseconds: 300);
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      await c.seed('demos');
      wire(c);
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('todos.demos');
      await writing;

      expect(stamped(key)['ckNs'], 'todos.demos');
    });
  });

  group(
      'Given start-up has not yet said what it seeds, and the search finds '
      'demos published', () {
    test('when a write under todos.demos is made, then it does not wait',
        () async {
      final c = _Client(_Ring());
      await c.seed('demos');
      wire(c);
      final key = AtKey.fromString('x.todos.demos$_alice');

      await atOnce(write(c, key));

      expect(stamped(key)['ckNs'], 'demos');
    });
  });

  group("Given a write waiting for start-up's seeding step", () {
    test(
        'when its key is published but the step has not finished as the wait '
        'runs out, then the write goes ahead under that key',
        timeout: const Timeout(Duration(seconds: 10)), () async {
      StartUpSeeding.wait = const Duration(milliseconds: 300);
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      wire(c);
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('todos.demos');
      await writing;

      expect(stamped(key)['ckNs'], 'todos.demos');
    });
  });
}
