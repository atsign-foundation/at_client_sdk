import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_client_flutter/src/keychain/at_client_data.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart'
    show KeyChainStorage;
import 'package:at_utils/at_logger.dart';

const String enrollmentInfoKey = 'enrollmentInfo';

const int _kDataSchemeVersion = 2;

/// Service to manage keychain CRUD operations for atsigns
class KeyChainManager {
  static final _logger = AtSignLogger('KeyChainManager');
  KeyChainStorage keyChainStorage;

  KeyChainManager(
      {KeyChainStorage? keyChainStorage, bool useSharedStorage = false})
      : keyChainStorage = keyChainStorage ?? KeyChainStorage() {
    initialSetup(useSharedStorage: useSharedStorage);
  }

  /// Check app allow sharing atsign or not
  /// @returns 'null' if not define yet
  /// @returns 'true' if use sharing store
  /// @returns 'false' if use internal store

  /// Initial setup
  Future<void> initialSetup({required bool useSharedStorage}) async {
    if (useSharedStorage) {
      //Init shared storage if it not exiting
      final data =
          await keyChainStorage.readAtClientData(useSharedStorage: true);
      if (data == null) {
        keyChainStorage.saveAtClientData(
          data: AtClientData(
            config: AtClientDataConfig(
              schemaVersion: _kDataSchemeVersion,
            ),
            keys: [],
          ),
          useSharedStorage: useSharedStorage,
        );
      }
      await enableUsingSharedStorage();
      _logger.finer('Initial setup with shared storage');
    } else {
      await disableUsingSharedStorage();
      _logger.finer('Initial setup with internal storage');
    }
  }

  /// Function to get atsign's key with name
  Future<AtKeys?> getAtSign({required String name}) async {
    final atSigns = await getAllAtSigns();
    if (atSigns.isEmpty) {
      _logger.info('No atsign found in keychain');
      return null;
    }
    for (int i = 0; i < atSigns.length; i++) {
      if (atSigns[i].metadata.containsKey('atsign')) {
        if (atSigns[i].metadata['atsign'] == name) {
          return atSigns[i];
        }
      }
    }
    return null;
  }

  /// Function to get all atsign item in keychain
  Future<List<AtKeys>> getAllAtSigns() async {
    final atClientData =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    final data = await keyChainStorage.readAtClientData(
        useSharedStorage: useSharedStorage);
    return data?.keys ?? [];
  }

  /// Function to add a new atsign to keychain
  Future<bool> putAtSign({required AtKeys atKeys}) async {
    final internalAtClientData =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData = await keyChainStorage.readAtClientData(
        useSharedStorage: useSharedStorage);
    try {
      if (atClientData != null) {
        final atSigns = atClientData.keys;
        atSigns.removeWhere((element) =>
            element.metadata['atsign'] == atKeys.metadata['atsign']);
        atSigns.add(atKeys);
        await keyChainStorage.saveAtClientData(
            data: atClientData, useSharedStorage: useSharedStorage);
        return true;
      }
    } catch (e, s) {
      _logger.severe('exception in putAtSign :${e.toString()}');
      _logger.severe(s);
    }
    return false;
  }

  /// Function to add new atsigns to keychain
  Future<bool> putAllAtSigns({required List<AtKeys> atSigns}) async {
    final internalAtClientData =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    final useSharedStorage =
        internalAtClientData?.config?.useSharedStorage ?? false;
    final atClientData = await keyChainStorage.readAtClientData(
        useSharedStorage: useSharedStorage);
    try {
      if (atClientData != null) {
        final oldAtSigns = atClientData.keys;
        //If have no account => make this account is default
        for (var atsign in atSigns) {
          if (atsign.metadata.containsKey('atsign')) {
            oldAtSigns.removeWhere((element) =>
                element.metadata['atsign'] == atsign.metadata['atsign']);
            oldAtSigns.add(atsign);
          }
        }
        final newAtClientData = atClientData.copyWith(keys: oldAtSigns);
        await keyChainStorage.saveAtClientData(
            data: newAtClientData, useSharedStorage: useSharedStorage);
        return true;
      }
    } catch (e, s) {
      _logger.severe('exception in putAllAtSigns :${e.toString()}');
      _logger.severe(s);
    }
    return false;
  }

