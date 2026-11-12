/// AtEasy: a typed-collection facade over [AtClient] for app code.
///
/// Pure Dart with no web-only imports, so it runs in VM tests.
library;

import 'dart:async';

import 'package:at_client/at_client.dart';

const _anyTypeTag = 'n/a';

/// The default for how long one read of an item may take before the item is
/// treated as unreadable.
const _defaultReadTimeout = Duration(seconds: 30);

typedef _Predicate = bool Function(CItem<Map<String, dynamic>> item);

typedef _Comparator = bool Function(Object? actual, Object? value);

final Map<String, _Comparator> _operators = {
  '==': (a, v) => a == v,
  '!=': (a, v) => a != v,
  '<': (a, v) => _ordered(a, v, (c) => c < 0),
  '<=': (a, v) => _ordered(a, v, (c) => c <= 0),
  '>': (a, v) => _ordered(a, v, (c) => c > 0),
  '>=': (a, v) => _ordered(a, v, (c) => c >= 0),
  'isNull': (a, _) => a == null,
  'isNotNull': (a, _) => a != null,
};

/// Entry point. Creates and caches [AtEasyCollection]s for one app.
class AtEasy {
  /// Creates a facade over [_client] for [app]. [app] must not be empty. It is
  /// the suffix that a bare collection name gets.
  ///
  /// [readTimeout] caps each item read that [AtEasyCollection.watch] makes to
  /// build an event. An item whose read takes longer is delivered as `null`.
  /// It must be positive.
  AtEasy(
    this._client, {
    required String app,
    Duration readTimeout = _defaultReadTimeout,
  })  : _app = app,
        _readTimeout = readTimeout {
    if (app.isEmpty) {
      throw ArgumentError.value(app, 'app', 'must not be empty');
    }
    if (readTimeout <= Duration.zero) {
      throw ArgumentError.value(readTimeout, 'readTimeout', 'must be positive');
    }
  }

  final AtClient _client;
  final String _app;
  final Duration _readTimeout;
  final Map<String, AtEasyCollection> _registry = {};

  /// Returns the collection for [name], creating it on first use.
  ///
  /// A [name] with no `.` is qualified as `<name>.<app>`. A dotted [name] is
  /// used as the namespace unchanged. Repeating a namespace returns the same
  /// instance; a different [type], [expiration] or [eventSource] for that
  /// namespace throws [StateError].
  ///
  /// [expiration] must be positive.
  AtEasyCollection collection(
    String name, {
    required String type,
    required Duration expiration,
    String eventSource = 'data',
  }) {
    if (type.isEmpty) {
      throw ArgumentError.value(type, 'type', 'must not be empty');
    }
    if (expiration <= Duration.zero) {
      throw ArgumentError.value(expiration, 'expiration', 'must be positive');
    }
    final source = _eventSourceFor(eventSource);
    final namespace = name.contains('.') ? name : '$name.$_app';

    final existing = _registry[namespace];
    if (existing != null) {
      if (existing.type != type) {
        throw StateError(
          '$namespace is already open with type "${existing.type}", '
          'not "$type"',
        );
      }
      if (existing.expiration != expiration ||
          existing.eventSource != eventSource) {
        throw StateError(
          '$namespace is already open with a different expiration or '
          'eventSource',
        );
      }
      return existing;
    }

    final upstream = _client.collection<Map<String, dynamic>>(
      namespace,
      expiration,
      eventSource: source,
      writeTypeTag: type,
      cleanupOrphansOnCreation: false,
    );
    final created = AtEasyCollection._(
      client: _client,
      namespace: namespace,
      type: type,
      expiration: expiration,
      eventSource: eventSource,
      upstream: upstream,
      readTimeout: _readTimeout,
    );
    _registry[namespace] = created;
    upstream.then<void>((_) {}, onError: (Object _) {
      if (identical(_registry[namespace], created)) _registry.remove(namespace);
    });
    return created;
  }
}

EventSource _eventSourceFor(String name) => switch (name) {
      'data' => EventSource.data,
      'notifs' => EventSource.notifs,
      'both' => EventSource.both,
      _ => throw ArgumentError.value(
          name,
          'eventSource',
          'must be one of data, notifs, both',
        ),
    };

/// A typed collection of items of one [type] in one namespace.
class AtEasyCollection {
  AtEasyCollection._({
    required AtClient client,
    required this.namespace,
    required this.type,
    required this.expiration,
    required this.eventSource,
    required Future<AtCollection<Map<String, dynamic>>> upstream,
    required Duration readTimeout,
  })  : _client = client,
        _upstream = upstream,
        _readTimeout = readTimeout;

