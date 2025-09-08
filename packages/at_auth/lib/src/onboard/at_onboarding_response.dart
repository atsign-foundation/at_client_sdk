import 'package:at_auth/src/keys/at_keys.dart';

class AtOnboardingResponse {
  String atSign;
  String? enrollmentId;
  AtOnboardingResponse(this.atSign);
  bool isSuccessful = false;
  AtKeys? atAuthKeys;

  @override
  String toString() {
    return 'AtOnboardingResponse{atSign: $atSign, enrollmentId: $enrollmentId, isSuccessful: $isSuccessful}';
  }
}
