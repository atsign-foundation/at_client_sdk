import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

Future<void> main() async {
  AtOnboardingPreference onboardingPreference = AtOnboardingPreference()
    ..namespace =
        'your_namespace' // unique identifier that can be used to identify data from your app
    ..cramSecret = '<your cram secret>';
  AtOnboardingService? onboardingService =
      AtOnboardingServiceImpl('your atsign here', onboardingPreference);
  await onboardingService.onboard(); // when authenticating
  AtLookUp? atLookUp = onboardingService.atLookUp;
  AtClient? atClient = onboardingService.atClient;
  print(atClient?.getKeys());
  print(await atLookUp?.scan(regex: 'publickey'));
  await onboardingService.close();
}