  final AtClient _client;
  final Duration _readTimeout;
  final Future<AtCollection<Map<String, dynamic>>> _upstream;

  /// The fully qualified namespace, for example `todos.demo`.
  final String namespace;

  /// The type tag stamped on items created here.
  final String type;

  /// How long each item created in this collection lives before it expires.
  final Duration expiration;

  /// One of `data`, `notifs` or `both`.
  final String eventSource;

  bool _isVisible(CItem<Map<String, dynamic>> item) =>
      item.type == type || item.type == _anyTypeTag;

  /// Creates an item with [data]. [id] is generated when omitted.
  Future<AtEasyItem> create(
    Map<String, dynamic> data, {
    String? id,
    Iterable<String> sharedWith = const [],
  }) async {
    final coll = await _upstream;
    final item = await coll.create(
      obj: data,
      id: id,
      sharedWith: _atsigns(sharedWith),
    );
    return _view(item);
  }

  /// Replaces the data of the item [id], keeping its sharing and expiry.
  ///
  /// Throws [StateError] when the item is missing or owned by another atSign.
  Future<AtEasyItem> update(String id, Map<String, dynamic> data) async {
    final coll = await _upstream;
    final current = await _writable(coll, id);
    final replacement = coll.draft(
      obj: data,
      id: id,
      sharedWith: current.sharedWith,
      expiresAt: current.expiresAt,
      availableAt: current.availableAt,
    );
    await coll.update(replacement);
    return _view(replacement);
  }

  /// Adds [atSigns] to the recipients of the item [id], keeping existing ones.
  ///
  /// This is a read-modify-write. Two concurrent calls can drop one
  /// recipient, because upstream has no add-only operation.
  Future<AtEasyItem> share(String id, Iterable<String> atSigns) async {
    final coll = await _upstream;
    final item = await _writable(coll, id);
    final recipients = {...item.sharedWith, ..._atsigns(atSigns)};
    await coll.updateSharedWith(item, recipients, unshareWithOthers: false);
    return _view(item);
  }

  /// Deletes the item [id]. Set [cascade] to also delete its sub-items.
  Future<void> remove(String id, {bool cascade = false}) async {
    final coll = await _upstream;
    final item = await _writable(coll, id);
    await coll.delete(item, cascade: cascade);
  }

  /// All visible items of this collection.
  Future<List<AtEasyItem>> get() => query().get();

  /// Starts a query that keeps items where [path] satisfies [op] against
  /// [value]. See [AtEasyQuery.where].
  AtEasyQuery where(String path, String op, Object? value) =>
      query().where(path, op, value);

  /// Starts a query ordered by [path]. See [AtEasyQuery.orderByPath].
  AtEasyQuery orderByPath(String path, {bool descending = false}) =>
      query().orderByPath(path, descending: descending);

  /// An unfiltered query over this collection. Add [AtEasyQuery.where],
  /// [AtEasyQuery.orderByPath] or [AtEasyQuery.limit], then call
  /// [AtEasyQuery.get].
  AtEasyQuery query() => AtEasyQuery._(this, const [], null, null);

  /// Calls [onEvent] for each change to this collection, until the returned
  /// function is called.
  ///
  /// Events for items of another type are dropped when the item can be read.
  /// Deletions, and events for items that cannot be read (including a read
  /// that times out), are delivered with `item == null`. Errors from the
  /// upstream event stream go to [onError] when given; otherwise they are
  /// reported to the current [Zone] as uncaught errors. The subscription keeps
  /// running after one.
  void Function() watch(
    void Function(AtEasyEvent event) onEvent, {
    void Function(Object error)? onError,
  }) {
    final subscription = Stream.fromFuture(_upstream)
        .asyncExpand((coll) => coll.watch())
        .asyncMap(_toEvent)
        .listen(
      (event) {
        if (event != null) onEvent(event);
      },
      onError: onError == null ? null : (Object e) => onError(e),
    );
    return () {
      subscription.cancel();
    };
  }

  Future<AtEasyEvent?> _toEvent(CEvent event) async {
    AtEasyItem? view;
    if (event case CItemUpdated() || CItemAvailable() || CItemExpiringSoon()) {
      final item = await _readOrNull(event.id, event.owner);
      if (item != null && !_isVisible(item)) return null;
      view = item == null ? null : _view(item);
    }
    return AtEasyEvent._(
      kind: _kindOf(event),
      id: event.id,
      owner: event.owner.toString(),
      item: view,
    );
  }

