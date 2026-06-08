# How to Reactively Watch a Posts/Comments/Replies Tree

Your data shape is three levels deep:

```
posts  (root)
  └── comments  (sub-collection of a post)
        └── replies  (sub-collection of a comment)
```

Use `watchWithTree` with nested `SubSpec` declarations. This is the correct tool whenever you have three or more levels — `watchWithSub` only handles two levels (parent + one child type).

---

## Step 1: Define Your Domain Types

Each type needs `toJson` / `fromJson` and a string literal `typeTag`. Never derive `typeTag` from `T.toString()` — the Dart compiler renames types in release builds.

```dart
class Post {
  final String title;
  final String body;
  Post(this.title, this.body);

  Map<String, dynamic> toJson() => {'title': title, 'body': body};
  factory Post.fromJson(Map<String, dynamic> j) =>
      Post(j['title'] as String, j['body'] as String);
}

class Comment {
  final String text;
  Comment(this.text);

  Map<String, dynamic> toJson() => {'text': text};
  factory Comment.fromJson(Map<String, dynamic> j) =>
      Comment(j['text'] as String);
}

class Reply {
  final String text;
  Reply(this.text);

  Map<String, dynamic> toJson() => {'text': text};
  factory Reply.fromJson(Map<String, dynamic> j) =>
      Reply(j['text'] as String);
}
```

---

## Step 2: Register Factories at App Startup

Call `registerFactory` once before any `atClient.collection()` call. If you pass `fromJson:` directly to `atClient.collection()`, the factory is registered automatically — but registering explicitly here makes startup order clear and prevents issues with sub-types.

```dart
// Call once at startup, before any atClient.collection() call
AtCollection.registerFactory<Post>(Post.fromJson, typeTag: 'Post');
AtCollection.registerFactory<Comment>(Comment.fromJson, typeTag: 'Comment');
AtCollection.registerFactory<Reply>(Reply.fromJson, typeTag: 'Reply');
```

---

## Step 3: Get the Root Collection

```dart
final posts = await atClient.collection<Post>(
  'posts.my_app',                    // namespace: must contain '.'
  const Duration(days: 30),          // defaultExpiration for posts
  fromJson: Post.fromJson,
  typeTag: 'Post',
  cleanupOrphansOnCreation: true,    // recommended when using sub-collections
);
```

---

## Step 4: Watch the Full Tree with `watchWithTree`

Declare the shape using `SubSpec<U>` — nest the replies spec inside the comments spec via the `children` field:

```dart
final treeStream = posts.query().watchWithTree([
  SubSpec<Comment>(
    subName: 'comments',
    subDefaultExpiration: const Duration(days: 30),
    subFromJson: Comment.fromJson,
    subTypeTag: 'Comment',
    children: [
      SubSpec<Reply>(
        subName: 'replies',
        subDefaultExpiration: const Duration(days: 30),
        subFromJson: Reply.fromJson,
        subTypeTag: 'Reply',
        // no children — replies are the leaf level
      ),
    ],
  ),
]);
// Returns: Stream<List<TreeNode<Post>>>
```

The stream emits a fresh snapshot whenever any post, any comment on any post, or any reply on any comment changes or is deleted. You do not need to set up separate subscriptions for each level.

---

## Step 5: Consume the Tree

`watchWithTree` returns `Stream<List<TreeNode<Post>>>`. Each `TreeNode<T>` has:

- `node.parent` — the `CItem<T>` for this level
- `node.branches` — a `Map<String, List<TreeNode<dynamic>>>` keyed by `subName`

```dart
treeStream.listen((posts) {
  for (final postNode in posts) {
    final post = postNode.parent;          // CItem<Post>
    print('Post: ${post.obj.title}');

    final commentNodes = postNode.branches['comments'] ?? [];
    for (final commentNode in commentNodes) {
      final comment = commentNode.parent;  // CItem<dynamic> — cast to CItem<Comment>
      final c = comment.obj as Comment;
      print('  Comment: ${c.text}');

      final replyNodes = commentNode.branches['replies'] ?? [];
      for (final replyNode in replyNodes) {
        final reply = replyNode.parent;    // CItem<dynamic> — cast to CItem<Reply>
        final r = reply.obj as Reply;
        print('    Reply: ${r.text}');
      }
    }
  }
});
```

---

## Flutter Integration

Use `StreamBuilder` to wire the tree stream into your widget tree:

```dart
@override
Widget build(BuildContext context) {
  return StreamBuilder<List<TreeNode<Post>>>(
    stream: posts.query().watchWithTree([
      SubSpec<Comment>(
        subName: 'comments',
        subDefaultExpiration: const Duration(days: 30),
        subFromJson: Comment.fromJson,
        subTypeTag: 'Comment',
        children: [
          SubSpec<Reply>(
            subName: 'replies',
            subDefaultExpiration: const Duration(days: 30),
            subFromJson: Reply.fromJson,
            subTypeTag: 'Reply',
          ),
        ],
      ),
    ]),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const CircularProgressIndicator();
      final postNodes = snapshot.data!;
      return ListView.builder(
        itemCount: postNodes.length,
        itemBuilder: (context, i) => PostCard(postNodes[i]),
      );
    },
  );
}
```

If multiple widgets need to listen to the same stream, call `.asBroadcastStream()` on it — `watchWithTree` returns a single-subscription stream by default.

---

## Writing to the Tree

To add items at each level, use `subCollection` to scope a typed collection to the correct parent:

```dart
// Add a comment to a post
final commentsCol = posts.subCollection<Comment>(
  parent: postItem,
  subName: 'comments',
  defaultExpiration: const Duration(days: 30),
  fromJson: Comment.fromJson,
  typeTag: 'Comment',
);
final comment = await commentsCol.create(obj: Comment('Great post!'));

// Add a reply to that comment
final repliesCol = commentsCol.subCollection<Reply>(
  parent: comment,
  subName: 'replies',
  defaultExpiration: const Duration(days: 30),
  fromJson: Reply.fromJson,
  typeTag: 'Reply',
);
await repliesCol.create(obj: Reply('Agreed!'));
```

Both writes will automatically cause the `watchWithTree` stream to re-emit with the updated snapshot.

---

## Deleting Items

Deleting a node that has descendants will throw `StateError` unless you pass `cascade: true`:

```dart
// This throws if the post has comments/replies
await posts.delete(postItem);

// This removes the post and all descendants first
await posts.delete(postItem, cascade: true);
```

---

## Key Rules Summary

| Rule | Detail |
|------|--------|
| Use `watchWithTree` for 3+ levels | `watchWithSub` is for 2 levels only |
| `subName` must NOT contain `.` | Use plain words: `'comments'`, `'replies'` |
| `typeTag` must be a string literal | Never `T.toString()` — breaks in release builds |
| Never call `atClient.collection()` with a composed namespace | Always use `subCollection(parent:)` |
| `cleanupOrphansOnCreation: true` on root | Removes dangling sub-items from expired ancestors at startup |
| Cast `TreeNode<dynamic>.parent.obj` | Branches are `TreeNode<dynamic>` — cast `obj` to the concrete type |
