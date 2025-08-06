import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_server_status/at_server_status.dart';

class OnboardingServiceImplOverride extends AtOnboardingServiceImpl {
  OnboardingServiceImplOverride(
      atsign, AtOnboardingPreference atOnboardingPreference)
      : super(atsign, atOnboardingPreference);

  AtStatus status = AtStatus()
    ..rootStatus = RootStatus.found
    ..serverStatus = ServerStatus.ready
    ..atSignStatus = AtSignStatus.teapot;

  @override
  Future<AtStatus> getServerStatus() {
    print('[Test] Using overrided getServerStatus()');
    print('[Test] Returning ${status.atSignStatus}');
    return Future.value(status);
  }
}
