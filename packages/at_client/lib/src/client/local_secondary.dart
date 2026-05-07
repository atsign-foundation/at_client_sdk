// HiveKeystore.getExpiryKeysCache() is @visibleForTesting in the
// at_persistence package, but is the canonical access point we read
// here to surface nextExpiryAt / nextAvailableAt without duplicating
// the cache in this layer. The parallel persistence project will
// promote it to a public method on SecondaryKeyStore — at that point
// this file-level ignore goes away.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
// Private path: HiveKeystore isn't exported from the package barrel, but
// this file's `deleteExpiredKeys` needs the concrete class for the
// `is HiveKeystore` guard and the `getExpiredKeys()` call. The parallel
// persistence project will eventually expose these via a public method on
// SecondaryKeyStore at which point this private import goes away.
// ignore: implementation_imports
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// Contains methods to execute verb on local secondary storage using [executeVerb]
/// Set [AtClientPreference.isLocalStoreRequired] to true and other preferences that your app needs.
/// Delete and Update commands will be synced to the server
class LocalSecondary implements Secondary {
  final AtClient _atClient;

  late final AtSignLogger _logger;

  /// Local keystore used to store data for the current atSign.
  SecondaryKeyStore? keyStore;

  /// Sink for keystore-mutation events. Wired by [AtClientImpl] at
  /// construction to its [AtClientImpl.emitDataEvent]; left null by
  /// callers that don't need event propagation (most unit-test
  /// fixtures). Emits are silently dropped when null.
  final void Function(DataEvent)? _onEvent;

  void _emit(DataEvent e) => _onEvent?.call(e);

  /// Tracks the `availableAt` timestamp [_onAvailableFire] last
  /// emitted `DataUpdated` for, per key. Lets the available-timer
  /// sweep skip keys we've already fired for (the underlying record's
  /// `availableAt` is now in the past but unchanged). A subsequent
  /// `_update` that rewrites the record with a new future
  /// `availableAt` causes the cache's value to differ from this map's
  /// — the sweep then refires.
  ///
  /// In-memory only — does NOT survive process restart. Restart-side
  /// re-fire is acceptable: subscribers come up fresh and a single
  /// `DataUpdated` per restart is the consistent answer.
  final Map<String, DateTime> _firedAvailableAt = {};

  LocalSecondary(
    this._atClient, {
    this.keyStore,
    void Function(DataEvent)? onEvent,
  }) : _onEvent = onEvent {
    _logger = AtSignLogger('LocalSecondary (${_atClient.getCurrentAtSign()})');
    keyStore ??= SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(_atClient.getCurrentAtSign())!
        .getSecondaryKeyStore();
  }

  // temporarily cache enrollmentDetails until we store in local secondary
  @visibleForTesting
  Enrollment? enrollment;

