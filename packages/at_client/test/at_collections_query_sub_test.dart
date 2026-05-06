// Tests for [Query<T>.watchWithSub<U>] — the live parent+children
// stream terminal. Exercises initial emission, child-arrival,
// parent-removal, and cross-parent independence.
//
// Uses a mocked [AtClient] with an injected notification stream so
// tests drive both parent and child changes without real I/O. The
// helpers here shape a store where each AtKey resolves to a JSON
// envelope we construct from seed data.

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class FakeAtKey extends Fake implements AtKey {}

class Post {
  final String title;
  Post(this.title);
  Map<String, dynamic> toJson() => {'title': title};
  factory Post.fromJson(Map<String, dynamic> j) => Post(j['title'] as String);
}

class Comment {
  final String body;
  Comment(this.body);
  Map<String, dynamic> toJson() => {'body': body};
  factory Comment.fromJson(Map<String, dynamic> j) =>
      Comment(j['body'] as String);
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
    AtCollection.registerFactory<Post>(Post.fromJson);
    AtCollection.registerFactory<Comment>(Comment.fromJson);
  });

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;
  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const namespace = 'posts.app_1.my_apps';

  // Seed: maps from the AtKey's `key` field to its JSON envelope.
  late Map<String, Map<String, dynamic>> seed;

  setUp(() {
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    seed = {};
    when(() => atClient.atSign).thenReturn(selfAtSign);
    // The seed map is keyed by the AtKey's full form (e.g.
    // 'p1.posts.app_1.my_apps@alice') — [AtKey.fromString] splits the
    // last dotted segment off as `namespace` and trims `key` to the
    // rest, so we can't rely on `k.key` for lookups.
    when(() => atClient.getAtKeys(regex: any(named: 'regex'))).thenAnswer((
      inv,
    ) async {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return seed.keys
          .map(AtKey.fromString)
          .where((k) => regex.hasMatch(k.toString()))
          .toList();
    });
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final k = inv.positionalArguments.first as AtKey;
      final body = seed[k.toString()];
      if (body == null) throw Exception('no such key ${k.toString()}');
      final v = AtValue();
      v.value = jsonEncode(body);
      v.metadata = Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().add(const Duration(days: 7));
      return v;
    });
  });

  tearDown(() async {
    await notifStream.close();
  });

  AtCollection<Post> buildPosts() {
    return AtCollection<Post>.withInjectedNotifications(
      atClient,
      namespace,
      const Duration(days: 7),
      notifications: notifStream.stream,
      fromJson: Post.fromJson,
    );
  }

  void seedPost(String id, String title) {
    seed['$id.$namespace$selfAtSignStr'] = {
      'type': 'Post',
      'obj': {'title': title},
    };
  }

  void seedComment(String postId, String id, String body) {
    seed['$id.comments.$postId.$namespace$selfAtSignStr'] = {
      'type': 'Comment',
      'obj': {'body': body},
      // parent-chain envelope so child ancestry-filter passes.
      'parents': [
        {'owner': selfAtSignStr},
      ],
    };
  }

  /// Spin the event loop a few times so onListen + nested async
  /// subscribes have settled. Most tests need ~3 iterations.
  Future<void> pump({int n = 5}) async {
    for (int i = 0; i < n; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  // ---------------------------------------------------------------------------
  group('watchWithSub', () {
    test('initial snapshot lists parents with their current children',
        () async {
      final posts = buildPosts();
      seedPost('p1', 'first');
      seedPost('p2', 'second');
      seedComment('p1', 'c1', 'hello');
      seedComment('p1', 'c2', 'world');

      final snapshots =
          <List<({CItem<Post> parent, List<CItem<Comment>> children})>>[];
      final sub = posts
          .query()
          .watchWithSub<Comment>(
            subName: 'comments',
            subDefaultExpiration: const Duration(days: 7),
            subFromJson: Comment.fromJson,
          )
          .listen(snapshots.add);
      await pump();
      // Last snapshot contains both posts; p1 has 2 comments, p2 has 0.
      final last = snapshots.last;
      expect(last.map((r) => r.parent.id).toSet(), {'p1', 'p2'});
      final p1Row = last.firstWhere((r) => r.parent.id == 'p1');
      final p2Row = last.firstWhere((r) => r.parent.id == 'p2');
      expect(p1Row.children.map((c) => c.id).toSet(), {'c1', 'c2'});
      expect(p2Row.children, isEmpty);
      await sub.cancel();
    });

    test('child arrival re-emits with the added child', () async {
      final posts = buildPosts();
      seedPost('p1', 'first');
      final snapshots =
          <List<({CItem<Post> parent, List<CItem<Comment>> children})>>[];
      final sub = posts
          .query()
          .watchWithSub<Comment>(
            subName: 'comments',
            subDefaultExpiration: const Duration(days: 7),
            subFromJson: Comment.fromJson,
          )
          .listen(snapshots.add);
      await pump();
      expect(snapshots.last.single.children, isEmpty);

      // A new comment arrives: add to seed and pump a sub-update
      // notification.
      seedComment('p1', 'cnew', 'yo');
      notifStream.add(AtNotification(
        'nid-1',
        '$selfAtSignStr:cnew.comments.p1.$namespace$selfAtSignStr',
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'update',
      ));
      await pump();
      expect(snapshots.last.single.children.map((c) => c.id), contains('cnew'));
      await sub.cancel();
    });

    test('parent removal cancels its child subscription', () async {
      final posts = buildPosts();
      seedPost('p1', 'first');
      seedPost('p2', 'second');
      seedComment('p1', 'c1', 'hello');
      final snapshots =
          <List<({CItem<Post> parent, List<CItem<Comment>> children})>>[];
      final sub = posts
          .query()
          .watchWithSub<Comment>(
            subName: 'comments',
            subDefaultExpiration: const Duration(days: 7),
            subFromJson: Comment.fromJson,
          )
          .listen(snapshots.add);
      await pump();
      expect(snapshots.last.map((r) => r.parent.id).toSet(), {'p1', 'p2'});

      // Delete p1 from the seed and notify.
      seed.remove('p1.$namespace$selfAtSignStr');
      seed.remove('c1.comments.p1.$namespace$selfAtSignStr');
      notifStream.add(AtNotification(
        'nid-2',
        '$selfAtSignStr:p1.$namespace$selfAtSignStr',
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'delete',
      ));
      await pump();
      // Snapshot should no longer include p1.
      expect(snapshots.last.map((r) => r.parent.id), ['p2']);
      await sub.cancel();
    });

    test(
        'independent children — child event on one parent does not affect another',
        () async {
      final posts = buildPosts();
      seedPost('p1', 'first');
      seedPost('p2', 'second');
      seedComment('p1', 'c1', 'hello');
      seedComment('p2', 'c9', 'other');
      final snapshots =
          <List<({CItem<Post> parent, List<CItem<Comment>> children})>>[];
      final sub = posts
          .query()
          .watchWithSub<Comment>(
            subName: 'comments',
            subDefaultExpiration: const Duration(days: 7),
            subFromJson: Comment.fromJson,
          )
          .listen(snapshots.add);
      await pump();
      final before = snapshots.last;
      final p2Before = before
          .firstWhere((r) => r.parent.id == 'p2')
          .children
          .map((c) => c.id)
          .toSet();

      // Add a comment to p1 only.
      seedComment('p1', 'c2', 'world');
      notifStream.add(AtNotification(
        'nid-3',
        '$selfAtSignStr:c2.comments.p1.$namespace$selfAtSignStr',
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'update',
      ));
      await pump();
      final after = snapshots.last;
      final p1After = after
          .firstWhere((r) => r.parent.id == 'p1')
          .children
          .map((c) => c.id)
          .toSet();
      final p2After = after
          .firstWhere((r) => r.parent.id == 'p2')
          .children
          .map((c) => c.id)
          .toSet();
      expect(p1After, {'c1', 'c2'});
      expect(p2After, p2Before);
      await sub.cancel();
    });

    test('cancel tears down all child subscriptions', () async {
      final posts = buildPosts();
      seedPost('p1', 'first');
      seedPost('p2', 'second');
      final snapshots =
          <List<({CItem<Post> parent, List<CItem<Comment>> children})>>[];
      final sub = posts
          .query()
          .watchWithSub<Comment>(
            subName: 'comments',
            subDefaultExpiration: const Duration(days: 7),
            subFromJson: Comment.fromJson,
          )
          .listen(snapshots.add);
      await pump();
      final countAfterInitial = snapshots.length;

      await sub.cancel();

      // After cancel, further notifications must NOT produce snapshots.
      seedComment('p1', 'cnew', 'yo');
      notifStream.add(AtNotification(
        'nid-4',
        '$selfAtSignStr:cnew.comments.p1.$namespace$selfAtSignStr',
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: 'update',
      ));
      await pump();
      expect(snapshots.length, countAfterInitial);
    });
  });
}
