import 'package:at_auth/at_auth.dart';

/// Represents and authentication response of an atSign.
class AtAuthResponse {
  /// The atSign for authentication
  String atSign;

  /// Represents if an atSign is successfully authenticated.
  bool isSuccessful = false;

  /// The enrollmentId for APKAM authentication
  String? enrollmentId;

  /// The keys for authentication of an atSign.
  AtAuthKeys? atAuthKeys;

  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(this.atSign);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, enrollmentId: $enrollmentId, isSuccessful: $isSuccessful}';
  }
}
