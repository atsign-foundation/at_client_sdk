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
    // An entry written by an older release carries its atSign only in the
    // metadata, and `AtKeys.toJson` refuses to serialize typed material
    // without `atsign` — so without this backfill the first flush of a key
    // package or nskey private onto a pre-existing entry would throw.
    atsignKey.atsign ??= atSign.toAtsign();
    return atsignKey;
  }

  @override
  Future<void> write(String atSign, AtKeys atKeys) async {
    // Create-only, like every other WrittenAtKeysIo. The underlying store
    // APPENDS, and `read` answers with the first matching entry — so writing
    // an atSign that already has one used to leave two entries with only the
    // older reachable. A second onboard of the same atSign would then look
    // like it had worked while every later read returned the superseded keys.
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
    // The keychain holds `AtKeys.toJson()` in the clear — the OS keystore is
    // the protection — so both sides of the assurance check are plaintext and
    // the ciphertext-comparison problem the `.atKeys` file has does not arise
    // here.
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
  /// entry an older release wrote instead — the one the keychain still falls
  /// back to for entries that predate the typed field.
  ///
  /// Neither is overwritten once set. The metadata entry is a legacy value the
  /// never-lose assurance holds to be preserved, so restamping it in the
  /// canonical spelling would have every flush onto an entry stored under a
  /// different spelling refused as a lost value — and the spelling does not
  /// need to match, because the keychain compares normalized.
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
