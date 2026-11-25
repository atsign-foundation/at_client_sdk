import 'dart:async';

/// Serialises work that shares a key: each [run] starts only after every
/// earlier [run] on the same key has finished, however it ended.
///
/// An entry lives only while an operation holds or awaits it: the last
/// waiter to finish removes it.
final class KeyedQueue<K> {
  final _tails = <K, Completer<void>>{};

  /// How many keys are busy or awaited right now.
  int get length => _tails.length;

  /// Runs [body] after every earlier [run] on [key] has finished.
  Future<R> run<R>(K key, Future<R> Function() body) async {
    final previous = _tails[key];
    final done = Completer<void>();
    _tails[key] = done;
    try {
      if (previous != null) await previous.future;
      return await body();
    } finally {
      done.complete();
      if (identical(_tails[key], done)) {
        _tails.remove(key);
      }
    }
  }

  /// Forgets every entry; a waiter already queued still runs in order.
  void clear() => _tails.clear();
}
