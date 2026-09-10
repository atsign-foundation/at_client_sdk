import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:test/test.dart';

/// Which level of a nested namespace holds the nskey a sender seals to.
void main() {
  const alice = '@alice';

  late XWingKeyPair todosKey;
  late XWingKeyPair deepKey;

  setUpAll(() async {
    todosKey = await XWingKeyPair.generate();
    deepKey = await XWingKeyPair.generate();
  });

  /// A resolver over a ring that records every namespace it is asked about.
  ({NskeyResolver resolver, InMemoryNskeyKeyRing ring, List<String> lookups})
      resolver({Duration? missMemory}) {
    final ring = _CountingRing();
    return (
      resolver: NskeyResolver(ring,
          missMemory: missMemory ?? const Duration(minutes: 15)),
      ring: ring,
      lookups: ring.lookups,
    );
  }

  group('what this client is willing to seal to', () {
    test('the default reaches an owner advertising either KEM', () async {
      // NOTE: the control for the refusal that follows — the same owner and key
      // resolve once the algorithm list is not narrowed.
      final r = resolver();
      r.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      expect((await r.resolver.resolve(alice, 'todos'))?.alg,
          SecretSharingAlgos.xWing);
    });

    test('a narrowed list refuses, and the message names both sides', () async {
      final ring = _CountingRing();
      final narrowed = NskeyResolver(ring,
          sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024]);
      ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      await expectLater(
          narrowed.resolve(alice, 'todos'),
          throwsA(isA<AtEncryptionException>().having(
              (e) => e.message,
              'message',
              allOf(
                  contains(SecretSharingAlgos.xWing),
                  contains(SecretSharingAlgos.mlKem1024),
                  contains('sealsToKeyAlgorithms')))));
    });

    test('a widened advertisement serves each sender the entry IT understands',
        () async {
      // UC-G2.10: a recipient publishes a second algorithm beside the first,
      // and a sender that cannot use one of them still seals under the other.
      //
      // NOTE: the two narrowings run as a differential over ONE advertisement.
      // Either arm alone is satisfied by a build that always seals to a single
      // algorithm; only the pair shows both lists are read.
      final mlKem = SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024)!;
      final second = await mlKem.keyPairFromSeed(mlKem.newSeed());
      final ring = _WidenedRing(NskeyAdvertisement(
        v: nskeyAdvertisementVersion,
        createdAt: DateTime.now().toUtc(),
        keys: [
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.mlKem1024,
              pub: second.publicKey),
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc,
              alg: SecretSharingAlgos.xWing,
              pub: todosKey.publicKeyBytes),
        ],
      ));

      final xWingOnly = await NskeyResolver(ring,
              sealsToKeyAlgorithms: const [SecretSharingAlgos.xWing])
          .resolve(alice, 'todos');
      final mlKemOnly = await NskeyResolver(ring,
              sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024])
          .resolve(alice, 'todos');

      expect(xWingOnly?.alg, SecretSharingAlgos.xWing);
      expect(mlKemOnly?.alg, SecretSharingAlgos.mlKem1024);

      // NOTE: asserted at the key, not at the algorithm name — an entry naming
      // the right algorithm and carrying the wrong key seals to something the
      // recipient cannot open, and the name alone cannot tell.
      expect(xWingOnly?.publicKey, todosKey.publicKeyBytes);
      expect(mlKemOnly?.publicKey, second.publicKey,
          reason: 'each sender is served the entry its own list names, off '
              'one advertisement that carries both — which is what lets the '
              'two ends move independently');
    });

    test('it refuses rather than walking up to a broader namespace', () async {
      // NOTE: walking on would silently seal under another namespace's key, a
      // different content-key scope than the caller asked for.
      final ring = _CountingRing();
      final narrowed = NskeyResolver(ring,
          sealsToKeyAlgorithms: const [SecretSharingAlgos.mlKem1024]);
      ring.seedPublicOnly(alice, 'notes', publicKey: deepKey.publicKeyBytes);
      ring.seedPublicOnly(alice, 'medical.notes',
          publicKey: todosKey.publicKeyBytes);

      await expectLater(narrowed.resolve(alice, 'medical.notes'),
          throwsA(isA<AtEncryptionException>()),
          reason: 'the deeper level was the hit, and a hit this client will '
              'not use is a refusal rather than a reason to keep walking');
    });
  });

  group('candidates', () {
    test('yields every level, most specific first', () {
      expect(NskeyResolver.candidates('d.c.b.a').toList(),
          ['d.c.b.a', 'c.b.a', 'b.a', 'a']);
    });

    test('a single-segment namespace is its own only level', () {
      expect(NskeyResolver.candidates('todos').toList(), ['todos']);
    });
  });

  group('resolve', () {
    test('an exact hit resolves to itself', () async {
      final c = resolver();
      c.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      final r = await c.resolver.resolve(alice, 'todos');

      expect(r?.namespace, 'todos');
      expect(r?.nskeyKid, nskeyKidOf(todosKey.publicKeyBytes));
    });

    test('a composed namespace walks up to the app namespace', () async {
      final c = resolver();
      c.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      final r = await c.resolver.resolve(alice, '__rr.item123.todos');

      expect(r?.namespace, 'todos',
          reason: 'the first hit is the app-namespace boundary, and the walk '
              'is how a sender finds it');
      expect(c.lookups, ['__rr.item123.todos', 'item123.todos', 'todos'],
          reason: 'most specific first');
    });

    test('a deeper key wins over the broader one', () async {
      final c = resolver();
      c.ring
        ..seedPublicOnly(alice, 'notes', publicKey: todosKey.publicKeyBytes)
        ..seedPublicOnly(alice, 'medical.notes',
            publicKey: deepKey.publicKeyBytes);

      final r = await c.resolver.resolve(alice, 'x.medical.notes');

      expect(r?.namespace, 'medical.notes');
      expect(r?.nskeyKid, nskeyKidOf(deepKey.publicKeyBytes),
          reason: 'a tighter nskey is the only way to say "authorised, but '
              'still cannot decrypt" — suffix authorisation already lets a '
              'notes-approved enrollment fetch the record');
    });

    test('an exhausted walk resolves to nothing', () async {
      final c = resolver();

      expect(await c.resolver.resolve(alice, 'a.b.never_used'), isNull);
      expect(c.lookups, ['a.b.never_used', 'b.never_used', 'never_used'],
          reason: 'cold start is the whole walk coming up empty, not the first '
              'level missing');
    });

    test('the walk does not escape into another owner', () async {
      final c = resolver();
      c.ring
          .seedPublicOnly('@bob', 'todos', publicKey: todosKey.publicKeyBytes);

      expect(await c.resolver.resolve(alice, 'x.todos'), isNull);
    });
  });

  group('cost', () {
    test('a level already found empty is not re-probed', () async {
      final c = resolver();
      c.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      await c.resolver.resolve(alice, '__rr.item123.todos');
      c.lookups.clear();

      await c.resolver.resolve(alice, '__rr.item123.todos');

      expect(c.lookups, ['todos'],
          reason: 'the two composed levels are known-empty and skipped; only '
              'the hit is re-asked, and the ring caches that');
    });

    test('a new item still probes its own levels once', () async {
      final c = resolver();
      c.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);
      await c.resolver.resolve(alice, '__rr.item123.todos');
      c.lookups.clear();

      await c.resolver.resolve(alice, '__rr.item124.todos');

      expect(c.lookups, ['__rr.item124.todos', 'item124.todos', 'todos'],
          reason: 'a new item is a namespace never seen, so its levels have to '
              'be probed — this is the irreducible cost, and it is paid once '
              'per item rather than once per write');
    });

    test('a key published after a miss is found on the very next resolve',
        () async {
      // NOTE: at the production default the remembered miss is nowhere near
      // lapsing, so letting it decide the outcome would answer null here. The
      // memory may make a resolution cheaper; it may never make one wrong.
      final c = resolver();
      expect(await c.resolver.resolve(alice, 'x.todos'), isNull,
          reason: 'the premise: nothing is published yet, and this is the '
              'call that stamps the miss');

      c.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      expect((await c.resolver.resolve(alice, 'x.todos'))?.namespace, 'todos',
          reason: 'a namespace that gains a key is reachable at once. The '
              'memory is a hint that saves work when some other level '
              'resolves; when nothing does, the skipped levels are asked for '
              'real before null is returned');
    });

    test('a resolution that skips nothing probes each level once', () async {
      final c = resolver();

      expect(await c.resolver.resolve(alice, 'x.todos'), isNull);

      expect(c.lookups, ['x.todos', 'todos'],
          reason: 'each level asked once and no more: nothing was skipped, so '
              'the answer was already trustworthy and there is nothing to '
              're-ask');
    });

    test('a repeated cold resolve pays the walk again, deliberately', () async {
      final c = resolver();
      await c.resolver.resolve(alice, 'x.todos');
      c.lookups.clear();

      await c.resolver.resolve(alice, 'x.todos');

      expect(c.lookups, ['x.todos', 'todos'],
          reason: 'every level was a remembered miss, so the first walk asked '
              'nothing and the second asked them all. This is the price of a '
              'null that is never stale, and it is charged only to callers '
              'about to be told no');
    });

    test('a miss is forgotten once its memory lapses', () async {
      final c = resolver(missMemory: const Duration(milliseconds: 1));
      expect(await c.resolver.resolve(alice, 'x.todos'), isNull);
      await Future.delayed(const Duration(milliseconds: 20));
      c.lookups.clear();

      c.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      expect((await c.resolver.resolve(alice, 'x.todos'))?.namespace, 'todos',
          reason: 'a namespace that gains a key must become reachable');
    });

    test('a deeper key is never skipped because a broader one was seen',
        () async {
      // NOTE: the property that rules out remembering hits — warming a broader
      // level must not make a deeper key invisible.
      final c = resolver();
      c.ring
        ..seedPublicOnly(alice, 'notes', publicKey: todosKey.publicKeyBytes)
        ..seedPublicOnly(alice, 'medical.notes',
            publicKey: deepKey.publicKeyBytes);

      await c.resolver.resolve(alice, 'x.notes');
      final r = await c.resolver.resolve(alice, 'y.medical.notes');

      expect(r?.namespace, 'medical.notes',
          reason: 'resolving x.notes first must not hide medical.notes');
    });
  });
}

/// An [InMemoryNskeyKeyRing] that records every namespace it was asked about.
class _CountingRing extends InMemoryNskeyKeyRing {
  final List<String> lookups = [];

  @override
  Future<NskeyAdvertisement?> currentPublic(
      String owner, String namespace) async {
    lookups.add(namespace);
    return super.currentPublic(owner, namespace);
  }
}

/// A ring serving one advertisement that carries more than one key, which
/// [InMemoryNskeyKeyRing]'s single-key seeding cannot express.
class _WidenedRing extends InMemoryNskeyKeyRing {
  _WidenedRing(this._advertised);

  final NskeyAdvertisement _advertised;

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      namespace == 'todos' ? _advertised : null;
}
