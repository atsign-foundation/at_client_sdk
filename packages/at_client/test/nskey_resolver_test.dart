import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

/// Which level of a nested namespace holds the nskey a sender seals to.
///
/// A namespace nests, and AtCollection composes sub-collection namespaces with a
/// per-**item** id — so requiring an exact-match key would mean a keypair per
/// item. Resolution walks up instead, most-specific-first, which is safe because
/// it goes the same direction as the atServer's suffix authorisation: an
/// enrollment approved for `a` may already access `d.c.b.a`.
void main() {
  const alice = '@alice';

  late XWingKeyPair todosKey;
  late XWingKeyPair deepKey;

  setUpAll(() async {
    todosKey = await XWingKeyPair.generate();
    deepKey = await XWingKeyPair.generate();
  });

  /// A ring that counts lookups, so the memo can be measured rather than
  /// assumed.
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

      // A second write to the SAME item: every level is either a remembered
      // miss or a hit the ring itself caches.
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
      // The correctness property that rules out remembering *hits*: warming a
      // broader level must not make a deeper key invisible.
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

/// An [InMemoryNskeyKeyRing] that records every namespace it was asked about,
/// and can be made to forget one.
class _CountingRing extends InMemoryNskeyKeyRing {
  final List<String> lookups = [];

  @override
  Future<NskeyAdvertisement?> currentPublic(
      String owner, String namespace) async {
    lookups.add(namespace);
    return super.currentPublic(owner, namespace);
  }
}
