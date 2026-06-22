// Sub-collection tests. The core AtCollection<T> baseline lives in
// at_collections_test.dart; this file exercises only sub-collection-specific
// behaviour: namespace composition, key-length guard, the CSubItem* event
// pipeline, parent-delete cascade, and cleanupOrphans.
//
// Event-source coverage: exercises the [EventSource.notifs] path. The
// data-events path equivalent is `at_collections_data_events_test.dart`;
// dual-emission semantics under [EventSource.both] are covered by
// `at_collections_events_both_test.dart`.

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';

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
    final parent = collectionWithInjectedNotifications<String>(
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
    String? typeTag,
  }) {
    return subCollectionWithInjectedNotifications<dynamic, U>(
      c.parent,
      parentItem: parent,
      subName: subName,
      defaultExpiration: const Duration(days: 30),
      fromJson: fromJson,
      typeTag: typeTag,
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
            contains('exceeds the absolute-worst-case max'),
          ),
        ),
      );
    });

    test(
        'composed namespace just under the 128-char budget succeeds; '
        'just over throws', () {
      // Compute lengths so the composed namespace `<sub>.<parent.id>.<ns>`
      // lands at exactly 128 chars (just-under) and 129 (just-over).
      // ns prefix overhead per level: '.' + parent.id (here 'p1' = 2 chars)
      // + '.' + parentNs (here 'posts.blog.app' = 14 chars) = 18 chars.
      // So sub-name length needed for composedNs == 128 is 128 - 18 = 110.
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final justRight = 'a' * 110; // composedNs total = 128 chars
      final tooBig = 'a' * 111; // composedNs total = 129 chars

      // Sanity-check the arithmetic.
      expect('$justRight.p1.$parentNs'.length, 128);
      expect('$tooBig.p1.$parentNs'.length, 129);

      // 128 chars: succeeds. Use `subOn` (the test helper) so the
      // sub-collection's notification subscription gets a stream.
      expect(
        () => subOn<String>(c, post, justRight),
        returnsNormally,
      );
      // 129 chars: throws — the budget check fires before any
      // notification setup, so this works on the public surface
      // too.
      expect(
        () => c.parent.subCollection<String>(
          parent: post,
          subName: tooBig,
          defaultExpiration: const Duration(days: 1),
        ),
        throwsArgumentError,
      );
    });

    test('nested sub-of-sub composes correctly', () {
      final c = buildParent();
      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      final comment = comments.draft(obj: 'great post', id: 'c1');
      final replies = subCollectionWithInjectedNotifications<String, String>(
        comments,
        parentItem: comment,
        subName: 'replies',
        defaultExpiration: const Duration(days: 1),
        notifications: c.notifStream.stream,
      );
      expect(replies.namespace, 'replies.c1.comments.p1.$parentNs');
    });
  });

  // ---------------------------------------------------------------------------
  group('CSubItem events via handleNotification', () {
    // Helper builds notifications with the `<to>:<bareKey>@<from>`
    // envelope shape that AtServer actually emits — production
    // notifications always carry the recipient atSign as the
    // `<to>:` prefix on the key. Tests previously omitted that
    // prefix, which left `_handleSubObjNotificationImpl`'s cached-
    // form construction unable to round-trip the storage key.
    AtNotification subNotif({
      required String key,
      required String from,
      required String to,
      required String operation,
    }) {
      return AtNotification(
        'nid-sub',
        '$to:$key',
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
            {'owner': bobStr}, // root (p1) owner
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
        'depth-2 update with `parents` in n.value recovers ancestor owners '
        'from the payload directly (no keystore round-trip)', () async {
      final c = buildParent();
      // Fail loudly if the dispatcher tries to fetch the envelope —
      // the notification payload already carries `parents`, so the
      // keystore round-trip should be skipped entirely.
      when(() => c.atClient.get(any())).thenAnswer(
        (_) async => throw StateError(
          'atClient.get must not be called when n.value carries parents',
        ),
      );

      final received = <CSubItemUpdated>[];
      final sub = c.parent.subUpdates.listen(received.add);

      c.notifStream.add(AtNotification(
        'nid-sub-payload',
        'r1.replies.c1.comments.p1.$parentNs$bobStr',
        bobStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'update',
        value: jsonEncode({
          'type': 'n/a',
          'obj': 'r1 body',
          'parents': [
            {'owner': bobStr},
            {'owner': selfAtSignStr},
          ],
        }),
      ));
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      expect(received.single.id, 'r1');
      expect(received.single.ancestry, hasLength(2));
      expect(received.single.ancestry[0].owner, bobStr.toAtsign());
      expect(received.single.ancestry[1].owner, selfAtSign);
      verifyNever(() => c.atClient.get(any()));
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
        if (regex
            .contains('comments\\.p1\\.${parentNs.replaceAll('.', '\\.')}')) {
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
        if (regex
            .contains('comments\\.p1\\.${parentNs.replaceAll('.', '\\.')}')) {
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
        // Direct-item scan uses `[^.]+\.<ns>@` (single non-dot id);
        // descendant scan uses `.+\.<parentId>\.<ns>@`. Branch on
        // whichever substring is present — both are stable across
        // the #1942 regex tightening.
        if (regex.contains(r'[^.]+\.')) return [p1];
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
        if (regex
            .contains('comments\\.p1\\.${parentNs.replaceAll('.', '\\.')}')) {
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
        if (regex
            .contains('comments\\.p1\\.${parentNs.replaceAll('.', '\\.')}')) {
          return [commentKey];
        }
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

    test('legacy depth-2 descendant whose middleman is gone is swept',
        () async {
      // Setup: a depth-2 reply r1 under comment c1 under post p1.
      // The reply is a legacy item (no `parents` envelope field).
      // Root post p1 still exists locally; mid comment c1 is gone;
      // reply r1 still on disk. The chain-walker detects c1's
      // absence and sweeps r1 even though the root is alive.
      final c = buildParent();
      final replyKey = AtKey.fromString(
        'r1.replies.c1.comments.p1.$parentNs$selfAtSignStr',
      );
      final postKey = AtKey.fromString('p1.$parentNs$selfAtSignStr');
      // getKeys() (root-level scan) returns the root post.
      // descendant scan returns the orphaned reply.
      // alive-at-mid-namespace scan returns no comments.
      // After the #1942 regex tightening, namespace dots are escaped
      // and every scan is prefixed with `^(?!local:)(?:[^:]*:)?`.
      final escapedParentNs = parentNs.replaceAll('.', '\\.');
      final directRegex = '^(?!local:)(?:[^:]*:)?[^.]+\\.$escapedParentNs@';
      final descendantRegex =
          '^(?!local:)(?:[^:]*:)?.+\\.$escapedParentNs$selfAtSignStr';
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((inv) async {
        final regex = inv.namedArguments[#regex] as String;
        if (regex == directRegex) return [postKey];
        if (regex == descendantRegex) return [replyKey];
        // Alive-at mid-namespace `comments.p1.<parentNs>` (any owner):
        if (regex.contains('comments\\.p1\\.posts\\.blog\\.app')) {
          return <AtKey>[]; // c1 is gone — middleman orphan
        }
        return <AtKey>[];
      });
      // Envelope read for the reply: legacy (no `parents`).
      when(() => c.atClient.get(replyKey)).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'orphan reply'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);

      final results = await c.parent.cleanupOrphans();
      expect(results, isNotEmpty);
      final deleted = verify(
        () => c.atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, contains(replyKey.toString()));
    });
  });

  // ---------------------------------------------------------------------------
  // Local CEvent emission for sub-collection writes. The sub-
  // collection's own `updates` / `deletes` streams fire as on a
  // root collection (see at_collections_test.dart). Additionally,
  // each ancestor collection's `subUpdates` / `subDeletes` streams
  // fire with the appropriate ancestry slice — matching the
  // round-trip notification path's shape but synchronously, so UIs
  // don't wait ~50-200 ms (or ~10-30 ms post-fsync) after a local
  // write.
  group('local CEvent emission on sub-collection writes', () {
    test(
        'depth-1 sub-item create fires CItemUpdated on the sub-collection '
        'AND CSubItemUpdated on the parent with 1-link ancestry', () async {
      final c = buildParent();
      when(() => c.atClient.put(any(), any())).thenAnswer((_) async => true);
      when(() => c.atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => <AtKey>[]);

      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');

      final subUpdated = <CItemUpdated>[];
      final parentSubUpdated = <CSubItemUpdated>[];
      final subSub = comments.updates.listen(subUpdated.add);
      final parentSub = c.parent.subUpdates.listen(parentSubUpdated.add);

      await comments.create(obj: 'first comment', id: 'c1');
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Sub-collection itself sees CItemUpdated for c1.
      expect(subUpdated, hasLength(1));
      expect(subUpdated.single.id, 'c1');
      // Parent sees CSubItemUpdated with ancestry [(p1, comments,
      // owner=selfAtSign)].
      expect(parentSubUpdated, hasLength(1));
      expect(parentSubUpdated.single.id, 'c1');
      expect(parentSubUpdated.single.ancestry, hasLength(1));
      expect(parentSubUpdated.single.ancestry[0].id, 'p1');
      expect(parentSubUpdated.single.ancestry[0].subName, 'comments');
      expect(parentSubUpdated.single.ancestry[0].owner, selfAtSign);

      await subSub.cancel();
      await parentSub.cancel();
    });

    test(
        'depth-2 sub-sub-item create fires CSubItemUpdated on BOTH the '
        'depth-1 ancestor (1-link) AND the depth-0 root (2-link)', () async {
      final c = buildParent();
      when(() => c.atClient.put(any(), any())).thenAnswer((_) async => true);
      when(() => c.atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => <AtKey>[]);

      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      final comment = comments.draft(obj: 'great post', id: 'c1');
      // subOn always chains off c.parent; for depth-2 we need to
      // chain off comments directly so the replies sub-collection's
      // _parentCollection is comments (not c.parent).
      final replies = subCollectionWithInjectedNotifications<String, String>(
        comments,
        parentItem: comment,
        subName: 'replies',
        defaultExpiration: const Duration(days: 30),
        notifications: c.notifStream.stream,
      );

      final commentsSubUpdated = <CSubItemUpdated>[];
      final rootSubUpdated = <CSubItemUpdated>[];
      final commentsSub = comments.subUpdates.listen(commentsSubUpdated.add);
      final rootSub = c.parent.subUpdates.listen(rootSubUpdated.add);

      await replies.create(obj: 'thanks', id: 'r1');
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Comments collection (depth-1) sees ancestry [(c1, replies,
      // owner=selfAtSign)] — leaf is depth-1 from comments'
      // perspective.
      expect(commentsSubUpdated, hasLength(1));
      expect(commentsSubUpdated.single.id, 'r1');
      expect(commentsSubUpdated.single.ancestry, hasLength(1));
      expect(commentsSubUpdated.single.ancestry[0].id, 'c1');
      expect(commentsSubUpdated.single.ancestry[0].subName, 'replies');

      // Root collection (depth-0) sees ancestry
      // [(p1, comments, ...), (c1, replies, ...)] — leaf is
      // depth-2 from root's perspective.
      expect(rootSubUpdated, hasLength(1));
      expect(rootSubUpdated.single.id, 'r1');
      expect(rootSubUpdated.single.ancestry, hasLength(2));
      expect(rootSubUpdated.single.ancestry[0].id, 'p1');
      expect(rootSubUpdated.single.ancestry[0].subName, 'comments');
      expect(rootSubUpdated.single.ancestry[1].id, 'c1');
      expect(rootSubUpdated.single.ancestry[1].subName, 'replies');

      await commentsSub.cancel();
      await rootSub.cancel();
    });

    test(
        'sub-item delete fires CSubItemDeleted on the parent with '
        'fully-populated owner chain', () async {
      // Locally-emitted CSubItemDeleted populates ancestor owners
      // (we have the in-process item graph). The round-trip path
      // can't — by the time the notification fires, the sub-item's
      // envelope is gone — so this is strictly more information than
      // the notification path provides.
      final c = buildParent();
      when(() => c.atClient.put(any(), any())).thenAnswer((_) async => true);
      when(() => c.atClient.delete(any())).thenAnswer((_) async => true);
      when(() => c.atClient.get(any())).thenThrow(Exception('no such key'));
      // Self-key+recipients scan for c1: returns the self-key.
      // Descendants scan for c1: returns [].
      final c1Key = AtKey.fromString('c1.comments.p1.$parentNs$selfAtSignStr');
      when(() => c.atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((inv) async {
        final regex = inv.namedArguments[#regex] as String;
        if (regex.contains('.+\\.c1\\.')) return <AtKey>[];
        if (regex.contains('c1\\.')) return [c1Key];
        return <AtKey>[];
      });

      final post = c.parent.draft(obj: 'hello', id: 'p1') as CItem<String>;
      final comments = subOn<String>(c, post, 'comments');
      final comment = await comments.create(obj: 'x', id: 'c1');

      final received = <CSubItemDeleted>[];
      final sub = c.parent.subDeletes.listen(received.add);
      await comments.delete(comment);
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(received, hasLength(1));
      expect(received.single.id, 'c1');
      expect(received.single.ancestry, hasLength(1));
      expect(received.single.ancestry[0].id, 'p1');
      expect(received.single.ancestry[0].subName, 'comments');
      // Owner populated locally — better than the round-trip path
      // which always carries null owners on delete events.
      expect(received.single.ancestry[0].owner, selfAtSign);
      await sub.cancel();
    });
  });
}
