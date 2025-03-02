import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/src/onboarding/models/onboarding_config.dart';
import 'package:at_client_mobile/src/theme/at_theme.dart';
import 'package:flutter/material.dart';

import 'models/onboarding_result.dart';
import 'widgets/at_onboarding_wrapper.dart';

class AtOnboarding {
  /// Onboards and authenticates the user with their atServer.
  static Future<AtOnboardingResult> onboard({
    required BuildContext context,
    required AtClientPreference atClientPreference,
    OnboardingConfig? onboardingConfig,
    ThemeData? themeData,
  }) async {
    AtOnboardingWrapper wrapperBuilder(BuildContext context) {
      return AtOnboardingWrapper(
        atClientPreference: atClientPreference,
        themeData: themeData,
      );
    }

    Future<AtOnboardingResult?> showOnboardingSheet() async {
      return await showModalBottomSheet<AtOnboardingResult>(
        context: context,
        routeSettings: RouteSettings(name: 'at-onboarding-bottom-sheet'),
        isScrollControlled: true,
        useRootNavigator: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        builder: (_) {
          return Material(
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: AnimatedSize(
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Builder(
                      builder: wrapperBuilder,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    Future<AtOnboardingResult?> showOnboardingModal() async {
      return await showDialog<AtOnboardingResult>(
        context: context,
        routeSettings: RouteSettings(name: 'at-onboarding-modal'),
        useRootNavigator: true,
        builder: (context) {
          return AtTheme(
            themeData: themeData,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 700,
                ),
                child: Dialog(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: null,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Builder(
                          builder: wrapperBuilder,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    Size screenSize = MediaQuery.of(context).size;
    // On mobile, show bottom sheet
    // On large screens, show a modal.
    AtOnboardingResult? result;
    if (screenSize.width < 600 || onboardingConfig?.dialogType == DialogType.sheet) {
      result = await showOnboardingSheet();
    } else {
      result = await showOnboardingModal();
    }
    return result ?? const AtOnboardingResult.cancelled();
  }
}
