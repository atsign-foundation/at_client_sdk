import 'package:at_auth/src/auth/at_auth_response.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class CramAuthenticator {
  final String _cramSecret;
  final String _atSign;
  CramAuthenticator(this._atSign, this._cramSecret, this.atLookup);

  AtLookUp? atLookup;

  Future<AtAuthResponse> authenticate() async {
    var authResult = AtAuthResponse(_atSign);
    try {
      bool cramResult =
          await (atLookup as AtLookupImpl).cramAuthenticate(_cramSecret);
      authResult.isSuccessful = cramResult;
    } on UnAuthenticatedException catch (e) {
      throw UnAuthenticatedException(
          'cram auth failed for $_atSign - ${e.toString()}');
    }
    return authResult;
  }
}
