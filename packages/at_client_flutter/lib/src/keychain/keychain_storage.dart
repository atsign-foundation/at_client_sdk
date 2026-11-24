import 'dart:convert';
import 'dart:io' show Platform;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysFileOverwriteException,
        AtKeysFormatException,
        AtKeysSourceAbsentException,
        AtKeysValidationException;
import 'package:at_client/at_client.dart' show Passcode;
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:biometric_storage/biometric_storage.dart'
    show
        BiometricStorageFile,
        BiometricStorage,
        StorageFileInitOptions,
        Win32BiometricStoragePlugin;
import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:synchronized/synchronized.dart';

import 'keychain_atsign.dart';
import 'keychain_data.dart';

part 'keychain_store.dart';

const int _kWindowSegmentDataLength =
    2560; //CREDENTIALA structure (wincred.h) - CRED_MAX_CREDENTIAL_BLOB_SIZE (5*512) bytes.

/// The most segments a Windows keychain entry is read or cleared in, far more
/// than any entry needs.
///
/// A header that records more is refused, and no search for segments to
/// delete looks at one at or past this index.
const int _kMaxWindowSegments = 2560;

/// Service to manage keychain CRUD operations for Atsigns and SPPs
class KeychainStorage {
  static final _logger = AtSignLogger('KeychainStorage');

  // NOTE: one for every instance, which all read and write the same keychain
  // entry, and reentrant, so a caller holding it through [writing] can call
  // the writers here, which take it too.
  static final _writes = Lock(reentrant: true);
  static bool isWindows = Platform.isWindows;
  @visibleForTesting
  late BiometricStorage biometricStorage;

  /// Create a [KeychainStorage] instance
  ///
  ///   [biometricStorage] - Optional [BiometricStorage] for mocking
  KeychainStorage({BiometricStorage? biometricStorage}) {
    if (isWindows) {
      // ignore: undefined_method
      Win32BiometricStoragePlugin.registerWith();
    }
    this.biometricStorage = biometricStorage ?? BiometricStorage();
  }

  /// Read all stored Atsign keys data from the keychain
  ///
  /// Returns [AtKeysData] containing all persisted [AtKeys] entries, or `null`
  /// if no key data has been stored yet. A stored entry that is not a JSON
  /// object throws [AtKeysFormatException], and a store the platform refuses
  /// to read throws the platform's error.
  Future<AtKeysData?> readAtKeysData() async {
    final data = await _readAtKeysDataRaw();
    if (data != null) {
      return _decodeAtKeysData(data);
    }
    return null;
  }

  /// [text], a stored atKeys entry, as [AtKeysData].
  static AtKeysData _decodeAtKeysData(String text) =>
      AtKeysData.fromJson(_decodeObject(text, 'the keychain atKeys entry'));

