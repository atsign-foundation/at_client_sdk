import 'package:at_auth/at_auth.dart';

// NOTE: This is incomplete and just a placeholder for now.
// NO Flutter dependencies!

abstract class OnboardingService {
  // This will use the keys and previously set config to construct a AtAuthRequest.
  Future<void> authenticate(AtAuthKeys keys);

  RegistrarServiceBase get registrarService;

  // ----- Enrollment -----
  Future<void> enroll({
    required String otp,
    required String deviceName,
    required String appName,
    required Map<String, String> namespace,
  });

  Future<void> getExistingEnrollmentRequest();

  // TODO: Update return type to be something meaningful
  Stream<void> getEnrollmentStatus();
}
