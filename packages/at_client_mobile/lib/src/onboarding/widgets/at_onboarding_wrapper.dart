// Wrapper to inject providers and theme.
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../notifiers/free_atsign_notifier.dart';
import '../notifiers/register_person_notifier.dart';
import '../notifiers/submit_registrar_otp_notifier.dart';
import '../pages/onboarding_page.dart';
import '../providers/at_client_preference_provider.dart';
import '../providers/free_atsign_notifier_provider.dart';
import '../providers/register_person_notifier_provider.dart';
import '../providers/submit_registrar_otp_notifier_provider.dart';

class AtOnboardingWrapper extends StatefulWidget {
  const AtOnboardingWrapper({
    required this.atClientPreference,
    this.themeData,
    super.key,
  });

  final AtClientPreference atClientPreference;
  final ThemeData? themeData;

  @override
  AtOnboardingWrapperState createState() => AtOnboardingWrapperState();
}

class AtOnboardingWrapperState extends State<AtOnboardingWrapper> {
  @override
  Widget build(BuildContext context) {
    return AtTheme(
      themeData: widget.themeData,
      child: AtClientPreferenceProvider(
        preferences: widget.atClientPreference,
        // TODO: Consider merging registrar related providers into one.
        child: FreeAtsignNotifierProvider(
          notifier: FreeAtsignNotifier(),
          child: RegisterPersonNotifierProvider(
            notifier: RegisterPersonNotifier(),
            child: SubmitRegistrarOtpNotifierProvider(
              notifier: SubmitRegistrarOtpNotifier(),
              child: OnboardingPage(),
            ),
          ),
        ),
      ),
    );
  }
}
