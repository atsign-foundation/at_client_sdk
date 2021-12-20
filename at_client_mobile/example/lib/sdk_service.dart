import 'dart:core';
import 'dart:io';
import 'package:at_app_flutter/at_app_flutter.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

class ClientSdkService {
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  final AtSignLogger _logger = AtSignLogger('Plugin example app');
  static final ClientSdkService _singleton = ClientSdkService._internal();

  ClientSdkService._internal();

  factory ClientSdkService.getInstance() {
    return _singleton;
  }

  AtClientService? atClientServiceInstance;
  final AtClientManager atClientInstance = AtClientManager.getInstance();
  Map<String?, AtClientService> atClientServiceMap =
      <String?, AtClientService>{};
  String? atsign;

  AtClient? _getAtClientForAtsign() => atClientInstance.atClient;

  Future<AtClientPreference> getAtClientPreference({String? cramSecret}) async {
    Directory appDocumentDirectory =
        await path_provider.getApplicationSupportDirectory();
    String path = appDocumentDirectory.path;
    AtClientPreference _atClientPreference = AtClientPreference()
      ..isLocalStoreRequired = true
      ..commitLogPath = path
      ..cramSecret = cramSecret
      ..namespace = AtEnv.appNamespace
      ..rootDomain = AtEnv.rootDomain
      ..hiveStoragePath = path;
    return _atClientPreference;
  }

  /// Gets [AtValue] and returns [AtValue.value].
  /// It may be null when it throws an exception.
  Future<String?> get(AtKey atKey) async {
    try {
      AtValue? result = await _getAtClientForAtsign()!.get(atKey);
      return result.value;
    } on AtClientException catch (atClientExcep) {
      _logger.severe('❌ AtClientException : ${atClientExcep.errorMessage}');
      return null;
    } catch (e) {
      _logger.severe('❌ Exception : ${e.toString()}');
      return null;
    }
  }

  /// Creates or updates [AtKey.key] with it's
  /// [AtValue.value] and returns Future bool value.
  Future<bool> put(AtKey atKey, String value) async {
    try {
      return _getAtClientForAtsign()!.put(atKey, value);
    } on AtClientException catch (atClientExcep) {
      _logger.severe('❌ AtClientException : ${atClientExcep.errorMessage}');
      return false;
    } catch (e) {
      _logger.severe('❌ Exception : ${e.toString()}');
      return false;
    }
  }

  /// Deletes [AtKey.atKey], so that it's values also
  /// will be deleted and returns Future bool value.
  Future<bool> delete(AtKey atKey) async {
    try {
      bool valueExists = await get(atKey) != null;
      if (valueExists) {
        return _getAtClientForAtsign()!.delete(atKey);
      }
      return false;
    } on AtClientException catch (atClientExcep) {
      _logger.severe('❌ AtClientException : ${atClientExcep.errorMessage}');
      return false;
    } catch (e) {
      _logger.severe('❌ Exception : ${e.toString()}');
      return false;
    }
  }

  Future<List<AtKey>> getAtKeys({String? regex, String? sharedBy}) async =>
      _getAtClientForAtsign()!
          .getAtKeys(regex: AtEnv.appNamespace, sharedBy: sharedBy);

  /// Fetches atsign from device keychain.
  Future<String?> getAtSign() async => _keyChainManager.getAtSign();

  Future<void> logout(BuildContext context) async {
    String? atsign = atClientInstance.atClient.getCurrentAtSign();
    await _keyChainManager.deleteAtSignFromKeychain(atsign!);
    atClientServiceInstance = null;
    atClientServiceMap = <String?, AtClientService>{};
    atsign = null;
    Navigator.pop(context);
  }
}
