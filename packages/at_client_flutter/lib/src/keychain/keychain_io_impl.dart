import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysFileOverwriteException,
        AtKeysValidationException,
        WrittenAtKeysIo;
import 'package:at_commons/at_commons.dart';

import 'keychain_storage.dart';

/// Implementation of WrittenAtKeysIo using Keychain storage
/// Uses KeyChainManager to perform the CRUD operations related to keychains
///
/// This is the main class to interact with keychain for storing and retrieving AtKeys
class KeychainAtKeysIo extends WrittenAtKeysIo {
  KeychainStorage keychainStorage;
  KeychainAtKeysIo({KeychainStorage? keychainStorage})
    : keychainStorage = keychainStorage ?? KeychainStorage();

  @override
  Future<AtKeys> read(String atSign) async {
    final AtKeys? atsignKey = await _existing(atSign);
    if (atsignKey == null) {
      throw AtKeyException(
        'AtsignKey not found in keychain for atSign: $atSign',
      );
    }
    // NOTE: an entry may carry its atSign only in the metadata, and
    // `AtKeys.toJson` refuses to serialize typed material without `atsign`.
    atsignKey.atsign ??= atSign.toAtsign();
    return atsignKey;
  }

  @override
  Future<void> write(String atSign, AtKeys atKeys) async {
    // NOTE: create-only. The underlying store appends and `read` answers with
    // the first matching entry, so a second write for the same atSign would
    // leave the newer keys unreachable.
    if (await _existing(atSign) != null) {
      throw AtKeysFileOverwriteException(
        'Tried writing $atSign to the keychain, but failed since it already '
        'has an entry. Use flush() to persist a change to existing keys.',
      );
    }
    _stampAtSign(atSign, atKeys);
    await keychainStorage.appendAtKeysToKeychain(keys: atKeys);
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) async {
    final atSign = atsign.toString();
    _stampAtSign(atSign, atKeys);
    await keychainStorage.updateAtKeysInKeychain(
      atSign: atSign,
      keys: atKeys,
      assureUpdate: (existing) => assurance.validateMapUpdate(
        existing: existing.toJson(),
        candidate: atKeys.toJson(),
      ),
    );
  }

  /// Records the owner on the typed `atsign` field, which `AtKeys.toJson`
  /// requires before it will serialize typed material, and on the `metadata`
  /// entry the keychain falls back to.
  ///
  /// Neither is overwritten once set: the metadata entry is one the never-lose
  /// assurance holds to be preserved, and the keychain compares atSigns
  /// normalized, so the stored spelling need not match.
  void _stampAtSign(String atSign, AtKeys atKeys) {
    final normalized = atSign.toAtsign();
    if (atKeys.atsign != null && atKeys.atsign != normalized) {
      throw AtKeysValidationException(
        'AtKeys belongs to ${atKeys.atsign} but is being persisted for '
        '$normalized',
      );
    }
    atKeys.atsign ??= normalized;
    atKeys.metadata['atsign'] ??= normalized.toString();
  }

  /// The entry for [atSign], or null — including when the keychain holds no
  /// AtKeys data at all, which `getAtsign` reports by throwing.
  Future<AtKeys?> _existing(String atSign) async {
    try {
      return await keychainStorage.getAtsign(atSign);
    } on AtKeyException {
      return null;
    }
  }
}
