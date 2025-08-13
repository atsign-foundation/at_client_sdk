import 'dart:convert';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:at_theme_flutter/utils/constants.dart';
import 'package:at_utils/at_utils.dart';

class ThemeService {
  ThemeService._();
  static final ThemeService _instance = ThemeService._();
  factory ThemeService() => _instance;

  final _logger = AtSignLogger('ThemeService');

  String? rootDomain;
  int? rootPort;
  String? currentAtsign;

  var atClientManager = AtClientManager.getInstance();

  initThemeService(String rootDomainFromApp, int rootPortFromApp) {
    rootDomain = rootDomainFromApp;
    rootPort = rootPortFromApp;
    currentAtsign = atClientManager.atClient.getCurrentAtSign();
  }

  Future<bool> updateThemeData(AppTheme themeData) async {
    AtKey atKey = getAtkey();
    try {
      var result =
          await atClientManager.atClient.put(atKey, themeData.encoded());
      return result;
    } catch (e) {
      _logger.severe('error in updating theme data: ${e.toString()}');
      return false;
    }
  }

  Future<AppTheme?> getThemeData() async {
    try {
      AtKey atKey = getAtkey();
      var atValue = await atClientManager.atClient.get(atKey);

      if (atValue.value == null && atValue.value == 'null') {
        return null;
      }

      AppTheme? themeData = AppTheme.decode(jsonDecode(atValue.value));
      return themeData;
    } catch (e) {
      _logger.severe('error in getThemeData : ${e.toString()}');
    }
    return null;
  }

  AtKey getAtkey() {
    Metadata metaData = Metadata();
    AtKey atKey = AtKey()
      ..key = MixedConstants.theme_key
      ..metadata = metaData
      ..metadata.ttr = -1
      ..metadata.ccd = true;

    return atKey;
  }
}
