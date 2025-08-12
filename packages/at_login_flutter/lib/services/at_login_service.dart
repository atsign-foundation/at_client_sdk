import 'dart:convert';
import 'dart:core';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_login_flutter/domain/at_login_model.dart';
import 'package:at_login_flutter/exceptions/at_login_exceptions.dart';
import 'package:at_login_flutter/utils/app_constants.dart';
import 'package:at_login_flutter/utils/at_login_utils.dart';
import 'package:at_login_flutter/utils/strings.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_utils.dart';
import 'package:crypton/crypton.dart';
import 'package:flutter/material.dart';

class AtLoginService {
  static final AtLoginService _singleton = AtLoginService._internal();

  // late List<AtLoginObj> _atLoginList;
  late AtClientPreference _atClientPreference;
  late String _initialised;

  Widget get nextScreen => _nextScreen;
  late Widget _nextScreen;

  late AtStatus atStatus;
  final AtStatusImpl atStatusImpl = AtStatusImpl();

  late AtSignLogger _logger = AtSignLogger('AtLoginService');

  // SDKService _sdkService = SDKService();

  AtLoginService._internal();

  factory AtLoginService() {
    return _singleton;
  }

  // var atLoginProvider = AtLoginProvider();
  // AtClient? _atClient;
  // String? _atsign;

  // late bool isMonitorStarted;

  init(String atSign, AtClientPreference atClientPreference) {
    if (atSign != _initialised) {
      // atLoginList;
      // isMonitorStarted = false;
      _initialised = atSign;
      _atClientPreference = atClientPreference;
    }
  }

  set atClientPreference(AtClientPreference preference) {
    _atClientPreference = preference;
  }

  set nextScreen(Widget? widget) {
    _nextScreen = widget!;
  }

  Future<bool> setAtsign(String? atSign) async {
    bool success = false;
    var namespace = _atClientPreference.namespace;
    await AtClientManager.getInstance()
        .setCurrentAtSign(atSign!, namespace, _atClientPreference);
    // if (result != null) success = true;
    return success;
  }

  Future<AtValue> getAtLoginObj(AtKey atKey) async {
    return await AtClientManager.getInstance().atClient.get(atKey).timeout(
        Duration(seconds: AppConstants.responseTimeLimit),
        onTimeout: () => _onTimeOut());
  }

  Future<bool> putAtLoginObj(AtLoginObj atLoginObj) async {
    var timestamp = new DateTime.now().millisecondsSinceEpoch.toString();
    var key = "$timestamp.${AppConstants.atLoginWidgetNamespace}";
    var atKey = AtKey()..key = key;
    var value = atLoginObj.toJson().toString();
    return await AtClientManager.getInstance()
        .atClient
        .put(atKey, value)
        .timeout(Duration(seconds: AppConstants.responseTimeLimit),
            onTimeout: () => _onTimeOut());
  }

  Future<bool> deleteAtLoginObj(String key) async {
    AtKey atKey = AtKey()..key = key;
    return await AtClientManager.getInstance().atClient.delete(atKey).timeout(
        Duration(seconds: AppConstants.responseTimeLimit),
        onTimeout: () => _onTimeOut());
  }

  Future<List<AtValue>> getAtLoginObjs() async {
    List<AtValue> atvalueList = [];
    AtClient atClient = AtClientManager.getInstance().atClient;
    List<AtKey> atKeys = await atClient.getAtKeys(regex: AppConstants.regex);
    for (var atKey in atKeys) {
      AtValue atValue = await atClient.get(atKey);
      atvalueList.add(atValue);
    }
    return atvalueList;
  }

  Future<bool> handleAtLogin(AtLoginObj atLoginObj) async {
    bool success = false;
    var paired = await atsignIsPaired(atLoginObj.atsign!);
    if (paired) {
      await setAtsign(atLoginObj.atsign);
      var atKey = AtKey()
        ..key = DateTime.now().microsecondsSinceEpoch.toString()
        ..sharedBy = atLoginObj.atsign
        ..namespace = AppConstants.atLoginWidgetNamespace;
      var data = atLoginObj.toJson().toString();
      success = await AtClientManager.getInstance()
          .atClient
          .put(atKey, data)
          .timeout(Duration(seconds: AppConstants.responseTimeLimit),
              onTimeout: () => _onTimeOut());
    } else {}
    return success;
  }

  Future<bool> checkTLSCertificate(String fqdn) async {
    return await AtLoginUtils().checkSSLCertViaFQDN(fqdn);
  }

  Future<AtSignStatus?> checkAtSignStatus(String atSign) async {
    atStatus = await atStatusImpl.get(atSign);
    return atStatus.atSignStatus;
  }

  Future<bool> putLoginProof(AtLoginObj atLoginObj) async {
    _logger.info('putLoginProof received ${atLoginObj.atsign}');
    bool success = false;
    var paired = await atsignIsPaired(atLoginObj.atsign!);
    if (paired) {
      var encryptionPrivateKey = await AtClientManager.getInstance()
          .atClient
          .encryptionService!
          .localSecondary!
          .getEncryptionPrivateKey();

      var privateKey = RSAPrivateKey.fromString(encryptionPrivateKey ?? '');
      var dataSignature = privateKey
          .createSHA256Signature(utf8.encode(atLoginObj.challenge ?? ''));
      var signature = base64Encode(dataSignature);

      await setAtsign(atLoginObj.atsign);
      _logger.info(
          'putLoginProof|atLoginObj.requestorUrl:${atLoginObj.requestorUrl}');
      var metadata = Metadata()
        ..isPublic = true
        ..isHidden = true
        ..ttl = 30;
      var atKey = AtKey()
        ..key = atLoginObj.location ?? ""
        ..metadata = metadata;
      var data = signature;
      _logger.info('putLoginProof|atKey:$atKey');
      success = await AtClientManager.getInstance()
          .atClient
          .put(atKey, data)
          .timeout(Duration(seconds: AppConstants.responseTimeLimit),
              onTimeout: () => _onTimeOut());
    }
    return success;
  }

  Future<bool> atsignIsPaired(String atsign) async {
    List<String> atsignList = await getAtsignList().timeout(
        Duration(seconds: AppConstants.responseTimeLimit),
        onTimeout: () => _onTimeOut());
    return atsignList.indexOf(atsign) >= 0;
  }

  ///Returns null if [atsign] is null else the formatted [atsign].
  ///[atsign] must be non-null.
  String? formatAtSign(String? atsign) {
    if (atsign == null) {
      return null;
    } else if (atsign.contains(':')) {
      return Strings.invalidAtsign;
    }
    atsign = atsign.trim().toLowerCase().replaceAll(' ', '');
    atsign = !atsign.startsWith('@') ? '@' + atsign : atsign;
    return atsign;
  }

  _onTimeOut() {
    _logger.severe('Reponse Timed Out!');
    throw ResponseTimeOutException();
  }

  Future<List<String>> getAtsignList() async {
    var atSignsList =
        await KeyChainManager.getInstance().getAtSignListFromKeychain();
    return atSignsList;
  }
}
