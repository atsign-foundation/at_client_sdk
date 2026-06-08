# Fetching Comment Data on a CSubItemUpdated Event

When you receive a `CSubItemUpdated` event, the event itself only carries metadata — the
`id` and `owner` of the leaf sub-item, plus an `ancestry` chain describing all ancestors
up to (but not including) the leaf. To get the actual comment data, you use
`collection.getDescendant(...)`.

## How it works

`CSubItemUpdated` has these fields:

```dart
final class CSubItemUpdated extends CEvent {
  final Atsign owner;               // owner of the leaf (the comment)
  final String id;                  // id of the leaf (the comment)
  final List<CAncestor> ancestry;   // root-to-direct-parent chain
  String get subName => ancestry.last.subName;
}
```

`ancestry` is ordered **root-first**: `ancestry[0]` is the outermost ancestor (e.g. the
post), and `ancestry.last` is the direct parent of the comment. The event's `id` is the
comment itself.

## Fetching the comment with getDescendant

Call `collection.getDescendant(...)` on the **root-level collection** (not a sub-collection
you construct manually). Pass the full `ancestry` from the event, plus the leaf's `id` and
`owner`:

```dart
collection.subUpdates.listen((event) async {
  final comment = await collection.getDescendant<Comment>(
    ancestry: event.ancestry,        // root-to-direct-parent chain from the event
    id: event.id,                    // the comment's id
    owner: event.owner,              // the comment's owner
    leafExpiration: const Duration(days: 30),  // TTL for the fetched leaf item
    leafFromJson: Comment.fromJson,  // omit if already registered via registerFactory
    leafTypeTag: 'Comment',          // omit if already registered via registerFactory
  );

  if (comment == null) {
    // An ancestor expired between the event firing and the fetch — handle gracefully
    return;
  }

  // comment.obj is your Comment domain object
  handleComment(comment);
});
```

`getDescendant` returns `null` if any item in the ancestor chain has expired or is
unavailable by the time you fetch. Always guard against the `null` case.

## Complete example: posts with comments

Suppose your data model is posts (root collection) with comments as a sub-collection:

```dart
// Root collection for posts
final posts = await atClient.collection<Post>(
  'posts.my_app',
  const Duration(days: 90),
  fromJson: Post.fromJson,
  typeTag: 'Post',
  cleanupOrphansOnCreation: true,
);

// Listen for new or updated comments on any post
posts.subUpdates.listen((event) async {
  // Filter to only comment-level events (direct children of posts)
  // ancestry has exactly one entry when the comment is a direct child of a post
  if (event.ancestry.length != 1) return;  // not a direct comment, skip

  final comment = await posts.getDescendant<Comment>(
    ancestry: event.ancestry,
    id: event.id,
    owner: event.owner,
    leafExpiration: const Duration(days: 30),
    leafFromJson: Comment.fromJson,
    leafTypeTag: 'Comment',
  );

  if (comment == null) return;

  final parentPostId = event.ancestry[0].id;  // ancestry[0] is the post (the root)
  print('New comment on post $parentPostId: ${comment.obj.text}');
});
```

## Do NOT do this

Do not construct a flat `AtCollection` at the composed namespace to read sub-items:

```dart
// WRONG — reads will return null even though notifications match
final comments = await atClient.collection<Comment>(
  'comments.posts.my_app',   // do NOT do this
  ...
);
```

Sub-collections must be opened via `subCollection(parent:)` or fetched via
`getDescendant(ancestry:)`.

## Filtering to a specific post's comments

If you only care about comments on a particular post item, check `ancestry.last.id`:

```dart
posts.subUpdates.listen((event) async {
  // Only process comments that belong to myPost
  if (event.ancestry.last.id != myPost.id) return;

  final comment = await posts.getDescendant<Comment>(
    ancestry: event.ancestry,
    id: event.id,
    owner: event.owner,
    leafExpiration: const Duration(days: 30),
    leafFromJson: Comment.fromJson,
    leafTypeTag: 'Comment',
  );

  if (comment == null) return;
  handleComment(comment);
});
```

`ancestry.last` is always the direct parent of the leaf, so this check correctly matches
only comments whose immediate parent is `myPost`.

## Important pitfall: CSubItemDeleted ancestry has null owners

If you also listen to `subDeletes`, be aware that `CAncestor.owner` is always `null` inside
the `ancestry` of a `CSubItemDeleted` event. This means `getDescendant` cannot be called on
a delete event. The recommended fix is to cache the last `CSubItemUpdated` event for each
`(id, subName)` pair while your stream is active, so you have the populated ancestry
available when the corresponding delete fires.
