import 'package:at_auth/src/keys/at_keys.dart';

/// Represents and authentication response of an atSign.
class AtAuthResponse {
  /// The atSign for authentication
  String atSign;

  /// Represents if an atSign is successfully authenticated.
  bool isSuccessful = false;

  /// The keys for authentication of an atSign.
  AtKeys? atAuthKeys;

  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(this.atSign);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
