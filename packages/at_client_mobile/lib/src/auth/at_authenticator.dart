import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/at_client_service_v2.dart';
import 'package:at_client_mobile/src/auth/at_keys_source.dart';

abstract class AtAuthenticator {
  Future<AtAuthResponse> authenticate(String atSign);
}

class AtAuthRequest {
  String atSign;
  AtAuthRequest(this.atSign, this.preference);
  AtClientPreference preference;
  AtKeysFileData? atKeysData;
  PkamAuthMode authMode = PkamAuthMode.keysFile;

  /// public key id if [authMode] is [PkamAuthMode.sim]
  String? publicKeyId;
}

class AtAuthResponse {
  String atSign;
  AtAuthResponse(this.atSign);
  bool isSuccessful = false;
  AtClientException? atClientException;
}
