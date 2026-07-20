// Regression tests for #2032 and the sibling AtCollection defects surfaced
// by the adversarial review alongside it:
//   #2032 — Query.watch()/getOrNull never resolve a received (shared-in)
//           item (id-scoped scan regex missed the two-wrapper cached: key).
//   #0    — owner suffix not end-anchored (@bob matched @bobby): cross-owner
//           reads and same-id delete data-loss.
//   #1    — exists() routed received items to a remote lookup.
//   #3    — a top-level id containing '.' read back truncated.
//   #5    — availableAt scheduler dropped not-yet-available items.
//   #6    — a key expiring mid-read duplicated the preceding item.
// (#2 lives in at_collections_sub_test.dart; #4 in the data-events file.)
//
// The harness here differs from the other collection test files in one
// deliberate way: `getAtKeys(regex:)` is stubbed to ACTUALLY APPLY the
// captured regex to a curated key universe, exactly as a real atServer
// scan does. The `seed()` helper elsewhere returns every key regardless
// of the regex, which masks this bug (the wrong regex would still "find"
// the key). A faithful reproduction has to let the regex filter.

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

class FakeAtKey extends Fake implements AtKey {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
  });

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;

  const selfStr = '@alice';
  final selfAtSign = selfStr.toAtsign();
  const bobStr = '@bob';
  final bob = bobStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
  });

  tearDown(() async {
    await notifStream.close();
  });

  AtCollection<String> buildCollection() =>
      collectionWithInjectedNotifications<String>(
        atClient,
        namespace,
        const Duration(days: 7),
        notifications: notifStream.stream,
      );

  // A record in the fake local keystore: the on-disk key string and the
  // item's `obj` payload.
  final universe = <String, String>{}; // keyString -> obj

  /// Installs [universe] as the mock keystore. `getAtKeys(regex:)` returns
  /// only the keys whose string matches the passed regex — the same
  /// filtering a real server-side scan performs — and `get(atKey)` returns
  /// each key's encoded String-collection value. The map is mutable, so a
  /// test can add a record between a watch prime and a later event.
  void installKeystore() {
    when(() => atClient.getAtKeys(regex: any(named: 'regex')))
        .thenAnswer((inv) async {
      final re = RegExp(inv.namedArguments[#regex] as String);
      return universe.keys.where(re.hasMatch).map(AtKey.fromString).toList();
    });
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final k = inv.positionalArguments.first as AtKey;
      final ks = k.toString();
      final matches = universe.entries
          .where((e) => AtKey.fromString(e.key).toString() == ks);
      if (matches.isEmpty) {
        // A real local llookup throws when the key isn't in the local
        // store. Modelling an offline / local-only keystore this way is
        // what makes the "routed to a remote lookup" bugs observable: the
        // buggy non-cached key shape simply isn't present locally.
        throw KeyNotFoundException('no local value for $ks');
      }
      return AtValue()
        ..value = jsonEncode({
          'type': 'n/a',
          'readBy': <String>[],
          'obj': matches.first.value,
        })
        ..metadata = (Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 7)));
    });
  }

  // Local key shapes for a collection item at this namespace:
  String selfKey(String id) => '$id.$namespace$selfStr';
  String sharedByMeKey(String id, String to) => '$to:$id.$namespace$selfStr';
  String receivedKey(String id, String owner) =>
      'cached:$selfStr:$id.$namespace$owner';

  AtNotification objNotif({
    required String key,
    required String from,
    required String to,
    required String operation,
  }) =>
      AtNotification(
        'nid',
        key,
        from,
        to,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: operation,
      );

  setUp(() {
    universe.clear();
    installKeystore();
  });

  group('#2032 — received (cached:) items resolve', () {
    test('getOrNull(id, owner) resolves a received item (minimal repro)',
        () async {
      // @bob owns q1 and shared it with @alice; on @alice's device it is
      // stored as `cached:@alice:q1.<ns>@bob`.
      universe[receivedKey('q1', bobStr)] = 'from-bob';
      final c = buildCollection();

      final item = await c.getOrNull('q1', bob);

      expect(item, isNotNull,
          reason: 'received item must be resolvable via the id-scoped read');
      expect(item!.id, 'q1');
      expect(item.owner, bob);
      expect(item.obj, 'from-bob');
    });

    test(
        'getItems() (wildcard path) already returns the received item '
        '— documents the asymmetry that masks the bug', () async {
      universe[receivedKey('q1', bobStr)] = 'from-bob';
      final c = buildCollection();

      final items = await c.getItems();

      // The unfiltered scan uses the `[^.]+` id wildcard, which absorbs the
      // `@self:` segment, so this path works even pre-fix. That is exactly
      // why the bug hid: getItems()/refresh() see the item, getOrNull()
      // does not.
      expect(items.map((i) => i.id), contains('q1'));
    });

    test('the id-scoped scan regex matches self and shared-by-me shapes',
        () async {
      final re = await _capturedScanRegex(
          atClient, buildCollection(), 'q1', selfAtSign);
      expect(re.hasMatch(selfKey('q1')), isTrue, reason: 'self-owned');
      expect(re.hasMatch(sharedByMeKey('q1', bobStr)), isTrue,
          reason: 'shared by me to @bob');
    });

    test('the id-scoped scan regex matches the received cached: shape',
        () async {
      // owner=@bob → regex is anchored on `@bob`; it must still match the
      // two-wrapper `cached:@alice:q1.<ns>@bob` local key.
      final re =
          await _capturedScanRegex(atClient, buildCollection(), 'q1', bob);
      expect(re.hasMatch(receivedKey('q1', bobStr)), isTrue,
          reason: 'cached:@self:<id>.<ns>@owner must be scannable');
    });

    test('watch() re-emits with a received item that arrives after priming',
        () async {
      // Prime with one self-owned item so the initial snapshot is non-empty
      // and the watch cache is primed (delta path active thereafter).
      universe[selfKey('q0')] = 'mine';
      final c = buildCollection();
      final q = c.query();
      final snapshots = <List<CItem<String>>>[];
      final sub = q.watch().listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.last.map((i) => i.id), ['q0']);

      // @bob now shares q1 with @alice. The received copy lands locally,
      // and the shared-key notification arrives.
      universe[receivedKey('q1', bobStr)] = 'from-bob';
      notifStream.add(objNotif(
        key: '$selfStr:q1.$namespace$bobStr', // notification key (pre-cache)
        from: bobStr,
        to: selfStr,
        operation: 'update',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final latest = snapshots.last.map((i) => '${i.owner}/${i.id}').toSet();
      expect(latest, contains('$bobStr/q1'),
          reason: 'the received item must appear in the watch snapshot');
      await sub.cancel();
    });
  });

  group('#0 — owner suffix is end-anchored', () {
    test('getItems(owner:) does not cross-match a prefix-extended atSign',
        () async {
      // self=@alice holds received items from @jo and @john. A scan for
      // owner @jo must not also return @john's items (@jo is a prefix).
      universe[receivedKey('aaa', '@jo')] = 'from-jo';
      universe[receivedKey('bbb', '@john')] = 'from-john';
      final c = buildCollection();

      final items = await c.getItems(owner: '@jo'.toAtsign());

      expect(items.map((i) => '${i.owner}/${i.id}').toSet(), {'@jo/aaa'});
    });

    test(
        'deleting a self item spares a same-id item received from a '
        'prefix-extended atSign', () async {
      // self=@jo; @john (has @jo as a prefix) shared t1 with @jo, and @jo
      // owns its own t1. Deleting @jo's t1 must not touch @john's copy.
      when(() => atClient.atSign).thenReturn('@jo'.toAtsign());
      final deleted = <String>[];
      when(() => atClient.delete(any())).thenAnswer((inv) async {
        deleted.add((inv.positionalArguments.first as AtKey).toString());
        return true;
      });
      universe['t1.$namespace@jo'] = 'mine';
      universe[receivedKey('t1', '@john')] = 'from-john';
      final c = buildCollection(); // self=@jo

      final mine = await c.getOrNull('t1', '@jo'.toAtsign());
      expect(mine, isNotNull);
      await c.delete(mine!);

      final johnKey = AtKey.fromString(receivedKey('t1', '@john')).toString();
      final selfKeyStr = AtKey.fromString('t1.$namespace@jo').toString();
      expect(deleted, contains(selfKeyStr), reason: 'own copy deleted');
      expect(deleted, isNot(contains(johnKey)),
          reason: "@john's received copy must survive");
    });
  });

  group('#1 — exists() reads the local received copy', () {
    test('exists(id, owner) resolves a received item from the local store',
        () async {
      universe[receivedKey('t1', bobStr)] = 'from-bob';
      final c = buildCollection();

      // The keystore mock throws for a non-local key shape, so a remote
      // route would surface as false. Post-fix exists probes the local
      // cached: copy.
      expect(await c.exists('t1', bob), isTrue);
    });

    test('exists agrees with getOrNull != null for a received item', () async {
      universe[receivedKey('t1', bobStr)] = 'from-bob';
      final c = buildCollection();

      expect(await c.exists('t1', bob), (await c.getOrNull('t1', bob)) != null);
    });
  });

  group('#3 — dotted top-level ids are rejected', () {
    test('draft rejects an id containing a dot', () {
      final c = buildCollection();
      expect(() => c.draft(obj: 'x', id: 'a.b'), throwsArgumentError);
    });

    test('create rejects an id containing a dot', () {
      final c = buildCollection();
      expect(c.create(obj: 'x', id: 'a.b'), throwsArgumentError);
    });
  });

  group('#5 — availableAt scheduler registers not-yet-available items', () {
    test(
        'a future-dated item arriving via an update event still fires '
        'CItemAvailable', () async {
      final c = buildCollection();
      final available = <CItemAvailable>[];
      final sub = c.availableEvents.listen(available.add);
      // Let the (empty) initial populate settle so this exercises the
      // update path, not startup.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // A self item whose value is not yet visible (availableAt ~120ms out).
      final availableAt = DateTime.now().add(const Duration(milliseconds: 120));
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [AtKey.fromString('t1.$namespace$selfStr')]);
      when(() => atClient.get(any())).thenAnswer((_) async => AtValue()
        ..value = null // not-yet-available: keystore withholds the value
        ..metadata = (Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..availableAt = availableAt
          ..expiresAt = DateTime.now().add(const Duration(days: 1))));

      notifStream.add(objNotif(
        key: 't1.$namespace$selfStr',
        from: selfStr,
        to: selfStr,
        operation: 'update',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(available.map((e) => e.id), contains('t1'),
          reason: 'CItemAvailable must fire for a future-dated item');
      await sub.cancel();
    });
  });

  group('#6 — no duplicate yield when a key vanishes mid-stream', () {
    test(
        'an expiry/delete race on a middle key does not re-yield its '
        'predecessor', () async {
      // Three self items sort aaa < bbb < ccc. bbb expires between the scan
      // and its per-key read (KeyNotFoundException); aaa must not be yielded
      // twice.
      final keys = ['aaa', 'bbb', 'ccc']
          .map((id) => AtKey.fromString('$id.$namespace$selfStr'))
          .toList();
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => keys);
      when(() => atClient.get(any())).thenAnswer((inv) async {
        final id =
            (inv.positionalArguments.first as AtKey).key.split('.').first;
        if (id == 'bbb') {
          throw KeyNotFoundException('bbb expired mid-stream');
        }
        return AtValue()
          ..value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': id})
          ..metadata = (Metadata()
            ..createdAt = DateTime.now().toUtc()
            ..expiresAt = DateTime.now().add(const Duration(days: 1)));
      });
      final c = buildCollection();

      final ids = (await c.getItems()).map((i) => i.id).toList();

      expect(ids, ['aaa', 'ccc']);
    });
  });
}

/// Captures the regex the id-scoped read path emits for
/// `getOrNull(id, owner)`. Temporarily overrides `getAtKeys` to record the
/// regex and return nothing; restores nothing else (each test re-installs
/// its keystore in setUp).
Future<RegExp> _capturedScanRegex(
  MockAtClient atClient,
  AtCollection<String> c,
  String id,
  Atsign owner,
) async {
  late String captured;
  when(() => atClient.getAtKeys(regex: any(named: 'regex')))
      .thenAnswer((inv) async {
    captured = inv.namedArguments[#regex] as String;
    return <AtKey>[];
  });
  await c.getOrNull(id, owner);
  return RegExp(captured);
}
