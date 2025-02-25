import 'package:at_auth/at_auth.dart';

class OnboardingServiceImpl {
  OnboardingServiceImpl(
    this.atAuth,
    this.registrarService,
  );

  final AtAuth atAuth;
  final RegistrarServiceBase registrarService;

  Future<AtAuthResponse> authenticate(AtAuthRequest authRequest) {
    return atAuth.authenticate(authRequest);
  }

  Future<AtOnboardingResponse> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret,
  ) async {
    return atAuth.onboard(atOnboardingRequest, cramSecret);
  }

  Future<bool> isOnboarded() async {
    throw UnimplementedError();
  }

  // ----- Enrollment -----
  Future<void> enroll({
    required String otp,
    required String deviceName,
    required String appName,
    required Map<String, String> namespace,
  }) async {}
}