  /// [text], a stored [what], as the JSON object it must be.
  ///
  /// Text that is not a JSON object throws [AtKeysFormatException], which
  /// holds none of it.
  static Map<String, dynamic> _decodeObject(String text, String what) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw AtKeysFormatException.notJson(what, e);
    }
    if (json is! Map<String, dynamic>) {
      throw AtKeysFormatException.notAnObject(what);
    }
    return json;
  }

  /// The segment count a Windows store's header [text] records: a legacy
  /// header, one not starting with `{`, is the count, and any other holds it
  /// as a JSON object's `segmentCount`.
  ///
  /// A count that is not a whole number from zero to [_kMaxWindowSegments],
  /// or a header starting with `{` that is not a JSON object, throws
  /// [AtKeysFormatException].
  static int _segmentCountIn(String text) {
    const what = 'the keychain atKeys entry header';
    const requirement = 'a whole number from 0 to $_kMaxWindowSegments';
    if (!text.startsWith('{')) {
      final legacy = int.tryParse(text);
      if (legacy == null || legacy < 0 || legacy > _kMaxWindowSegments) {
        throw AtKeysFormatException.badField(
          what,
          'segmentCount',
          requirement,
          kind: 'a legacy segment header',
        );
      }
      return legacy;
    }
    final count = _decodeObject(text, what)['segmentCount'];
    if (count is! int || count < 0 || count > _kMaxWindowSegments) {
      throw AtKeysFormatException.badField(what, 'segmentCount', requirement);
    }
    return count;
  }

  // Current behaviour:
  // 2.x.x (current):
  //   if `:` is absent and `_` is present, copy `_` to `:` but leave `_`.
  //
  // TODO(3.0.0): copy `_` to `:` then remove `_`.
  //
  // Since each app version runs in its own sandbox, there is no risk of an
  // older and newer version running simultaneously.
  Future<String?> _readAtKeysDataRaw() async {
    // 1. Read the current `:`-delimited store. If it exists, it is the
    // authoritative store and no migration is needed.
    final currentName = await AtKeysStore.getName();
    final data = await _read(keychainStoreName: currentName);
    if (data != null) {
      return data;
    }

    // See migration sequencing comment above.
    // 2.x.x: only copy `_` to `:`, leave `_` in place.

    // NOTE: a refused read of the legacy store is thrown, as one of the
    // current store is; it is not a keychain holding nothing.
    final keychainStorageImproperName = await _getImproperAtKeysStoreName();
    final improperDataString = await _read(
      keychainStoreName: keychainStorageImproperName,
    );
    if (improperDataString == null) {
      return null;
    }
    final legacyData = improperDataString;

    return _writes.synchronized(() async {
      // NOTE: read again under the lock. A writer may have copied the legacy
      // entry and changed it since the read above, and copying it again would
      // write over that change.
      final migrated = await _read(keychainStoreName: currentName);
      if (migrated != null) {
        return migrated;
      }
      _logger.info(
        'Migrating AtKeysData from legacy keychain store '
        '"$keychainStorageImproperName" to "$currentName"',
      );
      await _replaceEntry(
        name: currentName,
        previous: null,
        keychainData: _decodeAtKeysData(legacyData),
      );
      return legacyData;
    });
  }

  /// Runs [action] holding the lock every write of stored keys takes, so a
  /// read, change and write inside it cannot interleave with another write in
  /// this isolate.
  ///
  /// A write [action] starts and does not await runs alongside the rest of
  /// it, and throws [StateError] if it reaches a writer after [action] ends.
  Future<T> writing<T>(Future<T> Function() action) =>
      _writes.synchronized(action);

  /// Get the stored keys for a specific Atsign
  ///
  ///   [atSign] - Atsign whose key material should be retrieved
  ///
  /// Returns [AtKeys] for the requested Atsign, or `null` if it is not present
  ///
  /// Throws [AtKeyException] if no Atsign data exists in the keychain
  Future<AtKeys?> getAtsign(String atSign) async {
    final atKeysData = await readAtKeysData();
    if (atKeysData == null) {
      throw AtKeyException('No atsign found in keychain');
    }
    final index = _indexOf(atKeysData, atSign);
    return index == -1 ? null : atKeysData.keys[index];
  }

  /// Get all Atsigns currently stored in the keychain
  ///
  /// Returns a [List] of unique Atsign values: an Atsign stored under two
  /// spellings is listed once, in the spelling stored first.
  Future<List<String>> getAllAtsigns() async {
    final atKeysData = await readAtKeysData();
    if (atKeysData == null) {
      return [];
    }
    final listed = <String>{};
    final atSigns = <String>[];
    for (final keys in atKeysData.keys) {
      final atSign = _atSignOf(keys);
      if (atSign != null && listed.add(normalizedAtSign(atSign)!)) {
        atSigns.add(atSign);
      }
    }
    return atSigns;
  }

  /// Replace the stored [keys] for [atSign], or append them if this atSign has
  /// no entry yet.
  ///
  ///   [assureUpdate] - called with the entry about to be replaced, before
  ///   anything is written. Throwing from it abandons the write.
  ///
  ///   [requireExisting] - throw [AtKeysSourceAbsentException] and write
  ///   nothing when [atSign] has no entry, rather than adding one.
  ///
  /// The entry is replaced whole, and nothing checks that the key material it
  /// held survives unless [assureUpdate] does: `KeychainAtKeysIo.update`
  /// changes stored keys with that check.
  ///
  /// Keys naming an Atsign other than [atSign], in their typed `atsign` field
  /// or their metadata's `atsign` or legacy `name` entry, or naming two
  /// Atsigns, throw [AtKeysValidationException] before the keychain is read.
  /// Their metadata is stamped with the Atsign they name, or with [atSign]
  /// when they name none, only once those checks and [assureUpdate] have
  /// passed, so keys they refuse are left as they were.
  ///
  /// Writes in this isolate take turns; one from another isolate still wins
  /// over this, or loses to it, whole, since the keychain offers no
  /// compare-and-swap. On Windows, where the keychain item is written in
  /// parts, a write that fails partway is undone before it is thrown, unless
  /// undoing it fails too, which is logged.
  Future<void> updateAtKeysInKeychain({
    required String atSign,
    required AtKeys keys,
    void Function(AtKeys existing)? assureUpdate,
    bool requireExisting = false,
  }) => _writes.synchronized(() async {
    final named = atSignNamedBy(keys, filedAs: atSign);
    final previous = await _readAtKeysDataRaw();
    final atKeysData = previous == null
        ? AtKeysData(keys: [])
        : _decodeAtKeysData(previous);
    final index = _indexOf(atKeysData, atSign);
    if (index == -1 && requireExisting) {
      throw AtKeysSourceAbsentException(
        'The keychain no longer holds keys for $atSign, so nothing was '
        'written',
      );
    }
    if (index != -1) assureUpdate?.call(atKeysData.keys[index]);
    stampAtSign(keys, named);
    if (index == -1) {
      atKeysData.keys.add(keys);
    } else {
      atKeysData.keys[index] = keys;
    }
    await _replaceEntry(
      name: await AtKeysStore.getName(),
      previous: previous,
      keychainData: atKeysData,
    );
  });

  /// The atSign an entry belongs to, in whatever spelling it was stored: the
  /// typed `atsign` field, else the one [metadataAtSignOf] finds.
  String? _atSignOf(AtKeys keys) =>
      keys.atsign?.toString() ?? metadataAtSignOf(keys);

  int _indexOf(AtKeysData atKeysData, String atSign) {
    final wanted = normalizedAtSign(atSign);
    for (int i = 0; i < atKeysData.keys.length; i++) {
      if (normalizedAtSign(_atSignOf(atKeysData.keys[i])) == wanted) return i;
    }
    return -1;
  }

  /// Append a new [AtKeys] entry to the keychain
  ///
  ///   [keys] - [AtKeys] instance to persist
  ///
  /// The keys name their Atsign in their typed `atsign` field or their
  /// metadata's `atsign` or legacy `name` entry, decided before the keychain
  /// is read: keys naming two Atsigns throw [AtKeysValidationException], and
  /// keys naming none are appended as they are. Keys whose metadata does not
  /// name their Atsign have it stamped there only once the checks here have
  /// passed, so keys they refuse are left as they were.
  ///
  /// Keys for an Atsign the keychain already holds, its legacy-named store
  /// included, throw [AtKeysFileOverwriteException] and none of them is
  /// added: `KeychainAtKeysIo.write` adds an Atsign's keys and
  /// `KeychainAtKeysIo.update` changes them. Two appends for one Atsign in
  /// this isolate take turns, so one of them is refused.
  ///
  /// A failure to read or write the keychain, its legacy-named store
  /// included, is thrown, and a keychain item that is not a JSON object
  /// throws [AtKeysFormatException], with nothing written. On Windows, where
  /// the keychain item is written in parts, a write that fails partway is
  /// undone before it is thrown, unless undoing it fails too, which is
  /// logged.
  Future<void> appendAtKeysToKeychain({required AtKeys keys}) =>
      _writes.synchronized(() => _append(keys));

  Future<void> _append(AtKeys keys) async {
    final atSign = atSignNamedBy(keys);
    final existingData = await _readAtKeysDataRaw();
    final atKeysData = existingData == null
        ? AtKeysData(keys: [])
        : _decodeAtKeysData(existingData);
    if (atSign != null && _indexOf(atKeysData, atSign) != -1) {
      throw AtKeysFileOverwriteException(
        'The keychain already holds keys for '
        '${quotedForMessage(normalizedAtSign(atSign)!)}, so nothing was '
        'added. KeychainAtKeysIo.write adds an Atsign\'s keys and '
        'KeychainAtKeysIo.update changes them; a caller holding only this '
        'storage can build KeychainAtKeysIo(keychainStorage: storage).',
      );
    }
    stampAtSign(keys, atSign);
    atKeysData.keys.add(keys);
    await _replaceEntry(
      name: await AtKeysStore.getName(),
      previous: existingData,
      keychainData: atKeysData,
    );
  }

  /// Remove a stored Atsign entry from the keychain
  ///
  ///   [atSign] - Atsign whose persisted keys should be removed
  ///
  /// A failure to read or write the keychain, its legacy-named store
  /// included, is thrown, and a stored entry that is not a JSON object throws
  /// [AtKeysFormatException], with nothing written. On Windows, where the
  /// entry is written in parts, a write that fails partway is undone before
  /// it is thrown, unless undoing it fails too, which is logged. An empty
  /// keychain is left as it is. [deleteAllAtKeysData] is how a keychain whose
  /// entry does not parse is cleared, removing every Atsign stored there.
  Future<void> removeAtsignFromKeychain(String atSign) =>
      _writes.synchronized(() => _remove(atSign));

  Future<void> _remove(String atSign) async {
    final data = await _readAtKeysDataRaw();
    if (data == null) return;
    final atKeysData = _decodeAtKeysData(data);
    final wanted = normalizedAtSign(atSign);
    atKeysData.keys.removeWhere(
      (element) => normalizedAtSign(_atSignOf(element)) == wanted,
    );
    await _replaceEntry(
      name: await AtKeysStore.getName(),
      previous: data,
      keychainData: atKeysData,
    );
  }

  /// Delete all persisted Atsign key data from the keychain, including any
  /// data still held under the legacy pre-2.0.0 `_` delimited store name.
  /// TODO(3.0.0): remove the `_` cleanup once `_` stores are deleted during
  /// migration (see [_readAtKeysDataRaw] sequencing comment).
  Future<void> deleteAllAtKeysData() => _writes.synchronized(_deleteAll);

  Future<void> _deleteAll() async {
    try {
      await _delete(keychainStoreName: await AtKeysStore.getName());
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
    try {
      await _delete(keychainStoreName: await _getImproperAtKeysStoreName());
    } catch (e, s) {
      _logger.info('_getAtClientData', e, s);
      print(s);
    }
  }

  /// Save an SPP/OTP for an Atsign in the keychain
  ///
  ///   [atSign] - Atsign associated with the SPP
  ///
  ///   [passcode] - the [Passcode] the atSign accepted
  ///
  /// Appends the value to the existing SPP list after removing expired entries
  /// and any matching duplicate value
  Future<void> saveSpp(String atSign, Passcode passcode) async {
    final spp = SppData(value: passcode.value, expiry: passcode.expiry);

    SppListData sppListData;
    try {
      final existingData = await _read(
        keychainStoreName: SppStore(atSign).getName(),
      );
      if (existingData != null) {
        sppListData = SppListData.fromJson(jsonDecode(existingData));
      } else {
        sppListData = SppListData(spps: []);
      }
    } catch (e) {
      sppListData = SppListData(spps: []);
    }

    // Remove expired and the same value if it exists
    sppListData.spps.removeWhere(
      (element) => element.isExpired || element.value == spp.value,
    );
    sppListData.spps.add(spp);

    await _write(
      biometricStoreName: SppStore(atSign).getName(),
      keychainData: sppListData,
    );
    _logger.info('SPP saved to keychain');
  }

  /// Get all active SPPs stored for an Atsign
  ///
  ///   [atSign] - Atsign whose SPPs should be retrieved
  ///
  /// Returns a [List] of non-expired [SppData] values. Expired entries are
  /// removed from storage when encountered.
  Future<List<SppData>> getAllSpps(String atSign) async {
    try {
      final data = await _read(keychainStoreName: SppStore(atSign).getName());
      if (data == null) {
        return [];
      }
      SppListData sppListData = SppListData.fromJson(jsonDecode(data));

      // Filter out expired ones
      final activeSpps = sppListData.spps
          .where((spp) => !spp.isExpired)
          .toList();

      // If some were expired, update the store
      if (activeSpps.length != sppListData.spps.length) {
        if (activeSpps.isEmpty) {
          await deleteSppData(atSign);
        } else {
          await _write(
            biometricStoreName: SppStore(atSign).getName(),
            keychainData: SppListData(spps: activeSpps),
          );
        }
      }

      return activeSpps;
    } catch (e, st) {
      _logger.severe('Failed to get SPPs from keychain', e, st);
      return [];
    }
  }

  /// Get the active SPP for an Atsign
  ///
  ///   [atSign] - Atsign whose SPP should be retrieved
  ///
  /// Returns the most recently added non-expired [SppData], or `null` if none
  /// exist
  Future<SppData?> getActiveSpp(String atSign) async {
    final activeSpps = await getAllSpps(atSign);
    if (activeSpps.isEmpty) {
      return null;
    }
    return activeSpps.last;
  }

  /// Delete all stored SPP data for an Atsign
  ///
  ///   [atSign] - Atsign whose SPP data should be removed
  Future<void> deleteSppData(String atSign) async {
    try {
      final BiometricStorageFile biometricStore =
          await _getBiometricStorageFile(SppStore(atSign).getName());
      await biometricStore.delete();
    } catch (e) {
      _logger.warning('Failed to delete SPP data: $e');
    }
  }

  Future<String?> _read({required String keychainStoreName}) async {
    try {
      final BiometricStorageFile store = await _getBiometricStorageFile(
        keychainStoreName,
      );
      String? value;
      if (!isWindows) {
        value = await store.read();
        return value;
      } else {
        // log('READ: _readDataFromStore called', true);
        String? storedData = await store.read();
        log(
          '  => READ: Fetched length ${storedData?.length}'
          ' from $keychainStoreName',
          false,
        );
        if (storedData == null || storedData.isEmpty) {
          return null;
        }

        final layout = await _segmentLayout(keychainStoreName, storedData);
        final segmentCount = layout.count;
        final segmentPrefix = layout.prefix;
        final results = <String>[];
        for (int i = 0; i < segmentCount; i++) {
          final segmentStore = await _getBiometricStorageFile(
            '${segmentPrefix}_$i',
          );
          String? segmentValue = await segmentStore.read();
          log(
            '  => READ: Fetched segment $i, length ${segmentValue?.length}'
            ' from $segmentPrefix',
            false,
          );
          results.add(segmentValue ?? '');
        }
        value = _combineString(results);

        return value;
      }
    } catch (e, s) {
      // NOTE: never clear the store on a read failure. A transient platform
      // error or a cancelled biometric prompt would destroy what may be the
      // only copy of the atSign's keys; recovering a corrupt store is the
      // caller's decision.
      _logger.severe('_read failed with $e', e, s);
      rethrow;
    }
  }

  Future<void> _delete({required String keychainStoreName}) async {
    final store = await _getBiometricStorageFile(keychainStoreName);
    if (!isWindows) {
      await store.delete();
      return;
    }

    // NOTE: a segment that cannot be deleted is logged and the header deleted
    // regardless, so the entry reads as absent; the segments left under the
    // current prefix start at 0, where the next delete or write finds them.
    final currentPrefix = '${keychainStoreName}_segment';
    var currentCount = 0;
    String? legacyPrefix;
    int? legacyCount;
    try {
      final header = await store.read();
      if (header != null && header.isNotEmpty) {
        if (!header.startsWith('{')) {
          legacyPrefix = await _legacySegmentPrefix();
        }
        final layout = await _segmentLayout(keychainStoreName, header);
        if (legacyPrefix == null) {
          currentCount = layout.count;
        } else {
          legacyCount = layout.count;
        }
      }
    } catch (e, s) {
      _logger.severe(
        'Failed to read the Windows keychain header of "$keychainStoreName" '
        'for deletion; deleting the segments found',
        e,
        s,
      );
    }
    try {
      await _deleteSegmentsFrom(currentPrefix, 0, atLeast: currentCount);
      // NOTE: every store's legacy header names the same segments, so one
      // whose count can be read has only those deleted.
      if (legacyPrefix != null) {
        if (legacyCount == null) {
          await _deleteSegmentsFrom(legacyPrefix, 0);
        } else {
          await _deleteSegmentRange(legacyPrefix, 0, legacyCount);
        }
      }
    } catch (e, s) {
      _logger.severe(
        'Failed to delete the Windows keychain segments of '
        '"$keychainStoreName"',
        e,
        s,
      );
    }

    await store.delete();
  }

  /// Deletes the Windows segments `<prefix>_<first>` upward: each below
  /// [atLeast], stored or not, then each stored one, an empty one included,
  /// up to the first absent, never reaching [_kMaxWindowSegments].
  ///
  /// They are deleted from the top down, throwing on the first that cannot be
  /// read or deleted or stays stored, so those left run unbroken from
  /// [first], where a later search from there finds them.
  Future<void> _deleteSegmentsFrom(
    String prefix,
    int first, {
    int atLeast = 0,
  }) async {
    var end = first;
    while (end < _kMaxWindowSegments &&
        (end < atLeast || await _isStored('${prefix}_$end'))) {
      end++;
    }
    await _deleteSegmentRange(prefix, first, end);
  }

  /// Deletes the Windows segments `<prefix>_<first>` to `<prefix>_<end - 1>`,
  /// stored or not, from the top down, throwing on the first that cannot be
  /// deleted or stays stored.
  Future<void> _deleteSegmentRange(String prefix, int first, int end) async {
    for (var i = end - 1; i >= first; i--) {
      await _deleteSegment('${prefix}_$i');
    }
  }

  /// Writes [keychainData] to the keys entry named [name], which held
  /// [previous], or nothing when it is null.
  ///
  /// On Windows the entry is a header and segments written one at a time, so
  /// a write to the store that fails partway is undone before the failure is
  /// rethrown: [previous] is written back, or the entry deleted when it held
  /// nothing, and the segments the failed write added past it are deleted. A
  /// failure to undo it is logged, and the write's own failure thrown. The
  /// undo is a write too, so it overwrites a write another isolate made
  /// since [previous] was read. A write that succeeds deletes the segments
  /// [previous] had past its own.
  Future<void> _replaceEntry({
    required String name,
    required String? previous,
    required KeychainData keychainData,
  }) async {
    final data = jsonEncode(keychainData.toJson());
    try {
      await _writeText(biometricStoreName: name, data: data);
    } catch (e, s) {
      if (isWindows) await _undoWrite(name, previous);
      Error.throwWithStackTrace(e, s);
    }
  }

  /// Puts the entry named [name] back as [previous] after a failed write.
  Future<void> _undoWrite(String name, String? previous) async {
    try {
      if (previous == null) {
        await _delete(keychainStoreName: name);
      } else {
        await _writeText(biometricStoreName: name, data: previous);
      }
    } catch (e, s) {
      _logger.severe(
        'Undoing a failed write of keychain entry "$name" failed; it may be '
        'left partly written',
        e,
        s,
      );
    }
  }

  Future<void> _write({
    required String biometricStoreName,
    required KeychainData keychainData,
  }) => _writeText(
    biometricStoreName: biometricStoreName,
    data: jsonEncode(keychainData.toJson()),
  );

  Future<void> _writeText({
    required String biometricStoreName,
    required String data,
  }) async {
    BiometricStorageFile store = await _getBiometricStorageFile(
      biometricStoreName,
    );
    if (!isWindows) {
      //log("WRITE: _writeDataToStore called", true);
      await store.write(data);
    } else {
      //log('WRITE: _writeDataToStore called', true);
      final dataList = _splitString(data, _kWindowSegmentDataLength);
      final segmentPrefix = '${biometricStoreName}_segment';
      // A shorter document leaves the old document's trailing segments
      // behind; note how many there were so they can be deleted below.
      int oldSegmentCount = 0;
      ({int count, String prefix})? legacyLayout;
      try {
        final oldHeader = await store.read();
        if (oldHeader != null && oldHeader.isNotEmpty) {
          final layout = await _segmentLayout(biometricStoreName, oldHeader);
          if (layout.prefix == segmentPrefix) {
            oldSegmentCount = layout.count;
          } else {
            legacyLayout = layout;
          }
        }
      } catch (e, s) {
        // The write itself can still succeed; only the stale segments of an
        // unreadable header are left in place.
        _logger.warning(
          'Failed to read Windows keychain segment metadata before write;'
          ' stale segments of "$biometricStoreName" may remain',
          e,
          s,
        );
      }
      String segmentCountInfo = jsonEncode({'segmentCount': dataList.length});
      //log('  => WRITE: Writing $segmentCountInfo to ${store.name}', false);
      await store.write(segmentCountInfo);

      for (int i = 0; i < dataList.length; i++) {
        final segmentStore = await _getBiometricStorageFile(
          '${biometricStoreName}_segment_$i',
        );
        //log('  => WRITE: Writing segment $i length ${dataList[i].length} to ${segmentStore.name}',
        //    false);
        // log('  => WRITE: segmentValue was ${dataList[i]}', false);
        await segmentStore.write(dataList[i]);
      }

      // NOTE: a failure here is logged, not thrown: the new document is
      // already written.
      try {
        // NOTE: every store's legacy header names the same segments, so only
        // the old header's own are deleted.
        if (legacyLayout != null) {
          await _deleteSegmentRange(legacyLayout.prefix, 0, legacyLayout.count);
        }
        await _deleteSegmentsFrom(
          segmentPrefix,
          dataList.length,
          atLeast: oldSegmentCount,
        );
      } catch (e, s) {
        _logger.severe(
          'Failed to delete stale Windows keychain segments of'
          ' "$biometricStoreName": $e',
          e,
          s,
        );
      }
    }
  }

  Future<bool> _isStored(String name) async =>
      await (await _getBiometricStorageFile(name)).read() != null;

  /// Deletes the Windows segment [name], throwing [StateError] if it is still
  /// stored afterwards.
  Future<void> _deleteSegment(String name) async {
    await (await _getBiometricStorageFile(name)).delete();
    if (await _isStored(name)) {
      throw StateError('Windows keychain segment "$name" is still stored');
    }
  }

  /// Parses the Windows header [storedData] of [keychainStoreName] into the
  /// number of segments it points at and the name prefix they use.
  ///
  /// A header whose count [_segmentCountIn] refuses throws
  /// [AtKeysFormatException].
  Future<({int count, String prefix})> _segmentLayout(
    String keychainStoreName,
    String storedData,
  ) async => (
    count: _segmentCountIn(storedData),
    prefix: storedData.startsWith('{')
        ? '${keychainStoreName}_segment'
        : await _legacySegmentPrefix(),
  );

  /// The name prefix of the segments a legacy Windows header points at.
  ///
  /// It is the app's package name and not the store's, so every legacy header
  /// the app wrote points at the same segment names.
  static Future<String> _legacySegmentPrefix() async =>
      '${await getPackageName()}_data';

  Future<BiometricStorageFile> _getBiometricStorageFile(
    String storeName,
  ) async {
    return await biometricStorage.getStorage(
      storeName,
      options: StorageFileInitOptions(authenticationRequired: false),
    );
  }

  /// Split a string into fixed-size segments
  ///
  ///   [text] - Source string to split
  ///
  ///   [segmentLength] - Maximum length of each segment
  ///
  /// Returns a [List] of string segments
  List<String> _splitString(String text, int segmentLength) {
    int segmentCount = (text.length / segmentLength).ceil();
    final result = <String>[];
    for (int i = 0; i < segmentCount; i++) {
      if (i == segmentCount - 1) {
        result.add(text.substring(i * segmentLength, text.length));
      } else {
        result.add(text.substring(i * segmentLength, (i + 1) * segmentLength));
      }
    }
    return result;
  }

  /// Combine a list of string segments into a single string
  ///
  ///   [texts] - String segments to combine
  ///
  /// Returns the combined string, or `null` if the list is empty
  String? _combineString(List<String> texts) {
    if (texts.isEmpty) {
      return null;
    }
    return texts.join();
  }

  /// Write a message to the internal logger
  ///
  ///   [s] - Log message
  ///
  ///   [logStackTrace] - Whether to include the current stack trace
  void log(String s, bool logStackTrace) {
    _logger.info(s);
    if (!logStackTrace) {
      return;
    }
    List<String> st = StackTrace.current.toString().split('\n');
    for (int i = 0; i < 30 && i < st.length; i++) {
      if (st[i] == '<asynchronous suspension>') {
        continue;
      }
      _logger.info('    ${st[i]}');
    }
  }
}
