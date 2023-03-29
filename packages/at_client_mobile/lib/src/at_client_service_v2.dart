import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/auth/at_keys_source.dart';

abstract class AtClientServiceV2 {
  AtChops? atChops;
  Future<AtLoginResponse> login(AtLoginRequest atLoginRequest);
  Future<bool> isOnboarded({String? atSign});
  Future<bool> onboard(AtOnboardingRequest atOnboardingRequest);
}

class AtLoginRequest {
  String atSign;
  AtLoginRequest(this.atSign);
  AtClientPreference? preference;
  AtKeysFileData? atKeysData;
}

class AtLoginResponse {
  String atSign;
  AtLoginResponse(this.atSign);
  bool isSuccessful = false;
  AtClientException? atException;
}

class AtOnboardingRequest {
  String atSign;
  AtOnboardingRequest(this.atSign);
  AtClientPreference? preference;
  AtKeysFileData? atKeysData;
}

class AtOnboardingResponse {
  String atSign;
  AtOnboardingResponse(this.atSign);
  AtClientPreference? preference;
  AtKeysFileData? atKeysData;
}
