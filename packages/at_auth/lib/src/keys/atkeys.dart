import 'package:at_auth/src/keys/material.dart';
import 'package:at_commons/at_commons.dart';

export 'material.dart';

abstract base class AtKeysSet {
  Atsign get atsign;
  String? get enrollmentId;

  Iterable<AtKeyPair> get keyPairs;
  Iterable<AtSymmetricKey> get symmetricKeys;

  AtKeyPair? getKeyPair(String pairId);
  AtSymmetricKey? getSymmetricKey(String id);

  @override
  bool operator ==(Object other) {
    return other is AtKeysSet &&
        other.atsign == atsign &&
        other.enrollmentId == enrollmentId &&
        _iterableEquals(other.keyPairs, keyPairs) &&
        _iterableEquals(other.symmetricKeys, symmetricKeys);
  }

  @override
  int get hashCode {
    return Object.hash(
      atsign,
      enrollmentId,
      Object.hashAll(keyPairs),
      Object.hashAll(symmetricKeys),
    );
  }
}

base mixin Writability on AtKeysSet {
  set enrollmentId(String? value);

  void addKey(AtKeysMaterial key);
  void addKeys(Iterable<AtKeysMaterial> keys);

  bool removeKeyPair(String pairId);
  bool removeSymmetricKey(String id);

  void replaceKeyPair(AtKeyPair key);
  void replaceSymmetricKey(AtSymmetricKey key);
}

final class WritableAtKeysSet extends AtKeysSet with Writability {
  final Map<String, AtKeyPair> _keyPairs;
  final Map<String, AtSymmetricKey> _symmetricKeys;

  WritableAtKeysSet({
    required Atsign atsign,
    String? enrollmentId,
    Iterable<AtKeysMaterial> keys = const [],
  }) : this._indexed(
          atsign: atsign,
          enrollmentId: enrollmentId,
          index: _AtKeysIndex.from(keys),
        );

  WritableAtKeysSet._indexed({
    required this.atsign,
    required _AtKeysIndex index,
    String? enrollmentId,
  })  : _enrollmentId = enrollmentId,
        _keyPairs = index.keyPairs,
        _symmetricKeys = index.symmetricKeys;

  @override
  final Atsign atsign;

  String? _enrollmentId;

  @override
  String? get enrollmentId => _enrollmentId;

  @override
  set enrollmentId(String? value) {
    _enrollmentId = value;
  }

  @override
  Iterable<AtKeyPair> get keyPairs => _keyPairs.values;

  @override
  Iterable<AtSymmetricKey> get symmetricKeys => _symmetricKeys.values;

  AtKeysSnapshot get snapshot => AtKeysSnapshot.from(this);

  @override
  AtKeyPair? getKeyPair(String pairId) {
    return _keyPairs[pairId];
  }

  @override
  AtSymmetricKey? getSymmetricKey(String id) {
    return _symmetricKeys[id];
  }

  @override
  void addKey(AtKeysMaterial key) {
    switch (key) {
      case AtKeyPair():
        _addKeyPair(key);
      case AtSymmetricKey():
        _addSymmetricKey(key);
    }
  }

  @override
  void addKeys(Iterable<AtKeysMaterial> keys) {
    for (final key in keys) {
      addKey(key);
    }
  }

  @override
  bool removeKeyPair(String pairId) {
    return _keyPairs.remove(pairId) != null;
  }

  @override
  bool removeSymmetricKey(String id) {
    return _symmetricKeys.remove(id) != null;
  }

  @override
  void replaceKeyPair(AtKeyPair key) {
    if (!_keyPairs.containsKey(key.pairId)) {
      throw ArgumentError.value(key.pairId, 'pairId', 'Missing key pair');
    }
    _keyPairs[key.pairId] = key;
  }

  @override
  void replaceSymmetricKey(AtSymmetricKey key) {
    if (!_symmetricKeys.containsKey(key.id)) {
      throw ArgumentError.value(key.id, 'id', 'Missing symmetric key');
    }
    _symmetricKeys[key.id] = key;
  }

  void _addKeyPair(AtKeyPair key) {
    if (_keyPairs.containsKey(key.pairId)) {
      throw ArgumentError.value(key.pairId, 'pairId', 'Duplicate key pair');
    }
    _keyPairs[key.pairId] = key;
  }

  void _addSymmetricKey(AtSymmetricKey key) {
    if (_symmetricKeys.containsKey(key.id)) {
      throw ArgumentError.value(key.id, 'id', 'Duplicate symmetric key');
    }
    _symmetricKeys[key.id] = key;
  }
}

final class AtKeysSnapshot extends AtKeysSet {
  final Map<String, AtKeyPair> _keyPairs;
  final Map<String, AtSymmetricKey> _symmetricKeys;

  AtKeysSnapshot({
    required this.atsign,
    required Map<String, AtKeyPair> keyPairs,
    required Map<String, AtSymmetricKey> symmetricKeys,
    this.enrollmentId,
  })  : _keyPairs = Map.unmodifiable(keyPairs),
        _symmetricKeys = Map.unmodifiable(symmetricKeys);

  factory AtKeysSnapshot.from(WritableAtKeysSet keys) {
    return AtKeysSnapshot(
      atsign: keys.atsign,
      enrollmentId: keys.enrollmentId,
      keyPairs: keys._keyPairs,
      symmetricKeys: keys._symmetricKeys,
    );
  }

  @override
  final Atsign atsign;

  @override
  final String? enrollmentId;

  @override
  Iterable<AtKeyPair> get keyPairs => _keyPairs.values;

  @override
  Iterable<AtSymmetricKey> get symmetricKeys => _symmetricKeys.values;

  @override
  AtKeyPair? getKeyPair(String pairId) {
    return _keyPairs[pairId];
  }

  @override
  AtSymmetricKey? getSymmetricKey(String id) {
    return _symmetricKeys[id];
  }
}

final class _AtKeysIndex {
  final Map<String, AtKeyPair> keyPairs;
  final Map<String, AtSymmetricKey> symmetricKeys;

  const _AtKeysIndex({
    required this.keyPairs,
    required this.symmetricKeys,
  });

  factory _AtKeysIndex.from(Iterable<AtKeysMaterial> keys) {
    final keyPairIndex = <String, AtKeyPair>{};
    final symmetricKeyIndex = <String, AtSymmetricKey>{};

    for (final key in keys) {
      switch (key) {
        case AtKeyPair():
          if (keyPairIndex.containsKey(key.pairId)) {
            throw ArgumentError.value(
              key.pairId,
              'pairId',
              'Duplicate key pair',
            );
          }
          keyPairIndex[key.pairId] = key;
        case AtSymmetricKey():
          if (symmetricKeyIndex.containsKey(key.id)) {
            throw ArgumentError.value(
              key.id,
              'id',
              'Duplicate symmetric key',
            );
          }
          symmetricKeyIndex[key.id] = key;
      }
    }

    return _AtKeysIndex(
      keyPairs: keyPairIndex,
      symmetricKeys: symmetricKeyIndex,
    );
  }
}

bool _iterableEquals<T>(Iterable<T> left, Iterable<T> right) {
  final leftIterator = left.iterator;
  final rightIterator = right.iterator;

  while (true) {
    final leftHasNext = leftIterator.moveNext();
    final rightHasNext = rightIterator.moveNext();

    if (leftHasNext != rightHasNext) {
      return false;
    }
    if (!leftHasNext) {
      return true;
    }
    if (leftIterator.current != rightIterator.current) {
      return false;
    }
  }
}
