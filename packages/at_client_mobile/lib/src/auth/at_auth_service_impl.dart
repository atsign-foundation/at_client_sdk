import 'dart:async';

import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';

class AtAuthServiceImpl implements AtAuthService {
  AtServiceFactory? atServiceFactory;

  // ignore: unused_field
  final String _atSign;

  // ignore: unused_field
  final AtClientPreference _atClientPreference;

  final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  AtClientManager atClientManager = AtClientManager.getInstance();

  AtAuthServiceImpl(this._atSign, this._atClientPreference);

  @override
  Future<bool> isOnboarded(String atSign) async {
    AtsignKey? atsignKey = await _keyChainManager.readAtsign(name: atSign);
    if (atsignKey == null) {
      return false;
    }
    if (atsignKey.encryptionPublicKey == null ||
        atsignKey.encryptionPublicKey!.isEmpty) {
      return false;
    }
    return true;
  }
}