  /// Function to get default atsign from keychain
  Future<String?> getDefaultAtSign() async {
    final atClientData =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    final defaultAtsign = atClientData?.defaultAtsign;
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    final atsignKeys = (await keyChainStorage.readAtClientData(
                useSharedStorage: useSharedStorage))
            ?.keys ??
        [];
    for (var element in atsignKeys) {
      if (element.metadata.containsKey('atsign')) {
        if (element.metadata['atsign'] == defaultAtsign) {
          return element.metadata['atsign'];
        }
      }
    }
    if (atsignKeys.isNotEmpty) return atsignKeys.first.metadata['atsign'];
    return null;
  }

  /// Function to make the atsign passed as primary
  Future<bool> setDefaultAtSign(String atsign) async {
    final atClientData =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    if (atClientData != null) {
      atClientData.defaultAtsign = atsign;
      await keyChainStorage.saveAtClientData(
          data: atClientData, useSharedStorage: false);
      return true;
    } else {
      return false;
    }
  }

  /// Function to remove an atsign from list of atsigns and hence, from keychain
  Future<bool> deleteAtSign(String atsign) async {
    final atClientData =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    final useSharedStorage = atClientData?.config?.useSharedStorage ?? false;
    atClientData?.keys
        .removeWhere((element) => element.metadata['atsign'] == atsign);
    if (atClientData != null) {
      await keyChainStorage.saveAtClientData(
          data: atClientData, useSharedStorage: useSharedStorage);
      return true;
    } else {
      return false;
    }
  }

  /// Function to delete the datastore. This will delete all atsigns from keychain
  Future<void> deleteAllAtSigns() async {
    await keyChainStorage.deleteDataStore();
  }

  /// Function to delete all values related to the atsign passed from keychain
  Future<bool> resetAtSign(String atsign) async {
    AtClientData? atClientData;

    final useSharedStorage =
        (await keyChainStorage.readAtClientData(useSharedStorage: false))
            ?.config
            ?.useSharedStorage;

    if (useSharedStorage == true) {
      final atClientDataShared =
          await keyChainStorage.readAtClientData(useSharedStorage: true);

      atClientDataShared?.keys
          .removeWhere((element) => element.metadata['atsign'] == atsign);

      atClientData =
          await keyChainStorage.readAtClientData(useSharedStorage: false);

      atClientData?.keys
          .removeWhere((element) => element.metadata['atsign'] == atsign);

      if (atClientData != null && atClientDataShared != null) {
        await keyChainStorage.saveAtClientData(
            data: atClientData, useSharedStorage: false);

        await keyChainStorage.saveAtClientData(
            data: atClientDataShared, useSharedStorage: true);

        return true;
      } else {
        return false;
      }
    } else {
      atClientData =
          await keyChainStorage.readAtClientData(useSharedStorage: false);

      atClientData?.keys
          .removeWhere((element) => element.metadata['atsign'] == atsign);

      if (atClientData != null) {
        await keyChainStorage.saveAtClientData(
            data: atClientData, useSharedStorage: false);
        return true;
      } else {
        return false;
      }
    }
  }

  /// Change atsign data to internal store
  Future<bool> disableUsingSharedStorage() async {
    final data =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    if (data != null) {
      if (data.config?.useSharedStorage == false) {
        return false;
      }
      final newConfig = data.config?.copyWith(useSharedStorage: false);
      var newData = data.copyWith(config: newConfig);
      await keyChainStorage.saveAtClientData(
          data: newData, useSharedStorage: false);
      final sharedAtsigns =
          (await keyChainStorage.readAtClientData(useSharedStorage: true))
                  ?.keys ??
              [];
      final result = await putAllAtSigns(atSigns: sharedAtsigns);
      return result;
    }
    return false;
  }

  /// Change atsign data to internal store
  Future<bool> enableUsingSharedStorage() async {
    //Init shared storage if it not exiting
    final sharedData =
        await keyChainStorage.readAtClientData(useSharedStorage: true);
    if (sharedData == null) {
      await keyChainStorage.saveAtClientData(
        data: AtClientData(
          config: AtClientDataConfig(
            schemaVersion: _kDataSchemeVersion,
          ),
          keys: [],
        ),
        useSharedStorage: true,
      );
    }
    //
    final data =
        await keyChainStorage.readAtClientData(useSharedStorage: false);
    if (data != null) {
      final newConfig = data.config?.copyWith(useSharedStorage: true);
      var newData = data.copyWith(config: newConfig);
      await keyChainStorage.saveAtClientData(
          data: newData, useSharedStorage: false);
      final result = await putAllAtSigns(atSigns: data.keys);
      if (result) {
        newData = newData.copyWith(keys: []);
        await keyChainStorage.saveAtClientData(
            data: newData, useSharedStorage: false);
      }
      return result;
    }
    return false;
  }
}
