# Reactively Watching a Full Tree Hierarchy in Firestore (Posts > Comments > Replies)

Firestore does not support deep recursive listeners out of the box. A single `onSnapshot` listener on a collection only watches that collection's documents — it does not automatically propagate changes in nested subcollections. To reactively watch a full `posts > comments > replies` tree you must compose multiple listeners.

---

## Strategy Overview

There are two main approaches:

1. **Collection Group Listeners** — listen to all `comments` and `replies` subcollections across the entire database at once.
2. **Layered Listeners** — listen to `posts`, then for each post attach a listener to its `comments`, then for each comment attach a listener to its `replies`.

---

## Approach 1: Collection Group Listeners (Recommended for most cases)

Firestore's `collectionGroup` query lets you listen to every subcollection with a given name, regardless of where it lives in the document hierarchy.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

final db = FirebaseFirestore.instance;

// Watch all posts
final postsStream = db.collection('posts').snapshots();

// Watch ALL comments across every post
final commentsStream = db.collectionGroup('comments').snapshots();

// Watch ALL replies across every comment across every post
final repliesStream = db.collectionGroup('replies').snapshots();
```

You can then combine these three streams in your UI layer (e.g., using `rxdart`'s `CombineLatestStream` or `StreamZip`, or by managing state in a BLoC/provider).

### Pros
- Simple — three listeners regardless of how many posts/comments exist.
- Low listener count.

### Cons
- You receive flat lists; you must reassemble the tree in memory using document IDs and parent path references.
- Requires composite indexes for ordered collection group queries.

### Reassembling the tree

Each document has a `reference` property. You can extract the parent path to figure out which post a comment belongs to, and which comment a reply belongs to.

```dart
void processComments(QuerySnapshot snapshot) {
  for (final doc in snapshot.docs) {
    // doc.reference.path looks like: posts/{postId}/comments/{commentId}
    final segments = doc.reference.path.split('/');
    final postId = segments[1]; // index 1 is the postId
    // use postId to group comments
  }
}

void processReplies(QuerySnapshot snapshot) {
  for (final doc in snapshot.docs) {
    // doc.reference.path: posts/{postId}/comments/{commentId}/replies/{replyId}
    final segments = doc.reference.path.split('/');
    final postId = segments[1];
    final commentId = segments[3];
    // use postId + commentId to group replies
  }
}
```

---

## Approach 2: Layered Listeners

This approach is more granular and keeps the tree structure natural in your code, but it creates more listener subscriptions as the data grows.

```dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostTreeWatcher {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Holds all active subscriptions so they can be cancelled
  final List<StreamSubscription> _subscriptions = [];

  void startWatching() {
    // Step 1: Watch the posts collection
    final postsSub = _db.collection('posts').snapshots().listen((postsSnapshot) {
      for (final postChange in postsSnapshot.docChanges) {
        if (postChange.type == DocumentChangeType.removed) {
          // Clean up comment listeners for removed posts if tracked separately
          continue;
        }
        _watchComments(postChange.doc.reference);
      }
    });
    _subscriptions.add(postsSub);
  }

  void _watchComments(DocumentReference postRef) {
    // Step 2: For each post, watch its comments subcollection
    final commentsSub = postRef.collection('comments').snapshots().listen((commentsSnapshot) {
      for (final commentChange in commentsSnapshot.docChanges) {
        if (commentChange.type == DocumentChangeType.removed) {
          continue;
        }
        _watchReplies(commentChange.doc.reference);
      }
    });
    _subscriptions.add(commentsSub);
  }

  void _watchReplies(DocumentReference commentRef) {
    // Step 3: For each comment, watch its replies subcollection
    final repliesSub = commentRef.collection('replies').snapshots().listen((repliesSnapshot) {
      for (final replyDoc in repliesSnapshot.docs) {
        // Handle reply updates here
        print('Reply updated: ${replyDoc.id} under ${commentRef.path}');
      }
    });
    _subscriptions.add(repliesSub);
  }

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
```

### Pros
- The tree structure is explicit and easy to reason about.
- Listeners are scoped — a reply listener only fires for its own comment's replies.

### Cons
- Listener count grows with data: O(posts) + O(comments) + O(replies).
- Managing subscription lifecycles (especially for removed documents) requires careful bookkeeping.
- Not suitable for large datasets.

---

## Approach 3: Combining Streams with rxdart

If you want a single reactive stream that emits the full assembled tree whenever anything changes, use `rxdart` to combine the three collection group streams.

```yaml
# pubspec.yaml
dependencies:
  rxdart: ^0.27.0
  cloud_firestore: ^5.0.0
```

```dart
import 'package:rxdart/rxdart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Stream<PostTree> watchFullTree() {
  final postsStream = FirebaseFirestore.instance.collection('posts').snapshots();
  final commentsStream = FirebaseFirestore.instance.collectionGroup('comments').snapshots();
  final repliesStream = FirebaseFirestore.instance.collectionGroup('replies').snapshots();

  return Rx.combineLatest3(
    postsStream,
    commentsStream,
    repliesStream,
    (QuerySnapshot posts, QuerySnapshot comments, QuerySnapshot replies) {
      return _assembleTree(posts, comments, replies);
    },
  );
}

PostTree _assembleTree(
  QuerySnapshot posts,
  QuerySnapshot comments,
  QuerySnapshot replies,
) {
  // Group comments by postId
  final commentsByPost = <String, List<QueryDocumentSnapshot>>{};
  for (final comment in comments.docs) {
    final postId = comment.reference.path.split('/')[1];
    commentsByPost.putIfAbsent(postId, () => []).add(comment);
  }

  // Group replies by commentId
  final repliesByComment = <String, List<QueryDocumentSnapshot>>{};
  for (final reply in replies.docs) {
    final commentId = reply.reference.path.split('/')[3];
    repliesByComment.putIfAbsent(commentId, () => []).add(reply);
  }

  return PostTree(
    posts: posts.docs,
    commentsByPost: commentsByPost,
    repliesByComment: repliesByComment,
  );
}

class PostTree {
  final List<QueryDocumentSnapshot> posts;
  final Map<String, List<QueryDocumentSnapshot>> commentsByPost;
  final Map<String, List<QueryDocumentSnapshot>> repliesByComment;

  PostTree({
    required this.posts,
    required this.commentsByPost,
    required this.repliesByComment,
  });
}
```

---

## Security Rules Consideration

Collection group queries require explicit Firestore security rules that match the subcollection name across all paths:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{path=**}/comments/{commentId} {
      allow read: if request.auth != null;
    }
    match /{path=**}/replies/{replyId} {
      allow read: if request.auth != null;
    }
  }
}
```

---

## Recommendation

| Scenario | Recommended Approach |
|---|---|
| Large dataset, many posts/comments | Collection Group Listeners (Approach 1 or 3) |
| Small dataset, tree structure matters | Layered Listeners (Approach 2) |
| UI needs a single reactive state update | rxdart CombineLatest (Approach 3) |
| You want to filter by a specific post only | Layered Listeners scoped to that post |

For most production applications, **Approach 3** (collection group + rxdart) gives you the best balance of simplicity, reactive correctness, and scalability.