  /// The item [id] owned by [owner], or null when it cannot be read or the
  /// read takes longer than [_readTimeout].
  Future<CItem<Map<String, dynamic>>?> _readOrNull(
      String id, Atsign owner) async {
    final coll = await _upstream;
    try {
      return await coll.getOrNull(id, owner).timeout(_readTimeout);
    } on CItemReadException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// The items of [coll] this device can read, from any owner. Skips shared
  /// records whose read fails with [CItemReadException].
  Stream<CItem<Map<String, dynamic>>> _readableItems(
    AtCollection<Map<String, dynamic>> coll, {
    String? id,
  }) =>
      coll
          .getItemsAsStream(id: id)
          .handleError((Object _) {}, test: (e) => e is CItemReadException);

  /// The visible item [id] that this atSign may change. Throws [StateError]
  /// when it is missing, or when another atSign owns it.
  Future<CItem<Map<String, dynamic>>> _writable(
    AtCollection<Map<String, dynamic>> coll,
    String id,
  ) async {
    final own = (await coll.getItems(id: id, owner: _client.atSign))
        .where(_isVisible)
        .toList();
    if (own.isNotEmpty) return own.first;

    final peers = await _readableItems(coll, id: id).where(_isVisible).toList();
    if (peers.isNotEmpty) {
      throw StateError(
        'item $id is owned by ${peers.first.owner}; '
        'only the owner can change it',
      );
    }
    throw StateError('no item $id in $namespace');
  }
}

/// A filter, ordering and limit over one collection. Immutable: each call
/// returns a new query.
class AtEasyQuery {
  AtEasyQuery._(
    this._collection,
    this._predicates,
    this._order,
    this._limit,
  );

  final AtEasyCollection _collection;
  final List<_Predicate> _predicates;
  final _OrderBy? _order;
  final int? _limit;

  /// Keeps items where the value at [path] satisfies [op] against [value].
  ///
  /// [path] is dot-separated and walks the item's data. A missing or
  /// non-map step reads as `null`. [op] is one of `==`, `!=`, `<`, `<=`,
  /// `>`, `>=`, `isNull` or `isNotNull`. Chained calls combine with AND.
  ///
  /// [value] must be null, a `num`, a `String` or a `bool`. The ordering
  /// operators match only two numbers or two strings. Any other pair,
  /// including a null, a bool or a mixed type, is excluded and never throws.
  AtEasyQuery where(String path, String op, Object? value) {
    final compare = _operators[op];
    if (compare == null) {
      throw ArgumentError('unknown operator "$op"');
    }
    if (value != null && value is! num && value is! String && value is! bool) {
      throw ArgumentError.value(
        value,
        'value',
        'must be null, a num, a String or a bool',
      );
    }
    return AtEasyQuery._(
      _collection,
      [..._predicates, _predicateFor(path, compare, value)],
      _order,
      _limit,
    );
  }

  /// Orders results by the value at [path]. Values sort null, then bool,
  /// then num, then String, then other values. Ties break on item id.
  /// [descending] reverses the whole order, tie-break included.
  AtEasyQuery orderByPath(String path, {bool descending = false}) =>
      AtEasyQuery._(
        _collection,
        _predicates,
        _OrderBy(path.split('.'), descending: descending),
        _limit,
      );

  /// Keeps at most [n] results. Applied after ordering.
  AtEasyQuery limit(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'must not be negative');
    return AtEasyQuery._(_collection, _predicates, _order, n);
  }

  /// Runs the query. Visible items are kept, then the [where] filters are
  /// applied (ANDed), then the order, then the limit.
  Future<List<AtEasyItem>> get() async {
    final coll = await _collection._upstream;
    final readable = _collection._readableItems(coll);
    final items = await readable
        .where(_collection._isVisible)
        .where((item) => _predicates.every((predicate) => predicate(item)))
        .toList();
    final order = _order;
    if (order != null) {
      final keyed = {
        for (final item in items)
          item: _SortKey(_valueAt(item.obj, order.segments), item.id),
      };
      items.sort((a, b) => keyed[a]!.compareTo(keyed[b]!));
      if (order.descending) items.setAll(0, items.reversed.toList());
    }
    final cap = _limit;
    if (cap != null && items.length > cap) items.removeRange(cap, items.length);
    return [for (final item in items) _view(item)];
  }
}

