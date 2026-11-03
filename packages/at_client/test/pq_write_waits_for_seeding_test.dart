import 'dart:async';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show PairwiseSecretSharing;
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_client/src/crypto/nskey/start_up_seeding.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart'
    show SecretStore;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'fake_enrollment_directory.dart';
import 'test_utils/mocks.dart';

const _alice = '@alice';

/// A ring whose held namespaces are [held], set as a start-up would leave
/// them, which records each lookup.
class _Ring extends InMemoryNskeyKeyRing {
  final Set<String> held = {};
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

/// A ring whose next lookup answers what it read, once [hold] completes.
class _HeldRing extends _Ring {
  Completer<void>? hold;

  @override
  Future<NskeyAdvertisement?> currentPublic(
      String owner, String namespace) async {
    final answer = await super.currentPublic(owner, namespace);
    final held = hold;
    hold = null;
    await held?.future;
    return answer;
  }
}

/// A ring whose atServer cannot be reached.
class _UnreachableRing extends _Ring {
  @override
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace) =>
      throw AtException('$owner:$namespace could not be read: the atServer '
          'is unreachable');
}

/// A key ring over an atServer that has nothing published and lets nothing
/// be minted.
class _PublishingNothing extends PublishedNskeyKeyRing {
  _PublishingNothing(super.atClient);

  @override
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace) async =>
      null;

  @override
  Future<NskeyAdvertisement> mintAndPublish(String namespace,
          {Future<void> Function(List<String> nskeyKids)? conveyFirst,
          NskeyAfterPublish? afterPublish,
          Duration? lockTtl}) =>
      throw StateError('nothing may be minted here');
}

/// A ring whose client's start-up has asked for the privates in [asks], keyed
/// `namespace|nskeyKid`.
class _AskingRing extends _Ring implements AwaitsStartUpAsk {
  final Map<String, Future<void>> asks = {};

  @override
  Future<void>? startUpAsksPending;

  @override
  Future<void>? startUpAskFor(String namespace, String nskeyKid) =>
      asks['$namespace|$nskeyKid'];
}

