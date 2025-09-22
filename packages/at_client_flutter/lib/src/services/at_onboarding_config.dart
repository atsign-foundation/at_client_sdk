import 'package:at_client_flutter/at_client_flutter.dart' show AtClientPreference;
import 'package:at_client_flutter/src/services/at_onboarding_tutorial_service.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_app_constants.dart';
import 'package:flutter/material.dart';
import 'package:at_utils/at_logger.dart';

class AtOnboardingConfig {
  ///hides the references to webpages if set to true
  final bool hideReferences;

  ///hides the qr functionality if set to true
  final bool hideQrScan;

  ///The atClientPreference [required] to continue with the onboarding.
  final AtClientPreference atClientPreference;

  ///Default the plugin connects to [root.atsign.org] to perform onboarding.
  final String? domain;

  /// API authentication key for getting free atsigns
  final String? appAPIKey;

  /// Setting up [RootEnvironment] to **Staging** will use the staging environment for onboarding.
  ///
  ///```dart
  /// RootEnvironment.Staging
  ///```
  ///
  /// Setting up RootEnvironment to **Production** will use the production environment for onboarding.
  ///
  ///```dart
  /// RootEnvironment.Production
  ///```
  ///
  /// Setting up RootEnvironment to **Testing** will use the testing(docker) environment for onboarding.
  ///
  ///```dart
  /// RootEnvironment.Testing
  ///```
  ///
  /// **Note:**
  /// API Key is required when you set [rootEnvironment] to production.
  final AtSignLogger logger = AtSignLogger('At Onboarding Flutter');

  /// Provides option to choose whether user wants to share onboarded atSign details with other atApps.
  bool showPopupSharedStorage;

  final AtOnboardingTheme? theme;

  final AtOnboardingTutorialDisplay tutorialDisplay;

  AtOnboardingConfig({
    required this.atClientPreference,
    this.domain,
    this.appAPIKey,
    this.hideReferences = false,
    this.hideQrScan = false,
    this.tutorialDisplay = AtOnboardingTutorialDisplay.normal,
    this.theme,
    this.showPopupSharedStorage = false,
  });

  AtOnboardingConfig copyWith({
    bool? hideReferences,
    bool? hideQrScan,
    AtClientPreference? atClientPreference,
    String? domain,
    AtOnboardingTheme? theme,
    AtOnboardingTutorialDisplay? tutorialDisplay,
    String? appAPIKey,
    bool? showPopupSharedStorage,
  }) {
    return AtOnboardingConfig(
      hideReferences: hideReferences ?? this.hideReferences,
      hideQrScan: hideQrScan ?? this.hideQrScan,
      atClientPreference: atClientPreference ?? this.atClientPreference,
      domain: domain ?? this.domain,
      theme: theme ?? this.theme,
      tutorialDisplay: tutorialDisplay ?? this.tutorialDisplay,
      appAPIKey: appAPIKey ?? this.appAPIKey,
      showPopupSharedStorage:
          showPopupSharedStorage ?? this.showPopupSharedStorage,
    );
  }
}

class AtOnboardingTheme {
  ///set primary color for Onboarding
  final Color? primaryColor;
  final TextTheme? textTheme;

  AtOnboardingTheme({
    this.primaryColor,
    this.textTheme,
  });
}