class _OrderBy {
  const _OrderBy(this.segments, {required this.descending});

  final List<String> segments;
  final bool descending;
}

_Predicate _predicateFor(String path, _Comparator compare, Object? value) {
  final segments = path.split('.');
  return (item) => compare(_valueAt(item.obj, segments), value);
}

bool _ordered(Object? a, Object? b, bool Function(int) accept) {
  final int? comparison = switch ((a, b)) {
    (num x, num y) => x.compareTo(y),
    (String x, String y) => x.compareTo(y),
    _ => null,
  };
  return comparison != null && accept(comparison);
}

Object? _valueAt(Object? root, List<String> segments) {
  var current = root;
  for (final segment in segments) {
    if (current is! Map || !current.containsKey(segment)) return null;
    current = current[segment];
  }
  return current;
}

/// Total order over values of any type, with an id tie-break.
class _SortKey implements Comparable<_SortKey> {
  const _SortKey(this.value, this.id);

  final Object? value;
  final String id;

  int get _rank => switch (value) {
        null => 0,
        bool() => 1,
        num() => 2,
        String() => 3,
        _ => 4,
      };

  @override
  int compareTo(_SortKey other) {
    final byRank = _rank.compareTo(other._rank);
    if (byRank != 0) return byRank;
    final byValue = switch ((value, other.value)) {
      (bool a, bool b) => a == b ? 0 : (a ? 1 : -1),
      (num a, num b) => a.compareTo(b),
      (String a, String b) => a.compareTo(b),
      _ => 0,
    };
    return byValue != 0 ? byValue : id.compareTo(other.id);
  }
}

/// A collection item as seen by app code. Holds no upstream objects.
class AtEasyItem {
  AtEasyItem._({
    required this.id,
    required this.owner,
    required this.type,
    required this.data,
    required this.sharedWith,
    required this.createdAt,
    required this.expiresAt,
    required this.availableAt,
    required this.ancestors,
  });

  /// The item id. With [owner] and the collection it identifies the item.
  final String id;

  /// The atSign that owns the item, with its `@` prefix.
  final String owner;

  /// The type tag the item was written with, or `n/a` for untagged items.
  final String type;

  /// The item payload, as its owner wrote it.
  final Map<String, dynamic> data;

  /// The atSigns the item is shared with, each with its `@` prefix.
  final Set<String> sharedWith;

  /// When the item was first written.
  final DateTime createdAt;

  /// When the item expires.
  final DateTime expiresAt;

  /// When recipients first see the item. Null when it is available immediately.
  final DateTime? availableAt;

  /// The parent items of a sub-item, outermost first. Each entry holds the
  /// parent's owner, with its `@` prefix, and its id. Empty for a root item.
  final List<({String owner, String id})> ancestors;
}

/// A change to a collection, from [AtEasyCollection.watch].
class AtEasyEvent {
  AtEasyEvent._({
    required this.kind,
    required this.id,
    required this.owner,
    required this.item,
  });

  /// One of `updated`, `deleted`, `available`, `expiringSoon`,
  /// `readReceipt`, `subItemUpdated`, `subItemDeleted` or `unknown`.
  final String kind;

  /// The id of the changed item.
  final String id;

  /// The atSign that owns the changed item, with its `@` prefix.
  final String owner;

  /// The item after the change. Null for deletions, and for events whose item
  /// can no longer be read.
  final AtEasyItem? item;
}

String _kindOf(CEvent event) => switch (event) {
      CItemUpdated() => 'updated',
      CItemDeleted() => 'deleted',
      CItemAvailable() => 'available',
      CItemExpiringSoon() => 'expiringSoon',
      CReadReceipt() => 'readReceipt',
      CSubItemUpdated() => 'subItemUpdated',
      CSubItemDeleted() => 'subItemDeleted',
      _ => 'unknown',
    };

Set<Atsign> _atsigns(Iterable<String> names) => {
      for (final name in names) name.toAtsign(),
    };

AtEasyItem _view(CItem<Map<String, dynamic>> item) => AtEasyItem._(
      id: item.id,
      owner: item.owner.toString(),
      type: item.type,
      data: item.obj,
      sharedWith: {
        for (final recipient in item.sharedWith) recipient.toString()
      },
      createdAt: item.createdAt,
      expiresAt: item.expiresAt,
      availableAt: item.availableAt,
      ancestors: [
        for (final ancestor in item.ancestors)
          (owner: ancestor.owner.toString(), id: ancestor.id),
      ],
    );