  /// Executes a verb builder on the local secondary.
  /// If [sync] is true then a sync request will be queued — except for
  /// writes to `local:` keys, which are never sync candidates (they're
  /// filtered out of the sync regex by definition). Triggering a sync
  /// request for a local-key write is pure overhead pre-fix; post the
  /// `_clearQueue` fix in `SyncServiceImpl` (which retains requests
  /// arriving during a round) it actively chains an empty follow-up
  /// round, with knock-on effects for tests that rely on a single sync
  /// round per `syncData()` call (cf. the
  /// `_lastReceivedServerCommitId` cursor put inside `_syncFromServer`,
  /// which fires from inside the very round that's wrapping it).
  @override
  Future<String?> executeVerb(VerbBuilder builder, {bool? sync}) async {
    String? verbResult;

    try {
      if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
        //1. if local and server are out of sync, first sync before updating current key-value
        //2 . update/delete to local store
        if (builder is UpdateVerbBuilder) {
          verbResult = await _update(builder);
        } else if (builder is DeleteVerbBuilder) {
          verbResult = await _delete(builder);
        }
        // 3. sync latest update/delete if strategy is immediate AND
        //    the key is actually a sync candidate (not a `local:` key).
        final isLocalKey =
            (builder is UpdateVerbBuilder && builder.atKey.isLocal) ||
                (builder is DeleteVerbBuilder && builder.atKey.isLocal);
        if (sync != null && sync && !isLocalKey) {
          _logger.finer('calling sync immediate from local secondary');
          // Use the write-trigger entry point so [_clearQueue] knows
          // not to discard this request just because it landed during
          // an in-flight round — the write itself may not be in that
          // round's `unCommittedEntries` snapshot, and we need a
          // follow-up round to flush it.
          final syncSvc = _atClient.syncService;
          if (syncSvc is SyncServiceImpl) {
            syncSvc.syncFromWrite();
          } else {
            // Third-party implementations of SyncService still get the
            // legacy `sync()` trigger — we can't tag the request from
            // here, so they fall back to the pre-fix behaviour.
            syncSvc.sync();
          }
        }
      } else if (builder is LLookupVerbBuilder) {
        verbResult = await _llookup(builder);
      } else if (builder is ScanVerbBuilder) {
        verbResult = await _scan(builder);
      }
    } on AtLookUpException catch (e) {
      // Catches AtLookupException and
      // converts to AtClientException. rethrows any other exception.
      throw (AtClientException(e.errorCode, e.errorMessage));
    }
    return verbResult;
  }

  Future<String> _update(UpdateVerbBuilder builder) async {
    try {
      dynamic updateResult;
      var updateKey = builder.buildKey();
      if (!await isEnrollmentAuthorizedForOperation(updateKey, builder)) {
        throw UnAuthorizedException(
            'Cannot perform update on $updateKey due to insufficient privilege');
      }

      // Probe previous metadata BEFORE the write so we can compute
      // visibility transitions for event emission. May throw
      // KeyNotFoundException for first-write — treat as "no previous".
      // The cross-tier safety property here: this LocalSecondary is the
      // only in-process emit point for keystore-mutation events. The
      // notification path from the remote atServer comes through a
      // separate channel (NotificationServiceImpl) and already carries
      // availableAt in the envelope.
      AtMetaData? prevMeta;
      try {
        prevMeta = await keyStore!.getMeta(updateKey);
      } on Exception {
        prevMeta = null;
      }
      final now = DateTime.timestamp();
      final bool? prevVisible =
          prevMeta == null ? null : _visibleAt(prevMeta.availableAt, now);

      late AtMetaData emittedMetadata;
      switch (builder.operation) {
        case AtConstants.updateMeta:
          var atMetadata = AtMetaData.fromCommonsMetadata(
            builder.atKey.metadata,
            _atClient.getCurrentAtSign()!,
          );
          updateResult = await keyStore!.putMeta(updateKey, atMetadata);
          emittedMetadata = atMetadata;
          break;
        default:
          var atData = AtData();
          atData.data = builder.value;
          var atMetadata = AtMetaData.fromCommonsMetadata(
            builder.atKey.metadata,
            _atClient.getCurrentAtSign()!,
          );
          updateResult = await keyStore!.putAll(updateKey, atData, atMetadata);
          emittedMetadata = atMetadata;
          break;
      }

      final newVisible = _visibleAt(emittedMetadata.availableAt, now);
      if (newVisible) {
        _emit(DataUpdated(builder.atKey, metadata: emittedMetadata));
        // If the record carries an availableAt (necessarily in the
        // past since newVisible is true), record it so the
        // available-timer sweep won't re-emit DataUpdated for the
        // same crossing.
        final avail = emittedMetadata.availableAt;
        if (avail != null) {
          _firedAvailableAt[updateKey] = avail;
        } else {
          _firedAvailableAt.remove(updateKey);
        }
      } else if (prevVisible == true) {
        // visible → not-yet: record dropped out of listeners' view.
        // Clear any prior fire record — when the new future
        // availableAt crosses, the timer should fire DataUpdated.
        _emit(DataDeleted(builder.atKey));
        _firedAvailableAt.remove(updateKey);
      } else {
        // Silent (fresh future-write or future→future re-write).
        // The new availableAt differs from any previously fired
        // value, so let the sweep evaluate normally — clear any
        // stale fire record.
        _firedAvailableAt.remove(updateKey);
      }

      return 'data:$updateResult';
    } on DataStoreException catch (e) {
      _logger.severe('exception in local update:${e.toString()}');
      rethrow;
    }
  }

  Future<String> _llookup(LLookupVerbBuilder builder) async {
    var llookupKey = '';
    try {
      llookupKey = builder.buildKey();
      if (!await isEnrollmentAuthorizedForOperation(llookupKey, builder)) {
        throw UnAuthorizedException(
            'Cannot perform llookup on $llookupKey due to insufficient privilege');
      }
      var llookupMeta = await keyStore!.getMeta(llookupKey);
      var isActive = _isActiveKey(llookupMeta);
      String? result;
      if (isActive) {
        var llookupResult = await keyStore!.get(llookupKey);
        result = _prepareResponseData(builder.operation, llookupResult);
      }
      return 'data:$result';
    } on DataStoreException catch (e) {
      _logger.severe('exception in llookup:${e.toString()}');
      rethrow;
    } on KeyNotFoundException catch (e) {
      e.stack(AtChainedException(
          Intent.fetchData, ExceptionScenario.keyNotFound, e.message));
      rethrow;
    }
  }

  Future<String> _delete(DeleteVerbBuilder builder) async {
    var deleteKey = builder.buildKey();
    if (!await isEnrollmentAuthorizedForOperation(deleteKey, builder)) {
      throw UnAuthorizedException(
          'Cannot perform delete on $deleteKey due to insufficient privilege');
    }
    try {
      var deleteResult = await keyStore!.remove(deleteKey);
      _emit(DataDeleted(builder.atKey));
      _firedAvailableAt.remove(deleteKey);
      return 'data:$deleteResult';
    } on DataStoreException catch (e) {
      _logger.severe('exception in delete:${e.toString()}');
      rethrow;
    }
  }

  /// Deletes every key currently flagged expired by the underlying
  /// [HiveKeystore]'s in-memory cache. Each deletion goes through
  /// [_delete], which fires a [DataDeleted] on [AtClient.dataEvents]
  /// — so subscribers see expirations the same way they see any other
  /// delete. Returns the number of keys removed.
  ///
  /// Callers arming a timer via [AtClient.dataEvents] should suppress
  /// re-arms while a sweep is in flight (the events fired during this
  /// method would otherwise cause N redundant re-arms).
  /// [AtClientImpl._onExpiryFire] does this via a `_sweepInFlight`
  /// flag.
  ///
  /// Returns 0 (no-op) when the underlying keystore is not a
  /// [HiveKeystore]; non-Hive keystores are responsible for their own
  /// expiry mechanism if any.
  Future<int> deleteExpiredKeys() async {
    final ks = keyStore;
    if (ks is! HiveKeystore) {
      _logger.shout('Underlying keyStore is not HiveKeystore');
      return 0;
    }
    final expired = await ks.getExpiredKeys();
    if (expired.isEmpty) return 0;
    var deleted = 0;
    for (final keyString in expired) {
      try {
        final atKey = AtKey.fromString(keyString);
        final builder = DeleteVerbBuilder()..atKey = atKey;
        _logger.finer('Deleting expired key $atKey');
        await _delete(builder);
        deleted++;
      } on Exception catch (e) {
        _logger.warning('expiry sweep failed for $keyString: $e');
      }
    }
    return deleted;
  }

  Future<String?> _scan(ScanVerbBuilder builder) async {
    try {
      // Call to remote secondary sever and performs an outbound scan to retrieve values from sharedBy secondary
      // shared with current atSign
      if (builder.sharedBy != null) {
        var command = builder.buildCommand();
        return _atClient
            .getRemoteSecondary()!
            .executeCommand(command, auth: true);
      }
      List<String?> keys;
      keys = keyStore!.getKeys(regex: builder.regex) as List<String?>;
      // Gets keys shared to sharedWith atSign.
      if (builder.sharedWith != null) {
        keys.retainWhere(
            (element) => element!.startsWith(builder.sharedWith!) == true);
      }
      keys.removeWhere((key) => _shouldHideKeys(key!, builder.showHiddenKeys));
      final keysToRemove = <String>[];
      await Future.forEach(keys, (key) async {
        if (!(await isEnrollmentAuthorizedForOperation(
            key.toString(), builder))) {
          keysToRemove.add(key.toString());
        }
      });
      keys.removeWhere((key) => keysToRemove.contains(key));
      var keyString = keys.toString();
      // Apply regex on keyString to remove unnecessary characters and spaces
      keyString = keyString.replaceFirst(RegExp(r'^\['), '');
      keyString = keyString.replaceFirst(RegExp(r'\]$'), '');
      keyString = keyString.replaceAll(', ', ',');
      var keysArray = keyString.isNotEmpty ? (keyString.split(',')) : [];
      return json.encode(keysArray);
    } on DataStoreException catch (e) {
      _logger.severe('exception in scan:${e.toString()}');
      rethrow;
    }
  }

  bool _shouldHideKeys(String key, bool showHiddenKeys) {
    // If showHidden is set to true, display hidden public keys.
    // So returning false
    if ((key.toString().startsWith('public:__') || key.startsWith('_')) &&
        showHiddenKeys) {
      return false;
    }
    // Do not display keys that starts with 'private:' or 'privatekey:' or public:_
    return key.toString().startsWith('private:') ||
        key.toString().startsWith('privatekey:') ||
        key.toString().startsWith('public:_') ||
        key.startsWith('_');
  }

  /// Verifies if the key is active, If key is active, return true; else false.
  bool _isActiveKey(AtMetaData? atMetaData) {
    // The legacy keys will not have metadata.
    // Returning true if metadata is null
    if (atMetaData == null) return true;
    var ttb = atMetaData.availableAt;
    var ttl = atMetaData.expiresAt;
    if (ttb == null && ttl == null) return true;
    var now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (ttb != null) {
      var ttbMs = ttb.toUtc().millisecondsSinceEpoch;
      if (ttbMs > now) return false;
    }
    if (ttl != null) {
      var ttlMs = ttl.toUtc().millisecondsSinceEpoch;
      if (ttlMs < now) return false;
    }
    //If TTB or TTL populated but not met, return true.
    return true;
  }

  /// Visibility predicate for event-emission decisions: a record
  /// with this `availableAt` is considered visible at [at]. Mirrors
  /// the `availableAt` arm of [_isActiveKey] but excludes the
  /// `expiresAt` arm — visibility for emit purposes is independent
  /// of expiry (an already-expired record's `_update` should still
  /// emit normally; the expiry timer fires `DataDeleted` on its own
  /// schedule).
  bool _visibleAt(DateTime? availableAt, DateTime at) {
    if (availableAt == null) return true;
    return availableAt.toUtc().millisecondsSinceEpoch <=
        at.toUtc().millisecondsSinceEpoch;
  }

  /// Earliest pending `expiresAt` across keys with TTL, or `null`
  /// if none. Reads from the underlying [HiveKeystore]'s
  /// `_expiryKeysCache` — which is rebuilt on keystore open and
  /// maintained on every put. O(n) over the cache size; n is the
  /// count of keys with TTL or TTB set, NOT the total record count.
  ///
  /// Returns `null` when the keystore isn't a [HiveKeystore]
  /// (non-Hive backends are responsible for their own timer
  /// surfaces).
  DateTime? nextExpiryAt() {
    final ks = keyStore;
    if (ks is! HiveKeystore) return null;
    DateTime? earliest;
    for (final entry in ks.getExpiryKeysCache().values) {
      final exp = entry['expiresAt'];
      if (exp == null) continue;
      if (earliest == null || exp.isBefore(earliest)) earliest = exp;
    }
    return earliest;
  }

  /// Earliest pending `availableAt` across keys with TTB, excluding
  /// keys whose current `availableAt` matches a previously fired
  /// timestamp ([_firedAvailableAt]). Returns `null` if none.
  DateTime? nextAvailableAt() {
    final ks = keyStore;
    if (ks is! HiveKeystore) return null;
    DateTime? earliest;
    for (final entry in ks.getExpiryKeysCache().entries) {
      final avail = entry.value['availableAt'];
      if (avail == null) continue;
      final fired = _firedAvailableAt[entry.key];
      if (fired != null && fired.isAtSameMomentAs(avail)) continue;
      if (earliest == null || avail.isBefore(earliest)) earliest = avail;
    }
    return earliest;
  }

  /// Yields every key with `availableAt <= cutoff` whose current
  /// `availableAt` doesn't match a previously fired timestamp. Used
  /// by [AtClientImpl._onAvailableFire] to drive the visibility-
  /// onset sweep.
  ///
  /// Iteration order is unspecified — the underlying cache is a
  /// `HashMap`. Snapshots before yielding so concurrent writes
  /// during the sweep don't perturb the walk.
  Iterable<String> keysWithAvailableAtAtOrBefore(DateTime cutoff) sync* {
    final ks = keyStore;
    if (ks is! HiveKeystore) return;
    final cutoffMs = cutoff.toUtc().millisecondsSinceEpoch;
    final snapshot = List<MapEntry<String, Map<String, DateTime?>>>.from(
        ks.getExpiryKeysCache().entries);
    for (final entry in snapshot) {
      final avail = entry.value['availableAt'];
      if (avail == null) continue;
      if (avail.toUtc().millisecondsSinceEpoch > cutoffMs) continue;
      final fired = _firedAvailableAt[entry.key];
      if (fired != null && fired.isAtSameMomentAs(avail)) continue;
      yield entry.key;
    }
  }

  /// Records that the available-timer sweep just emitted
  /// `DataUpdated` for [key], so subsequent sweeps don't re-fire
  /// for the same `availableAt` crossing. A subsequent `_update`
  /// that rewrites the record with a new future `availableAt`
  /// (different from the recorded one) re-enables firing.
  void dropAvailabilityCacheEntry(String key) {
    final ks = keyStore;
    if (ks is! HiveKeystore) return;
    final entry = ks.getExpiryKeysCache()[key];
    final avail = entry?['availableAt'];
    if (avail != null) {
      _firedAvailableAt[key] = avail;
    }
  }

  String? _prepareResponseData(String? operation, AtData? atData) {
    String? result;
    if (atData == null) {
      return result;
    }
    switch (operation) {
      case 'meta':
        result = json.encode(atData.metaData!.toJson());
        break;
      case 'all':
        result = json.encode(atData.toJson());
        break;
      default:
        result = atData.data;
        break;
    }
    return result;
  }

  @Deprecated("Use getPkamPrivateKey")
  Future<String?> getPrivateKey() => getPkamPrivateKey();

  AtChopsKeys? get atChopsKeys => _atClient.atChops?.atChopsKeys;

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getPkamPrivateKey() async {
    String? v = atChopsKeys?.atPkamKeyPair?.atPrivateKey.privateKey;
    v ??= (await keyStore!.get(AtConstants.atPkamPrivateKey))?.data;
    return v;
  }

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getEncryptionPrivateKey() async {
    String? v = atChopsKeys?.atEncryptionKeyPair?.atPrivateKey.privateKey;
    v ??= (await keyStore!.get(AtConstants.atEncryptionPrivateKey))?.data;
    return v;
  }

  @Deprecated("Use getPkamPublicKey")
  Future<String?> getPublicKey() => getPkamPublicKey();

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getPkamPublicKey() async {
    String? v = atChopsKeys?.atPkamKeyPair?.atPublicKey.publicKey;
    v ??= (await keyStore!.get(AtConstants.atPkamPublicKey))?.data;
    return v;
  }

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getEncryptionPublicKey(String atSign) async {
    atSign = AtUtils.fixAtSign(atSign);
    String? v = atChopsKeys?.atEncryptionKeyPair?.atPublicKey.publicKey;
    v ??= (await keyStore!.get('${AtConstants.atEncryptionPublicKey}$atSign'))
        ?.data;

    return v;
  }

  /// get it from atChops if we have it, otherwise try the keystore
  Future<String?> getEncryptionSelfKey() async {
    String? v = atChopsKeys?.selfEncryptionKey?.key;
    v ??= (await keyStore!.get(AtConstants.atEncryptionSelfKey))?.data;
    return v;
  }

  ///Returns `true` on successfully storing the values into local secondary.
  Future<bool> putValue(String key, String value) async {
    dynamic isStored;
    var atData = AtData()..data = value;
    isStored = await keyStore!.put(key, atData);
    return isStored != null ? true : false;
  }

  Future<bool> isEnrollmentAuthorizedForOperation(
      String key, VerbBuilder verbBuilder) async {
    // Do whatever you want with "local" keys
    if (key.startsWith('local:')) {
      return true;
    }
    // if there is no enrollment, return true
    enrollment ??= await _getEnrollmentDetails();
    if (_atClient.enrollmentId == null ||
        enrollment == null ||
        _shouldSkipKeyFromEnrollmentAuthorization(key)) {
      _logger.finest('Skipping enrollment authorization check for key: $key');
      return true;
    }
    final enrollNamespaces = enrollment!.namespace;
    var keyNamespace = AtKey.fromString(key).namespace;
    _logger.finest(
        'Checking for enrollment authorization for key: $key with enrollmentId : ${_atClient.enrollmentId} for namespace: $keyNamespace');
    // * denotes access to all namespaces.
    final access = enrollNamespaces!.containsKey('*')
        ? enrollNamespaces['*']
        : enrollNamespaces[keyNamespace];

    if (access == null) {
      _logger.finer(
          'Access permissions not found for the enrollment id: ${_atClient.enrollmentId}. Not authorized for the operation');
      return false;
    }
    if (keyNamespace == null && enrollNamespaces.containsKey('*')) {
      _logger.finer(
          'Access permissions for the the enrollment id: ${_atClient.enrollmentId} : $access for namespace: $keyNamespace');
      if (_isReadAllowed(verbBuilder, access) ||
          _isWriteAllowed(verbBuilder, access)) {
        _logger.finest(
            'Enrollment id: ${_atClient.enrollmentId} : $access for namespace: $keyNamespace is authorized to perform operation');
        return true;
      }
      _logger.finest(
          'Enrollment id: ${_atClient.enrollmentId} : $access for namespace: $keyNamespace is not authorized to perform operation');
      return false;
    }
    return _isReadAllowed(verbBuilder, access) ||
        _isWriteAllowed(verbBuilder, access);
  }

  Future<Enrollment?> _getEnrollmentDetails() async {
    if (_atClient.enrollmentId == null) {
      return null;
    }

    // Fetch enrollment information from local secondary
    AtData? enrollmentInfoFromLocalSecondary;
    try {
      enrollmentInfoFromLocalSecondary = await keyStore?.get(
          'local:${_atClient.enrollmentId}${_atClient.getCurrentAtSign()}');
    } on Exception {
      _logger.finer(
          'Enrollment information for id: ${_atClient.enrollmentId} not found in local secondary. Fetching from server');
    }

    // If enrollmentInfo is not found in local secondary, fetch the info from the remote secondary server and cache it in local
    // secondary.
    String? enrollmentInfoFromServer;
    if (enrollmentInfoFromLocalSecondary == null) {
      try {
        enrollmentInfoFromServer = await _atClient
            .getRemoteSecondary()
            ?.executeCommand(
                'enroll:fetch:{"enrollmentId":"${_atClient.enrollmentId}"}\n',
                auth: true);
      } on AtException catch (e) {
        _logger.finer(
            'Failed to fetch enrollment information for id: ${_atClient.enrollmentId} from server caused by ${e.toString()}');
      } on AtLookUpException catch (e) {
        _logger.finer(
            'Failed to fetch enrollment information for id: ${_atClient.enrollmentId} from server caused by ${e.toString()}');
      }
      enrollmentInfoFromServer =
          enrollmentInfoFromServer?.replaceFirst(RegExp('^data:'), '');
      Map enrollmentDetailsMap = jsonDecode(enrollmentInfoFromServer!);
      _logger.info('Enrollment Details Map : $enrollmentDetailsMap');
      enrollment = Enrollment()
        ..appName = enrollmentDetailsMap['appName']
        ..deviceName = enrollmentDetailsMap['deviceName']
        ..namespace = enrollmentDetailsMap['namespace']
        ..encryptedAPKAMSymmetricKey =
            enrollmentDetailsMap['encryptedAPKAMSymmetricKey'];

      AtData atData = AtData()..data = jsonEncode(enrollment);
      // The enrollment data is fetch from server, Set skipCommit to true to prevent
      // the key sync back to server
      await keyStore?.put(
          '${_atClient.enrollmentId}.new.enrollments.__manage${_atClient.getCurrentAtSign()}',
          atData,
          skipCommit: true);
    } else {
      enrollment = Enrollment.fromJSON(
          jsonDecode(enrollmentInfoFromLocalSecondary.data!));
    }

    if (enrollment == null) {
      throw AtKeyNotFoundException(
          'Enrollment key for enrollmentId: ${_atClient.enrollmentId} not found in server');
    }
    return enrollment!;
  }

  bool _isReadAllowed(VerbBuilder verbBuilder, String access) {
    return (verbBuilder is LLookupVerbBuilder ||
            verbBuilder is LookupVerbBuilder ||
            verbBuilder is ScanVerbBuilder) &&
        (access == 'r' || access == 'rw');
  }

  bool _isWriteAllowed(VerbBuilder verbBuilder, String access) {
    return (verbBuilder is UpdateVerbBuilder ||
            verbBuilder is DeleteVerbBuilder ||
            verbBuilder is NotifyVerbBuilder ||
            verbBuilder is NotifyAllVerbBuilder ||
            verbBuilder is NotifyRemoveVerbBuilder) &&
        access == 'rw';
  }

  /// The enrollment authorization check does not include the following KeyTypes.
  /// Therefore, return true to skip the authorization check.
  /// This applies to Reserved keys, Cached shared keys, Cached public keys, and local keys
  bool _shouldSkipKeyFromEnrollmentAuthorization(String? atKey) {
    if (atKey == null) {
      return false;
    }
    KeyType keyType = AtKey.getKeyType(atKey);
    return (keyType == KeyType.reservedKey ||
        keyType == KeyType.cachedSharedKey ||
        keyType == KeyType.cachedPublicKey ||
        keyType == KeyType.localKey);
  }
}
