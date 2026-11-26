import 'package:at_client/at_client.dart' show Atsign;

import '../keyed_queue.dart';

/// The item id folded the way AtCollection folds it.
///
/// The one fold at_client_web keeps: a lock key is built from ids JS gave it
/// and from ids AtCollection returned, and those meet only if both take this
/// fold. Every other id here passes as it is; at_client folds its own.
String _foldItemId(String id) => id.toLowerCase();

/// Serialises operations on one item, keyed by the collection's namespace
/// (already folded by the session), the item id folded to lower case and the
/// owner. The key ignores every option a collection was opened with, so two
/// handles on one item queue behind one another.
final class ItemLocks {
  final _locks = KeyedQueue<(String, String, String)>();

  /// How many items are locked or awaited right now.
  int get length => _locks.length;

  /// Runs [body] after every earlier [run] on the same item has finished.
  Future<R> run<R>(String namespace, String id, Atsign owner,
          Future<R> Function() body) =>
      _locks.run((namespace, _foldItemId(id), owner.toString()), body);

  /// Forgets every entry; a waiter already queued still runs in order.
  void clear() => _locks.clear();
}