class _MockSharing extends Mock implements PairwiseSecretSharing {}

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
  Future<String> seed(String namespace, {XWingKeyPair? generated}) async {
    final pair = generated ?? await XWingKeyPair.generate();
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
      'A write in a namespace start-up will not seed refuses without waiting '
      'for a mint', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);

    await expectLater(
        atOnce(write(c, _built('x', 'other.app'))), refusedNaming('other.app'));
  });

  test(
      'A write whose name only ends with the letters of a namespace start-up '
      'seeds refuses without waiting', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);

    await expectLater(
        atOnce(write(c, AtKey.fromString('x.mytodos.demos$_alice'))),
        refusedNaming('demos'));
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

  test('A write that finds its key does not wait for start-up', () async {
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

    final kid = await c.seed('todos.demos');
    c.seeding.finish();
    await Future.wait(writing);

    expect({for (final key in keys) stamped(key)['ckNs']}, {'todos.demos'});
    final sealedTo = {
      for (final MapEntry(key: name, value: conveyance) in store.entries)
        if (name.contains('.__ck.todos.demos'))
          conveyance.key.metadata.appMetadata!.additional!['nskeyKid']
    };
    expect(sealedTo, {kid},
        reason: 'every write is sealed under the one key start-up published');
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

  test('A start-up that cannot read its grants ends the wait with its reason',
      () async {
    final c = _Client(_Ring());
    wire(c);
    final writing = write(c, AtKey.fromString('x.todos.demos$_alice'));
    expect(await _pending(writing), isTrue,
        reason: 'the premise: it waits for start-up to say what it seeds');

    c.seeding.failedAll('the enrollment could not be read');
    c.seeding.finish();

    await expectLater(
        atOnce(writing),
        throwsA(isA<NamespaceKeyUnavailableException>().having((e) => e.message,
            'message', contains('the enrollment could not be read'))));
  });

  test(
      'Given a start-up that failed to seed the namespaces it named, when a '
      'write in another namespace finds no key, then its refusal carries no '
      'reason of start-up\'s', () async {
    final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
    wire(c);
    c.seeding.failedAll('the mint lock is held elsewhere');
    c.seeding.finish();

    await expectLater(
        atOnce(write(c, AtKey.fromString('x.other.app$_alice'))),
        throwsA(isA<NamespaceKeyUnavailableException>().having(
            (e) => e.message, 'message', isNot(contains('mint lock')))));
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

    verifyNever(
        () => atClient.ensureReachable(any(), timeout: any(named: 'timeout')));
    expect(
        store[store.keys.singleWhere((k) => k.contains('.__ck.todos.demos'))]!
            .key
            .metadata
            .appMetadata!
            .additional!['nskeyKid'],
        adopted);
  });

  group("Given start-up's own seeding of todos.demos", () {
    /// The seeding the primary enrollment runs at start-up, with a
    /// secret-sharing substrate whose directory lists this enrollment with no
    /// key package when [withSharing], and none otherwise.
    Future<NskeySeeding> ownSeeding({required bool withSharing}) async {
      atClient.getPreferences().namespace = 'todos.demos';
      final io = InMemoryAtKeysIo();
      await io.write(_alice, AtKeys());
      _MockSharing? sharing;
      if (withSharing) {
        sharing = _MockSharing();
        when(() => sharing!.directory).thenReturn(
            FakeEnrollmentDirectory()..authorize('todos.demos', 'primary'));
        when(() => sharing!.enrollmentId).thenReturn('primary');
        when(() => sharing!.secretStore).thenReturn(SecretStore());
      }
      return NskeySeeding(
          atClient: atClient,
          ring: _PublishingNothing(atClient),
          sharing: sharing,
          privateFiling: NskeyPrivateFiling(keysIo: io, atSign: _alice));
    }

    for (final (:withSharing, :given, :because) in [
      (
        withSharing: true,
        given: 'the enrollment carries no key package',
        because: 'carries no key package'
      ),
      (
        withSharing: false,
        given: 'the client has no secret-sharing substrate',
        because: 'no secret-sharing substrate'
      ),
    ]) {
      test(
          'when it mints nothing because $given, then a waiting write is '
          'refused saying so', () async {
        final c = _Client(_Ring());
        wire(c);
        final seeding = await ownSeeding(withSharing: withSharing);
        final writing = write(c, AtKey.fromString('x.todos.demos$_alice'));
        expect(await _pending(writing), isTrue);

        await seeding.seed(progress: c.seeding);
        c.seeding.finish();

        await expectLater(
            atOnce(writing),
            throwsA(isA<NamespaceKeyUnavailableException>()
                .having((e) => e.namespace, 'namespace', 'todos.demos')
                .having((e) => e.message, 'message', contains(because))));
      });
    }
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
      StartUpSeeding.wait = const Duration(seconds: 1);
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      await c.seed('demos');
      wire(c);
      final generated = await XWingKeyPair.generate();
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('todos.demos', generated: generated);
      await writing;

      expect(stamped(key)['ckNs'], 'todos.demos');
    });
  });

  group(
      "Given start-up said it seeds todos.demos, from the grants its keyfile "
      'recorded', () {
    test(
        'when its grant read adds other.app, then a write in other.app waits '
        'for seeding', () async {
      final c = _Client(_Ring())
        ..seeding.announcing()
        ..seeding.announced({'todos.demos'})
        ..seeding.seeding({'todos.demos', 'other.app'});
      wire(c);
      final key = _built('x', 'other.app');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('other.app');
      c.seeding.finish();
      await atOnce(writing);

      expect(stamped(key)['ckNs'], 'other.app');
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

  group("Given a write whose search is in flight as start-up's seeding ends",
      () {
    test(
        'when start-up publishes its key as the search finds nothing, then the '
        'write searches again and seals under that key', () async {
      final hold = Completer<void>();
      final c = _Client(_HeldRing()..hold = hold)
        ..seeding.seeding({'todos.demos'});
      wire(c);
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('todos.demos');
      c.seeding.finish();
      hold.complete();
      await atOnce(writing);

      expect(stamped(key)['ckNs'], 'todos.demos');
    });

    test(
        'when start-up publishes its key as the search finds only demos, then '
        'the write searches again and seals at todos.demos', () async {
      final hold = Completer<void>();
      final c = _Client(_HeldRing())..seeding.seeding({'todos.demos'});
      await c.seed('demos');
      (c.ring as _HeldRing).hold = hold;
      wire(c);
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('todos.demos');
      c.seeding.finish();
      hold.complete();
      await atOnce(writing);

      expect(stamped(key)['ckNs'], 'todos.demos');
    });
  });

  group("Given a write waiting for start-up's seeding step", () {
    test(
        'when its key is published but the step has not finished as the wait '
        'runs out, then the write goes ahead under that key',
        timeout: const Timeout(Duration(seconds: 10)), () async {
      StartUpSeeding.wait = const Duration(seconds: 1);
      final c = _Client(_Ring())..seeding.seeding({'todos.demos'});
      wire(c);
      final generated = await XWingKeyPair.generate();
      final key = AtKey.fromString('x.todos.demos$_alice');
      final writing = write(c, key);
      expect(await _pending(writing), isTrue);

      await c.seed('todos.demos', generated: generated);
      await writing;

      expect(stamped(key)['ckNs'], 'todos.demos');
    });
  });

  group(
      "Given todos.demos's current generation published, its private not "
      'held, and start-up seeding finished', () {
    late _AskingRing ring;
    late _Client c;
    late XWingKeyPair pair;
    late String kid;
    late Completer<void> answer;
    late AtKey key;

    setUp(() async {
      key = _built('x', 'todos.demos');
      ring = _AskingRing();
      c = _Client(ring)..seeding.seeding({'todos.demos'});
      c.seeding.finish();
      pair = await XWingKeyPair.generate();
      kid = ring.seedPublicOnly(_alice, 'todos.demos',
          publicKey: pair.publicKeyBytes);
      answer = Completer<void>();
      wire(c);
    });

    Matcher notYetConveyed() => throwsA(isA<NskeyPrivateNotHeldException>()
        .having((e) => e.nskeyKid, 'nskeyKid', kid)
        .having((e) => e.message, 'message',
            contains('has not yet been conveyed')));

    test(
        'A write that misses while its start-up ask is outstanding waits for '
        'the answer', () async {
      ring.asks['todos.demos|$kid'] = answer.future;

      final writing = write(c, key);
      expect(await _pending(writing), isTrue,
          reason: "it waits for the answer to start-up's ask");
      ring.seedKeypair(_alice, 'todos.demos',
          publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
      answer.complete();
      await writing;

      expect(
          store[store.keys.singleWhere((k) => k.contains('.__ck.todos.demos'))]!
              .key
              .metadata
              .appMetadata!
              .additional!['nskeyKid'],
          kid,
          reason: 'the write succeeds once the answer is filed');
    });

    test(
        'when no answer comes within the bound, then the write throws naming '
        'the generation as not yet conveyed',
        timeout: const Timeout(Duration(seconds: 10)), () async {
      StartUpSeeding.wait = const Duration(milliseconds: 200);
      ring.asks['todos.demos|$kid'] = answer.future;

      await expectLater(write(c, key), notYetConveyed());
    });

    test(
        'when the ask ends with no answer filed, as when the client stops, '
        'then the write throws at once', () async {
      ring.asks['todos.demos|$kid'] = answer.future;

      final writing = write(c, key);
      expect(await _pending(writing), isTrue);
      answer.complete();

      await expectLater(atOnce(writing), notYetConveyed());
    });

    test(
        "A write made before start-up asks for its key's private waits for "
        'the ask and its answer', () async {
      final asking = Completer<void>();
      ring.startUpAsksPending = asking.future;

      final writing = write(c, key);
      expect(await _pending(writing), isTrue,
          reason: 'it waits for start-up to ask');
      ring.asks['todos.demos|$kid'] = answer.future;
      asking.complete();
      expect(await _pending(writing), isTrue,
          reason: 'and then for the answer to that ask');
      ring.seedKeypair(_alice, 'todos.demos',
          publicKey: pair.publicKeyBytes, privateKey: pair.privateKeyBytes);
      answer.complete();
      await writing;

      expect(
          store[store.keys.singleWhere((k) => k.contains('.__ck.todos.demos'))]!
              .key
              .metadata
              .appMetadata!
              .additional!['nskeyKid'],
          kid,
          reason: 'the write goes on once the answer is filed');
    });

    test(
        'when start-up has already made its asks, then the write throws at once',
        () async {
      ring.startUpAsksPending = Future<void>.value();

      await expectLater(atOnce(write(c, key)), notYetConveyed());
    });

    test(
        'when start-up ends without asking, as when the client stops, then the '
        'write throws at once', () async {
      final asking = Completer<void>();
      ring.startUpAsksPending = asking.future;

      final writing = write(c, key);
      expect(await _pending(writing), isTrue);
      asking.complete();

      await expectLater(atOnce(writing), notYetConveyed());
    });

    test('the waits for the ask and for its answer share one bound',
        timeout: const Timeout(Duration(seconds: 10)), () async {
      StartUpSeeding.wait = const Duration(seconds: 2);
      final asking = Completer<void>();
      ring.startUpAsksPending = asking.future;
      final started = DateTime.now();

      final writing = expectLater(write(c, key), notYetConveyed());
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      ring.asks['todos.demos|$kid'] = answer.future;
      asking.complete();
      await writing;

      expect(DateTime.now().difference(started),
          lessThan(const Duration(milliseconds: 2900)),
          reason: 'the wait for the answer takes only what the wait for the '
              'ask left of the bound, not a bound of its own');
    });

    test('when start-up has no ask outstanding, then the write throws at once',
        () async {
      await expectLater(atOnce(write(c, key)), notYetConveyed(),
          reason: 'the control: an ask a read miss made, or none, does not '
              'hold a write up');
    });
  });
}
