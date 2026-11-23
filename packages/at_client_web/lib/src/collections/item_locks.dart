import 'dart:async';

import 'package:at_client/at_client.dart' show Atsign;

import '../exceptions.dart';

/// Serialises operations on one item, keyed by the collection's namespace
/// (already folded by the session), the item id folded to lower case and the
/// owner. The key ignores every option a collection was opened with, so two
/// handles on one item queue behind one another.
///
/// An entry lives only while an operation holds or awaits it: the last
/// waiter to finish removes it.
final class ItemLocks {
  final _locks = <(String, String, String), Completer<void>>{};

  /// How many items are locked or awaited right now.
  int get length => _locks.length;

  /// Runs [body] after every earlier [run] on the same item has finished.
  Future<R> run<R>(String namespace, String id, Atsign owner,
      Future<R> Function() body) async {
    final key = (namespace, foldItemId(id), owner.toString());
    final previous = _locks[key];
    final done = Completer<void>();
    _locks[key] = done;
    try {
      if (previous != null) await previous.future;
      return await body();
    } finally {
      done.complete();
      if (identical(_locks[key], done)) {
        _locks.remove(key);
      }
    }
  }

  /// Forgets every entry; a waiter already queued still runs in order.
  void clear() => _locks.clear();
}
