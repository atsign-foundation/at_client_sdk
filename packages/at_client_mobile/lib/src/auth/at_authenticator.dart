import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/auth/at_keys_file.dart';

abstract class AtAuthenticator {
  Future<AtAuthResponse> authenticate(String atSign, {String? enrollmentId});
}

class AtAuthRequest {
  String atSign;
  AtAuthRequest(this.atSign, this.preference);
  AtClientPreference preference;
  String? enrollmentId;
  AtKeysFileData? atKeysData;
  PkamAuthMode authMode = PkamAuthMode.keysFile;

  /// public key id if [authMode] is [PkamAuthMode.sim]
  String? publicKeyId;
}

class AtAuthResponse {
  String atSign;
  AtAuthResponse(this.atSign);
  bool isSuccessful = false;

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
