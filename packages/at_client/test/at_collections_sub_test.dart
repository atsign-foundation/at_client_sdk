// Sub-collection tests. The core AtCollection<T> baseline lives in
// at_collections_test.dart; this file exercises only sub-collection-specific
// behaviour: namespace composition, key-length guard, the CSubItem* event
// pipeline, parent-delete cascade, and cleanupOrphans.

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class FakeAtKey extends Fake implements AtKey {}

class _Collections {
  final AtCollection parent;
  final MockAtClient atClient;
  final StreamController<AtNotification> notifStream;
  _Collections(this.parent, this.atClient, this.notifStream);
}

void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const bobStr = '@bob';
  const parentNs = 'posts.blog.app';

  _Collections buildParent() {
    final atClient = MockAtClient();
    final notifStream = StreamController<AtNotification>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
    final parent = AtCollection<String>.withInjectedNotifications(
      atClient,
      parentNs,
      const Duration(days: 7),
      notifications: notifStream.stream,
    );
    return _Collections(parent, atClient, notifStream);
  }

  /// Helper for building sub-collections in tests — forwards the parent's
  /// injected notification stream to the child so the test harness drives
  /// everything from one place.
  AtCollection<U> subOn<U>(
    _Collections c,
    CItem<dynamic> parent,
    String subName, {
    U Function(Map<String, dynamic>)? fromJson,
  }) {
    return c.parent.subCollection<U>(
      parent: parent,
      subName: subName,
      defaultExpiration: const Duration(days: 30),
      fromJson: fromJson,
      notifications: c.notifStream.stream,
    );
  }

  // ---------------------------------------------------------------------------
  group('subCollection — namespace composition', () {
    test('composes <subName>.<parent.id>.<namespace>', () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p123') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      expect(comments.namespace, 'comments.p123.$parentNs');
    });

    test('rejects subName with a dot', () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      expect(
        () => c.parent.subCollection<String>(
          parent: post,
          subName: 'comments.v2',
          defaultExpiration: const Duration(days: 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects empty subName', () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      expect(
        () => c.parent.subCollection<String>(
          parent: post,
          subName: '',
          defaultExpiration: const Duration(days: 1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects the reserved subName "__rr"', () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      expect(
        () => c.parent.subCollection<String>(
          parent: post,
          subName: '__rr',
          defaultExpiration: const Duration(days: 1),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('reserved'),
          ),
        ),
      );
    });

    test('rejects a composed namespace that would exceed the key-length max',
        () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final huge = List.filled(200, 'x').join();
      expect(
        () => c.parent.subCollection<String>(
          parent: post,
          subName: huge,
          defaultExpiration: const Duration(days: 1),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('exceeds the max'),
          ),
        ),
      );
    });

    test('nested sub-of-sub composes correctly', () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      final comment = comments.draft(obj: 'great post', id: 'c1');
      final replies = comments.subCollection<String>(
        parent: comment,
        subName: 'replies',
        defaultExpiration: const Duration(days: 1),
        notifications: c.notifStream.stream,
      );
      expect(replies.namespace, 'replies.c1.comments.p1.$parentNs');
    });
  });

  // ---------------------------------------------------------------------------
  group('CSubItem events via handleNotification', () {
    AtNotification subNotif({
      required String key,
      required String from,
      required String to,
      required String operation,
    }) {
      return AtNotification(
        'nid-sub',
        key,
        from,
        to,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: operation,
      );
    }

    test('regexSubObj match emits CSubItemUpdated on parent.subUpdates',
        () async {
      final c = buildParent();
      final received = <CSubItemUpdated>[];
      final sub = c.parent.subUpdates.listen(received.add);

      // A sub-item notification: <subId>.<subName>.<parentId>.<namespace>@<from>
      c.notifStream.add(subNotif(
        key: 'c1.comments.p1.$parentNs$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      // `id` is the sub-item's own id; ancestry.last.id is the direct
      // parent (p1).
      expect(received.single.id, 'c1');
      expect(received.single.ancestry, hasLength(1));
      expect(received.single.ancestry.single.id, 'p1');
      expect(received.single.subName, 'comments');
      expect(received.single.owner, selfAtSign);
      await sub.cancel();
    });

    test('regexSubObj delete emits CSubItemDeleted on parent.subDeletes',
        () async {
      final c = buildParent();
      final received = <CSubItemDeleted>[];
      final sub = c.parent.subDeletes.listen(received.add);

      c.notifStream.add(subNotif(
        key: 'c1.comments.p1.$parentNs$bobStr',
        from: bobStr,
        to: selfAtSignStr,
        operation: 'delete',
      ));
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      expect(received.single.id, 'c1');
      expect(received.single.ancestry.single.id, 'p1');
      expect(received.single.subName, 'comments');
      await sub.cancel();
    });

    test(
        'depth-2 update emits CSubItemUpdated with envelope-derived '
        'ancestor owners', () async {
      final c = buildParent();
      // Stub the dispatcher's envelope fetch. The sub-item's envelope
      // carries `parents` as owners-only; ids are recovered from the key.
      when(() => c.atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'n/a',
          'obj': 'r1 body',
          'parents': [
            {'owner': bobStr},       // root (p1) owner
            {'owner': selfAtSignStr}, // direct parent (c1) owner
          ],
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final received = <CSubItemUpdated>[];
      final sub = c.parent.subUpdates.listen(received.add);

      // Sub-sub key shape: <subSubId>.<subSubName>.<subId>.<subName>
      //   .<parentId>.<namespace>@<owner>
      c.notifStream.add(subNotif(
        key: 'r1.replies.c1.comments.p1.$parentNs$bobStr',
        from: bobStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      expect(received.single.id, 'r1');
      expect(received.single.ancestry, hasLength(2));
      // root → direct parent, ids from key, owners from envelope
      expect(received.single.ancestry[0].id, 'p1');
      expect(received.single.ancestry[0].subName, 'comments');
      expect(received.single.ancestry[0].owner, bobStr.toAtsign());
      expect(received.single.ancestry[1].id, 'c1');
      expect(received.single.ancestry[1].subName, 'replies');
      expect(received.single.ancestry[1].owner, selfAtSign);
      expect(received.single.subName, 'replies');
      await sub.cancel();
    });

    test(
        'depth-2 update with no `parents` field in envelope falls back '
        'to null ancestor owners (legacy tolerance)', () async {
      final c = buildParent();
      when(() => c.atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        // No `parents` key — legacy envelope.
        v.value = jsonEncode({'type': 'n/a', 'obj': 'r1'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final received = <CSubItemUpdated>[];
      final sub = c.parent.subUpdates.listen(received.add);

      c.notifStream.add(subNotif(
        key: 'r1.replies.c1.comments.p1.$parentNs$bobStr',
        from: bobStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      expect(received.single.ancestry, hasLength(2));
      expect(received.single.ancestry[0].owner, isNull);
      expect(received.single.ancestry[1].owner, isNull);
      expect(received.single.ancestry[0].id, 'p1');
      expect(received.single.ancestry[1].id, 'c1');
      await sub.cancel();
    });

    test(
        'depth-2 delete emits CSubItemDeleted with ancestry ids and '
        'null owners (item is gone, no envelope to read)', () async {
      final c = buildParent();
      final received = <CSubItemDeleted>[];
      final sub = c.parent.subDeletes.listen(received.add);

      c.notifStream.add(subNotif(
        key: 'r1.replies.c1.comments.p1.$parentNs$bobStr',
        from: bobStr,
        to: selfAtSignStr,
        operation: 'delete',
      ));
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      expect(received.single.id, 'r1');
      expect(received.single.ancestry.last.id, 'c1');
      expect(received.single.ancestry.last.owner, isNull);
      expect(received.single.ancestry.first.owner, isNull);
      expect(received.single.subName, 'replies');
      await sub.cancel();
    });

    test(
        'direct-item notifications still flow to parent.updates, not subUpdates',
        () async {
      final c = buildParent();
      final directReceived = <CItemUpdated>[];
      final subReceived = <CSubItemUpdated>[];
      final s1 = c.parent.updates.listen(directReceived.add);
      final s2 = c.parent.subUpdates.listen(subReceived.add);

      c.notifStream.add(subNotif(
        key: 'p1.$parentNs$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(directReceived, hasLength(1));
      expect(subReceived, isEmpty);
      await s1.cancel();
      await s2.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  group('parent-delete cascade on the sub-collection', () {
    test(
        'when parent CItemDeleted fires, sub-collection deletes self-owned '
        'keys in that sub-collection', () async {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      final subSelfKey =
          AtKey.fromString('c1.comments.p1.$parentNs$selfAtSignStr');
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((invocation) async {
        final regex =
            invocation.namedArguments[const Symbol('regex')] as String;
        if (regex.contains('comments.p1.$parentNs')) {
          return [subSelfKey];
        }
        return <AtKey>[];
      });
      // Ancestry filter in _cascadeFromParentDelete fetches each
      // candidate's envelope; stub the get. Legacy (no parents)
      // passes the lenient filter.
      when(() => c.atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);

      // Fire the parent delete notification.
      c.notifStream.add(AtNotification(
        'nid-del',
        'p1.$parentNs$selfAtSignStr',
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'delete',
      ));
      // Wait for the handler + cascade async chain.
      for (int i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Sanity: sub-collection was constructed.
      expect(comments.namespace, 'comments.p1.$parentNs');
      // Deletes were issued against the sub-collection's self-owned key.
      final deleted = verify(
        () => c.atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, contains('c1.comments.p1.$parentNs$selfAtSignStr'));
    });

    test(
        'parent-delete cascade deep-scans nested descendants '
        '(sub-sub items)', () async {
      // Regression: before the deep-scan fix, `_cascadeFromParentDelete`
      // only picked up direct sub-items (`<id>.<composedNs>@self`).
      // Nested sub-sub items matching the composed sub-collection's
      // namespace at depth 2+ were left behind.
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      final commentSelfKey =
          AtKey.fromString('c1.comments.p1.$parentNs$selfAtSignStr');
      final replySelfKey =
          AtKey.fromString('r1.replies.c1.comments.p1.$parentNs$selfAtSignStr');
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((invocation) async {
        final regex =
            invocation.namedArguments[const Symbol('regex')] as String;
        // Deep regex `(^|:).+\\.comments.p1.posts.blog.app@alice`
        // matches both the direct comment AND the nested reply.
        if (regex.contains('comments.p1.$parentNs')) {
          return [commentSelfKey, replySelfKey];
        }
        return <AtKey>[];
      });
      when(() => c.atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);

      c.notifStream.add(AtNotification(
        'nid-del',
        'p1.$parentNs$selfAtSignStr',
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'delete',
      ));
      for (int i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(comments.namespace, 'comments.p1.$parentNs');
      final deleted = verify(
        () => c.atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(
        deleted,
        containsAll(<String>[
          'c1.comments.p1.$parentNs$selfAtSignStr',
          'r1.replies.c1.comments.p1.$parentNs$selfAtSignStr',
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('cleanupOrphans — on a sub-collection', () {
    test('returns empty when the parent still exists', () async {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      // Parent lookup returns one key: parent exists.
      final parentKey = AtKey.fromString('p1.$parentNs$selfAtSignStr');
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [parentKey]);
      when(() => c.atClient.get(parentKey)).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'n/a',
          'readBy': <String>[],
          'obj': 'hello',
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final results = await comments.cleanupOrphans();
      expect(results, isEmpty);
    });

    test(
        'root-collection cleanupOrphans deletes descendants whose root '
        'ancestor is missing, keeps descendants of alive roots', () async {
      final c = buildParent();
      // Alive direct items: p1 only. p2 has been deleted while we were
      // offline; its descendants should be scrubbed.
      final p1 = AtKey.fromString('p1.$parentNs$selfAtSignStr');
      final c1OnP1 = AtKey.fromString(
        'c1.comments.p1.$parentNs$selfAtSignStr',
      );
      final c2OnP2 = AtKey.fromString(
        'c2.comments.p2.$parentNs$selfAtSignStr',
      );
      final r1OnC2OnP2 = AtKey.fromString(
        'r1.replies.c2.comments.p2.$parentNs$selfAtSignStr',
      );
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((invocation) async {
        final regex =
            invocation.namedArguments[const Symbol('regex')] as String;
        // Direct-item scan (getKeys) — returns only p1 (alive roots).
        if (regex.startsWith(r'(^|:)[^.]+\.')) return [p1];
        // Descendant scan — returns every descendant key in the subtree.
        return [c1OnP1, c2OnP2, r1OnC2OnP2];
      });
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);

      final results = await c.parent.cleanupOrphans();
      final deleted = verify(
        () => c.atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      // c2 on p2 and its reply: orphans (root p2 is gone).
      expect(deleted, contains(c2OnP2.toString()));
      expect(deleted, contains(r1OnC2OnP2.toString()));
      // c1 on p1: kept (root p1 is alive).
      expect(deleted, isNot(contains(c1OnP1.toString())));
      expect(results.whereType<OpSuccess>().length, 2);
    });

    test(
        'ancestry filter: sub-collection cleanup preserves self-owned '
        'items in a DIFFERENT-owner chain with a colliding parent id',
        () async {
      // Setup: self and bob each have a post with the same id (`p1`).
      // Self has a comment on self's p1 AND a comment on bob's p1,
      // both persisted with the same key shape (id collision on the
      // wire). When self's sub-collection-for-self's-p1 runs
      // cleanupOrphans after self's p1 is gone, ONLY self's comment on
      // self's p1 should be deleted. The comment on bob's p1
      // (envelope parents: [bob]) must be preserved.
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');

      final myCommentOnMyP1 =
          AtKey.fromString('c1.comments.p1.$parentNs$selfAtSignStr');
      final myCommentOnBobsP1 =
          AtKey.fromString('c2.comments.p1.$parentNs$selfAtSignStr');
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((invocation) async {
        final regex =
            invocation.namedArguments[const Symbol('regex')] as String;
        if (regex.contains('comments.p1.$parentNs')) {
          return [myCommentOnMyP1, myCommentOnBobsP1];
        }
        return <AtKey>[];
      });
      when(() => c.atClient.get(myCommentOnMyP1)).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'n/a',
          'obj': 'on my own p1',
          'parents': [
            {'owner': selfAtSignStr},
          ],
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => c.atClient.get(myCommentOnBobsP1)).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'n/a',
          'obj': 'on bob\'s p1',
          'parents': [
            {'owner': bobStr},
          ],
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);

      await comments.cleanupOrphans();
      final deleted = verify(
        () => c.atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, contains(myCommentOnMyP1.toString()));
      expect(deleted, isNot(contains(myCommentOnBobsP1.toString())));
    });

    test('deletes self-owned sub-items when the parent is gone', () async {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');

      // Parent lookup returns []; sub-collection self-owned scan returns
      // one comment; descendants scan on that comment returns [] (no
      // replies or deeper nesting).
      final commentKey =
          AtKey.fromString('c1.comments.p1.$parentNs$selfAtSignStr');
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((invocation) async {
        final regex =
            invocation.namedArguments[const Symbol('regex')] as String;
        // Both the sub-collection's deep-scan and its narrow scans
        // should find the stale comment.
        if (regex.contains('comments.p1.$parentNs')) return [commentKey];
        // Parent lookup in the parent collection.
        return <AtKey>[];
      });
      when(() => c.atClient.get(commentKey)).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'n/a',
          'obj': 'a stale comment',
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);

      final results = await comments.cleanupOrphans();
      expect(results, isNotEmpty);
      final deleted = verify(
        () => c.atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, contains(commentKey.toString()));
    });
  });
}
