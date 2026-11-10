import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

/// Device-local records (keys starting `local:`) for a remote-only client.
abstract interface class LocalRecordStore {
  Future<AtData?> get(String key);
  Future<void> put(String key, AtData value);
  Future<void> remove(String key);
  Future<List<String>> keys();

  /// Atomically replaces the value at [key] with `apply(current)`; current is
  /// null when absent; a null result removes the key. Returns the new value.
  Future<AtData?> update(String key, AtData? Function(AtData? current) apply);
}

/// Implemented by keystores that expose an atomic read-modify-write of a local record.
abstract interface class LocalRecordUpdater {
  Future<AtData?> updateLocal(
      String key, AtData? Function(AtData? current) apply);
}

class InMemoryLocalRecordStore implements LocalRecordStore {
  final Map<String, AtData> _records = {};

  @override
  Future<AtData?> get(String key) async => _records[key];

  @override
  Future<void> put(String key, AtData value) async {
    _records[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _records.remove(key);
  }

  @override
  Future<List<String>> keys() async => _records.keys.toList();

  @override
  Future<AtData?> update(
      String key, AtData? Function(AtData? current) apply) async {
    final next = apply(_records[key]);
    if (next == null) {
      _records.remove(key);
    } else {
      _records[key] = next;
    }
    return next;
  }
}
