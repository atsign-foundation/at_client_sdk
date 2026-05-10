// Worked example: posts and comments via AtCollection sub-collections.
//
// Demonstrates:
//   - creating a sub-collection from a parent CItem (post.subCollection)
//   - save() / getItems() against the sub-collection
//   - CSubItemUpdated / CSubItemDeleted events on the PARENT collection
//   - prevent-by-default delete: parent with self-owned descendants
//   - cascade: true delete: descendants vanish along with the parent
//
// Run two copies, e.g.:
//   dart run bin/collections_subcollections.dart -R sender -O @bob
//   dart run bin/collections_subcollections.dart -R receiver -O @alice

import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/init_example_context.dart';

// --- Domain objects ---------------------------------------------------------

class BlogPost {
  final String title;
  final String body;
  BlogPost(this.title, this.body);
  Map<String, dynamic> toJson() => {'title': title, 'body': body};
  factory BlogPost.fromJson(Map<String, dynamic> json) =>
      BlogPost(json['title'], json['body']);
  @override
  String toString() => 'BlogPost($title)';
}

class BlogComment {
  final String text;
  BlogComment(this.text);
  Map<String, dynamic> toJson() => {'text': text};
  factory BlogComment.fromJson(Map<String, dynamic> json) =>
      BlogComment(json['text']);
  @override
  String toString() => 'BlogComment($text)';
}

// --- Main -------------------------------------------------------------------

void main(List<String> args) async {
  stdout.writeln('Collections - sub-collections (blog + comments)');
  final c = await getExampleContext(args);
  c.progressController.stream.listen(
    (s) => stdout.writeln('${DateTime.now()} | $s'),
  );
  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final posts = await c.atClient.collection<BlogPost>(
    'posts.$applicationNamespace',
    exampleDefaultExpiration,
    eventSource: EventSource.both,
    fromJson: BlogPost.fromJson,
    typeTag: 'BlogPost',
  );

  switch (c.role) {
    case ExampleRole.sender:
      await sender(c, posts);
      break;
    case ExampleRole.receiver:
      await receiver(c, posts);
      break;
  }
  exit(0);
}

// --- Sender -----------------------------------------------------------------

Future<void> sender(ExampleContext c, AtCollection<BlogPost> posts) async {
  final progress = c.progressController.sink;
  final audience = c.otherAtSigns ?? const <Atsign>{};

  // 1. Create and share a post.
  progress.add('Creating a post, sharing with $audience');
  final post = await posts.create(
    obj: BlogPost('Hello World', 'This is a post shared with $audience'),
    sharedWith: audience,
  );
  progress.add('Saved post id=${post.id}');

  // 2. Open a comments sub-collection on that post, and comment on it.
  final comments = posts.subCollection<BlogComment>(
    parent: post,
    subName: 'comments',
    defaultExpiration: exampleDefaultExpiration,
    fromJson: BlogComment.fromJson,
    typeTag: 'BlogComment',
  );
  final myComment = await comments.create(
    obj: BlogComment('Author\'s opening comment from ${c.atClient.atSign}'),
    sharedWith: audience,
  );
  progress.add('Saved comment id=${myComment.id} on post ${post.id}');

  // 3. Wire up sub-item event listeners on the PARENT collection to see
  //    comments coming in from the other side.
  posts.subUpdates.listen((e) {
    progress.add('Sub-update from ${e.owner}: id=${e.id} sub=${e.subName}');
  });
  posts.subDeletes.listen((e) {
    progress.add('Sub-delete from ${e.owner}: id=${e.id} sub=${e.subName}');
  });

  // Linger briefly so the receiver can land its own comment.
  progress.add('Lingering 15s to observe incoming sub-updates...');
  await Future.delayed(const Duration(seconds: 15));

  // 4. Demonstrate prevent-by-default vs cascade delete.
  try {
    progress.add('Attempting delete(post) WITHOUT cascade...');
    await posts.delete(post);
    progress.add('Unexpected success — no descendants present.');
  } on StateError catch (e) {
    progress.add('Prevented as expected: $e');
  }

  progress.add('Now delete(post, cascade: true)...');
  await posts.delete(post, cascade: true);
  progress.add('Post ${post.id} and its comments are gone on our side.');
}

// --- Receiver ---------------------------------------------------------------

Future<void> receiver(ExampleContext c, AtCollection<BlogPost> posts) async {
  final progress = c.progressController.sink;
  final audience = c.otherAtSigns ?? const <Atsign>{};

  // Watch for updates at the parent level AND sub-item events.
  posts.updates.listen((e) async {
    try {
      final p = await posts.get(e.id, e.owner);
      progress.add('Post arrived from ${e.owner}: "${p.obj.title}"');
      // On first arrival, post a comment back.
      final comments = posts.subCollection<BlogComment>(
        parent: p,
        subName: 'comments',
        defaultExpiration: exampleDefaultExpiration,
        fromJson: BlogComment.fromJson,
        typeTag: 'BlogComment',
      );
      final mine = await comments.create(
        obj: BlogComment('Receiver comment from ${c.atClient.atSign}'),
        sharedWith: {e.owner, ...audience}..remove(c.atClient.atSign),
      );
      progress.add('Saved our comment id=${mine.id} on post ${p.id}');
    } catch (err) {
      progress.add('Error handling incoming post: $err');
    }
  });

  posts.subUpdates.listen((e) {
    progress.add('Sub-update from ${e.owner}: id=${e.id} sub=${e.subName}');
  });
  posts.subDeletes.listen((e) {
    progress.add('Sub-delete from ${e.owner}: id=${e.id} sub=${e.subName}');
  });

  // When the sender cascades a parent delete, our sub-collection's
  // parent-delete listener automatically cleans up our self-owned
  // sub-items. For cold starts (app wasn't running when the parent was
  // deleted), the app would call `subCollection.cleanupOrphans()` at
  // startup for each known parent.

  progress.add('Lingering for 30s');
  await Future.delayed(const Duration(seconds: 30));
}
