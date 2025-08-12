import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_result.dart';
import 'package:at_onboarding_flutter/localizations/generated/l10n.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_activate_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_intro_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_reset_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_start_screen.dart';
import 'package:at_onboarding_flutter/services/at_onboarding_config.dart';
import 'package:at_onboarding_flutter/services/at_onboarding_theme.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:flutter/material.dart';

class AtOnboarding {
  /// Using this function to get onboard atsing.
  ///
  /// @param context The build context.
  /// @param config The config for the onboard
  /// @param isSwitchingAtsign True - alway show UI for add new atsign. False - check onboard if existing atsing. Default is false
  /// @param atsign The atsign name when change the primary atsign.
  ///
  /// Return [AtOnboardingResult]
  static Future<AtOnboardingResult> onboard({
    required BuildContext context,
    required AtOnboardingConfig config,
    bool isSwitchingAtsign = false,
    String? atsign,
  }) async {
    AtOnboardingConstants.setApiKey(config.appAPIKey ??
        (AtOnboardingConstants.rootEnvironment.apikey ?? ''));
    AtOnboardingConstants.rootDomain =
        config.domain ?? AtOnboardingConstants.rootEnvironment.domain;

    /// Initial Setup
    await _initialSetup(context);

    /// user sharing is not supported on Android, iOS and Linux.
    if (Platform.isAndroid || Platform.isIOS || Platform.isLinux) {
      config.showPopupSharedStorage = false;
    }

    if (config.theme == null) {
      final defaultConfig = config.copyWith(
        theme: AtOnboardingTheme(),
      );
      config = defaultConfig;
    }

    if (!isSwitchingAtsign || (atsign ?? '').trim().isNotEmpty) {
      if ((atsign ?? '').trim().isNotEmpty) {
        await changePrimaryAtsign(atsign: atsign!);
      }

      //Check if existing an atsign => return onboard success
      // ignore: use_build_context_synchronously
      AtOnboardingResult? result;
      if (context.mounted) {
        result = await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AtOnboardingStartScreen(
            config: config,
          ),
        );
      }

      if (result is AtOnboardingResult) {
        return result;
      }

      return AtOnboardingResult.cancelled();
    }

    if (context.mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) {
            return AtOnboardingIntroScreen(
              config: config,
            );
          },
        ),
      );

      if (result is AtOnboardingResult) {
        //Update primary atsign after onboard success
        if (result.status == AtOnboardingResultStatus.success &&
            result.atsign != null) {
          await changePrimaryAtsign(atsign: result.atsign!);
        }
        return result;
      }
    }

    return AtOnboardingResult.cancelled();
  }

  static Future<AtOnboardingResult> activateAccount({
    required BuildContext context,
    required AtOnboardingConfig config,
  }) async {
    /// Initial Setup
    await _initialSetup(context);

    if (context.mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) {
            return AtOnboardingActivateScreen(
              hideReferences: false,
              config: config,
            );
          },
        ),
      );

      if (result is AtOnboardingResult) {
        return result;
      }
    }

    return AtOnboardingResult.cancelled();
  }

  static Future<bool> changePrimaryAtsign({required String atsign}) async {
    return await OnboardingService.getInstance()
        .changePrimaryAtsign(atsign: atsign);
  }

  static Future<AtOnboardingResetResult> reset({
    required BuildContext context,
    required AtOnboardingConfig config,
  }) async {
    /// Initial Setup
    await _initialSetup(context);

    if (context.mounted) {
      final result = await Navigator.push(context,
          MaterialPageRoute(builder: (BuildContext context) {
        return AtOnboardingResetScreen(config: config);
      }));

      if (result is AtOnboardingResetResult) {
        return result;
      }
    }

    return AtOnboardingResetResult.cancelled;
  }

  Future<bool> enableUsingSharedStorage() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isLinux) {
      throw UnsupportedError('user sharing not supported');
    }

    final result =
        await OnboardingService.getInstance().enableUsingSharedStorage();
    return result;
  }

  Future<bool> disableUsingSharedStorage() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isLinux) {
      throw UnsupportedError('user sharing not supported');
    }

    final result =
        await OnboardingService.getInstance().disableUsingSharedStorage();
    return result;
  }

  static Future<void> _initialSetup(BuildContext context) async {
    /// Configure Localization
    const AppLocalizationDelegate _delegate = AppLocalizationDelegate();
    final currentLocal = Localizations.localeOf(context);
    if (_delegate.isSupported(currentLocal)) {
      _delegate.load(currentLocal);
    } else {
      _delegate.load(const Locale.fromSubtags(languageCode: 'en'));
    }
  }
}
