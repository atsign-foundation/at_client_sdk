import 'dart:async';
import 'dart:collection';

import 'exceptions.dart';

/// The runs queued behind the one that owns a key.
final class _Slot {
  final waiters = Queue<Completer<void>>();
}

/// Serialises work that shares a key: each [run] starts only after every
/// earlier [run] on the same key has finished, however it ended.
///
/// A key holds at most [maxQueuedPerKey] waiters. The run that would be one
/// too many rejects with a [QueueLimitException] before it queues, so a body
/// that stalls cannot grow its key's queue without bound: the runs already
/// queued still wait behind it, and later callers fail fast.
final class KeyedQueue<K> {
  /// How many waiters one key holds when no other cap is given.
  static const defaultMaxQueuedPerKey = 64;

  /// How many waiters one key may hold; a [run] beyond it rejects.
  final int maxQueuedPerKey;

  /// Creates a queue that holds at most [maxQueuedPerKey] waiters per key.
  ///
  /// A [maxQueuedPerKey] below 1 is an [ArgumentError] naming the parameter:
  /// it would reject every run on a busy key.
  KeyedQueue({this.maxQueuedPerKey = defaultMaxQueuedPerKey}) {
    if (maxQueuedPerKey < 1) {
      throw ArgumentError.value(
          maxQueuedPerKey, 'maxQueuedPerKey', 'must be at least 1');
    }
  }

  /// The slot of every key busy or awaited right now.
  final _slots = <K, _Slot>{};

  /// How many keys are busy or awaited right now.
  int get length => _slots.length;

  /// Runs [body] after every earlier [run] on [key] has finished.
  ///
  /// The first run on a key starts at once and allocates no completer. Each
  /// later run waits in order; one that would be the ([maxQueuedPerKey] + 1)th
  /// waiter throws a [QueueLimitException] before it queues.
  Future<R> run<R>(K key, Future<R> Function() body) async {
    final slot = _slots[key];
    if (slot == null) {
      final fresh = _Slot();
      _slots[key] = fresh;
      return _drain(key, fresh, body);
    }
    if (slot.waiters.length >= maxQueuedPerKey) {
      throw QueueLimitException(maxQueuedPerKey);
    }
    final waiter = Completer<void>();
    slot.waiters.add(waiter);
    await waiter.future;
    return _drain(key, slot, body);
  }

  /// Runs [body] as [slot]'s owner, then hands the slot to its first waiter
  /// in order, or forgets [key] when its slot is still this one.
  Future<R> _drain<R>(K key, _Slot slot, Future<R> Function() body) async {
    try {
      return await body();
    } finally {
      if (slot.waiters.isNotEmpty) {
        slot.waiters.removeFirst().complete();
      } else if (identical(_slots[key], slot)) {
        _slots.remove(key);
      }
    }
  }

  /// Forgets every entry; an in-flight run and the waiters already queued
  /// behind it still drain in order.
  void clear() => _slots.clear();
}
