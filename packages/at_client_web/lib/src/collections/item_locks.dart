import 'package:at_client/at_client.dart' show Atsign;

import '../exceptions.dart';
import '../keyed_queue.dart';

/// Serialises operations on one item, keyed by the collection's namespace
/// (already folded by the session), the item id folded to lower case and the
/// owner. The key ignores every option a collection was opened with, so two
/// handles on one item queue behind one another. The lock orders writes within
/// one session, across all its handles. Two sessions (tabs, devices) do not
/// queue behind each other and can still lose an update, last writer wins; a
/// caller that needs cross-session ordering must serialise itself. An
/// atServer-side compare-and-set or version check would close the window, but
/// the atServer does not offer one today (#2620).
final class ItemLocks {
  final _locks = KeyedQueue<(String, String, String)>();

  /// How many items are locked or awaited right now.
  int get length => _locks.length;

  /// Runs [body] after every earlier [run] on the same item has finished.
  Future<R> run<R>(String namespace, String id, Atsign owner,
          Future<R> Function() body) =>
      _locks.run((namespace, foldItemId(id), owner.toString()), body);

  /// Forgets every entry; a waiter already queued still runs in order.
  void clear() => _locks.clear();
}
