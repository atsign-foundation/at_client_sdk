import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_lookup/at_lookup.dart';

import 'at_authenticator.dart';

class CramAuthenticator implements AtAuthenticator {
  String _cramSecret;
  AtClientPreference _atClientPreference;
  CramAuthenticator(this._cramSecret, this._atClientPreference);

  AtLookUp? atLookup;

  @override
  Future<AtAuthResponse> authenticate(String atSign) async {
    atLookup ??= AtLookupImpl(
        atSign, _atClientPreference.rootDomain, _atClientPreference.rootPort);
    var authResult = AtAuthResponse(atSign);
    try {
      bool cramResult =
          await (atLookup as AtLookupImpl).authenticate_cram(_cramSecret);
      authResult.isSuccessful = cramResult;
    } on UnAuthenticatedException catch (e) {
      authResult.atClientException = AtClientException(
          error_codes['UnAuthenticatedException'],
          'cram auth failed for $atSign - ${e.toString()}');
    }
    return authResult;
  }
}
