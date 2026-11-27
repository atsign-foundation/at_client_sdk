import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Catalogue: features/at_client/collection_delete_by_id.feature
void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const parentNs = 'posts.blog.app';

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;

  /// The keystore: each key's `AtKey.toString()` form to the value stored
  /// under it.
  late Map<String, String> store;

  setUp(() {
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    store = <String, String>{};
    when(() => atClient.atSign).thenReturn(selfAtSign);
    when(() => atClient.put(any(), any())).thenAnswer((inv) async {
      store['${inv.positionalArguments[0]}'] =
          inv.positionalArguments[1] as String;
      return true;
    });
    when(() => atClient.delete(any())).thenAnswer((inv) async {
      store.remove('${inv.positionalArguments[0]}');
      return true;
    });
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = store['$key'];
      if (value == null) throw KeyNotFoundException('no key $key');
      return AtValue()
        ..value = value
        ..metadata = (Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1)));
    });
    when(() => atClient.getAtKeys(regex: any(named: 'regex'))).thenAnswer(
      (inv) async {
        final pattern = RegExp(inv.namedArguments[#regex] as String);
        return <AtKey>[
          for (final key in store.keys)
            if (pattern.hasMatch(key)) AtKey.fromString(key),
        ];
      },
    );
  });

  tearDown(() => notifStream.close());

  AtCollection<String> buildParent() => collectionWithInjectedNotifications(
        atClient,
        parentNs,
        const Duration(days: 7),
        notifications: notifStream.stream,
      );

  test('deleting an own item by id keeps the delete bookkeeping', () async {
    final posts = buildParent();
    await posts.create(obj: 'post', id: 'p1');
    final post = await posts.get('p1', selfAtSign);
    final notes = subCollectionWithInjectedNotifications<String, String>(
      posts,
      parentItem: post,
      subName: 'notes',
      defaultExpiration: const Duration(days: 30),
      notifications: notifStream.stream,
    );
    await notes.create(obj: 'note', id: 'c1');
    const subKey = 'c1.notes.p1.$parentNs$selfAtSignStr';
    expect(store.keys, contains(subKey));
    expect(await notes.exists('c1', selfAtSign), isTrue,
        reason: 'create cached the id, so exists consults the cache');

    final deleted = <CItemDeleted>[];
    final subDeleted = <CSubItemDeleted>[];
    final onDeleted = notes.deletes.listen(deleted.add);
    final onSubDeleted = posts.subDeletes.listen(subDeleted.add);

    await notes.deleteById('c1');
    await Future<void>.delayed(Duration.zero);

    expect(store.keys, isNot(contains(subKey)));
    expect(await notes.exists('c1', selfAtSign), isFalse,
        reason: 'deleteById evicted the cached id and the store holds no key');
    expect(deleted, hasLength(1));
    expect(deleted.single.id, 'c1');
    expect(deleted.single.owner, selfAtSign);
    expect(subDeleted, hasLength(1));
    expect(subDeleted.single.id, 'c1');
    expect(subDeleted.single.owner, selfAtSign);
    expect(subDeleted.single.ancestry, [
      CAncestor(id: 'p1', subName: 'notes', owner: selfAtSign),
    ]);
    await onDeleted.cancel();
    await onSubDeleted.cancel();
  });
}
