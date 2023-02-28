
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/auth/at_keys_source.dart';

abstract class AtClientServiceV2 {
  AtChops? atChops;
  Future<AtLoginResponse> login(AtLoginRequest atLoginRequest);
  bool isOnboarded();
  bool onboard();
}

class AtLoginRequest {
  String _atSign;
  AtLoginRequest(this._atSign);
  AtClientPreference? preference;
  AtKeysFileData? atKeysData;
}

class AtLoginResponse {
  String _atSign;
  AtLoginResponse(this._atSign);
  bool isSuccessful = false;
  AtClientException? atException;
}


