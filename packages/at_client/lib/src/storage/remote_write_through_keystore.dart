import 'dart:convert';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

class RemoteWriteThroughKeyStore
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  final RemoteSecondary remoteSecondary;
  final int maxAttempts;

  RemoteWriteThroughKeyStore(this.remoteSecondary, {this.maxAttempts = 3});

  Future<T> _withRetry<T>(Future<T> Function() attempt) async {
    Object? lastError;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        return await attempt();
      } on KeyNotFoundException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError!;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<int?> put(String key, AtData value,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    await _withRetry(() => remoteSecondary
        .executeCommand('update:$key ${value.data}', auth: true));
    return null;
  }

  @override
  Future<int?> putMeta(String key, AtMetaData? metadata,
      {bool skipCommit = false,
      AtAssertedTimestamps? assertedTimestamps}) async {
    final fragment = metadata?.toCommonsMetadata().toAtProtocolFragment() ?? '';
    await _withRetry(() => remoteSecondary
        .executeCommand('update:meta:$key$fragment', auth: true));
    return null;
  }

  @override
  Future<int?> putAll(String key, AtData value, AtMetaData? metadata) async {
    final fragment = metadata?.toCommonsMetadata().toAtProtocolFragment() ?? '';
    await _withRetry(() => remoteSecondary
        .executeCommand('update$fragment:$key ${value.data}', auth: true));
    return null;
  }

  @override
  Future<int?> remove(String key,
      {bool skipCommit = false, DateTime? deletedAt}) async {
    await _withRetry(
        () => remoteSecondary.executeCommand('delete:$key', auth: true));
    return null;
  }

  @override
  Future<AtData?> get(String key) async {
    final builder = LLookupVerbBuilder()
      ..atKey = AtKey.fromString(key)
      ..operation = 'all';
    final response =
        await _withRetry(() => remoteSecondary.executeVerb(builder));
    final cleanResponse = response.replaceFirst(RegExp('^data:'), '');
    final decoded = jsonDecode(cleanResponse) as Map<String, dynamic>;
    return AtData().fromJson(decoded);
  }

  @override
  Future<AtMetaData?> getMeta(String key) async {
    final data = await get(key);
    return data?.metaData;
  }

  @override
  Future<Stream<String>> getKeys({String? regex}) async {
    final builder = ScanVerbBuilder()
      ..regex = regex
      ..auth = true;
    final response =
        await _withRetry(() => remoteSecondary.executeVerb(builder));
    final cleanResponse = response.replaceFirst(RegExp('^data:'), '');
    final list = jsonDecode(cleanResponse) as List<dynamic>;
    return Stream.fromIterable(list.cast<String>());
  }

  // Dead but must answer
  @override
  Future<DateTime?> nextExpiresAt() async => null;

  @override
  Future<DateTime?> nextAvailableAt({DateTime? asOf}) async => null;

  // Safe defaults
  @override
  Stream<KeyStoreChange> get changes => const Stream.empty();

  @override
  List<Future<void> Function(String, {required bool skipCommit})>
      get preRemoveHooks => const [];

  @override
  List<Future<void> Function(String, {required bool skipCommit})>
      get postRemoveHooks => const [];

  @override
  bool get supportsSnapshots => false;

  @override
  bool get supportsPathQueries => false;

  @override
  AtCommitLog? get commitLog => null;

  @override
  set commitLog(AtCommitLog? value) {}

  // Unsupported
  @override
  Future<int?> create(String key, AtData value,
      {bool skipCommit = false, AtAssertedTimestamps? assertedTimestamps}) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support create');
  }

  @override
  Future<Stream<String>> scanKeys(KeyPattern pattern,
      {bool includeExpired = false,
      OrderByKey? orderBy,
      int? limit,
      int? skip}) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support scanKeys');
  }

  @override
  Stream<KeyEntry<String, AtData, AtMetaData?>> queryByPath(
      {required KeyPattern keyPattern,
      required Predicate predicate,
      OrderByKey? orderBy,
      int? limit,
      int? skip}) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support queryByPath');
  }

  @override
  Future<AtKeyValueStoreSnapshot<String, AtData, AtMetaData?>> snapshot() {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support snapshot');
  }

  @override
  Stream<Object> compact(bool dryRun) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support compact');
  }

  @override
  Future<void> restore(String key, AtData value) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support restore');
  }

  @override
  Future<Stream<String>> peekNewlyAvailable(
      {required DateTime since, DateTime? asOf, int? limit}) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support peekNewlyAvailable');
  }

  @override
  Future<Stream<String>> getExpiredKeys() {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support getExpiredKeys');
  }

  @override
  Future<bool> deleteExpiredKeys() {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support deleteExpiredKeys');
  }

  @override
  Future<Stream<String>> peekExpired({DateTime? asOf, int? limit}) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support peekExpired');
  }

  @override
  Future<bool> exists(String key) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support exists');
  }

  @override
  Future<Map<String, AtData>> getMany(List<String> keys) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support getMany');
  }

  @override
  Future<int> removeMany(List<String> keys, {bool skipCommit = false}) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support removeMany');
  }

  @override
  Future<R> transaction<R>(
      Future<R> Function(KeyStoreTxn<String, AtData, dynamic> txn) body) {
    throw UnsupportedError(
        'RemoteWriteThroughKeyStore does not support transaction');
  }

  @override
  Future<KeyStoreStats> stats() {
    throw UnsupportedError('RemoteWriteThroughKeyStore does not support stats');
  }
}
