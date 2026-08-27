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

  group('what this client is willing to seal to', () {
    test('the default reaches an owner advertising either KEM', () async {
      // The control for the row below: with the full list this same owner
      // resolves, so the refusal there is the narrowing and nothing else.
      final r = resolver();
      r.ring.seedPublicOnly(alice, 'todos', publicKey: todosKey.publicKeyBytes);

      expect((await r.resolver.resolve(alice, 'todos'))?.alg,
          SecretSharingAlgos.xWing);
    });

    test('a narrowed list refuses, and the message names both sides', () async {
      // The refusal a FIPS-only deployment asked for. It must not read as a
      // cold start: the owner published a perfectly good key, and it is this
      // client's own rule that will not use it.
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

    test('it refuses rather than walking up to a broader namespace', () async {
      // Walking on would seal under a DIFFERENT namespace's key — another
      // content-key scope than the caller asked for — arrived at silently
      // because of a rule this client set. The parent key here is one the
      // narrowed client would happily use, so only the refusal tells the two
      // designs apart.
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

    test('a key published after a miss is found on the very next resolve',
        () async {
      // The memory may make a resolution CHEAPER; it may never make one WRONG.
      // At the production default this fixture is fifteen minutes from
      // lapsing, so if the remembered miss were allowed to decide the outcome
      // this would answer null.
      //
      // Measured live before the second walk existed: a client that had tried
      // to write to a recipient went on refusing for the rest of the window
      // after that recipient published, and the readiness query and the
      // exception text were wrong with it. Nothing in the write path asks a
      // pre-flight question, so there was no caller placed to notice.
      final c = resolver(); // production default missMemory
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
      // The second walk must not double the cost of an ordinary cold write.
      // It runs only when the memory actually suppressed something, and on a
      // first resolve it has suppressed nothing.
      final c = resolver();

      expect(await c.resolver.resolve(alice, 'x.todos'), isNull);

      expect(c.lookups, ['x.todos', 'todos'],
          reason: 'each level asked once and no more: nothing was skipped, so '
              'the answer was already trustworthy and there is nothing to '
              're-ask');
    });

    test('a repeated cold resolve pays the walk again, deliberately', () async {
      // The cost of never answering from memory, stated rather than hidden.
      // It falls only on a resolution that is about to return null — for a
      // write, one about to throw — and never on one that resolves.
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
