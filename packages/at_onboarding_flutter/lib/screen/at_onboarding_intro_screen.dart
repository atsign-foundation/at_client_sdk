import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_generate_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_home_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_reference_screen.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The introductory screen for the at onboarding process
/// [AtOnboardingIntroScreen] gives two options
/// 1. Already have an atSign - proceeds to home screen to upload atKey
/// 2. Get a free atSign - proceeds to generate free atSign
class AtOnboardingIntroScreen extends StatefulWidget {
  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingIntroScreen({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingIntroScreen> createState() => _AtOnboardingIntroScreenState();
}

class _AtOnboardingIntroScreenState extends State<AtOnboardingIntroScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      textTheme: widget.config.theme?.textTheme,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            AtOnboardingLocalizations.current.title_setting_up_your_atSign,
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          centerTitle: true,
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AtOnboardingDimens.borderRadius)),
              padding: const EdgeInsets.all(AtOnboardingDimens.paddingNormal),
              margin: const EdgeInsets.all(AtOnboardingDimens.paddingNormal),
              constraints: const BoxConstraints(
                maxWidth: 400,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RichText(
                    text: TextSpan(
                      text: AtOnboardingLocalizations.current.title_intro,
                      style: theme.textTheme.titleMedium,
                      children: <TextSpan>[
                        TextSpan(
                          text: AtOnboardingLocalizations.current.learn_more,
                          style: TextStyle(
                            fontSize: AtOnboardingDimens.fontLarge,
                            fontWeight: FontWeight.w500,
                            color: theme.primaryColor,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()..onTap = _showReferenceWebview,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  AtOnboardingPrimaryButton(
                    height: 48,
                    borderRadius: 24,
                    child: Text(
                      AtOnboardingLocalizations.current.already_have_an_atSign,
                    ),
                    onPressed: () {
                      _navigateToHomePage(true);
                    },
                  ),
                  const SizedBox(height: 16),
                  AtOnboardingSecondaryButton(
                    height: 48,
                    borderRadius: 24,
                    child: Text(
                      AtOnboardingLocalizations.current.get_free_atSign,
                    ),
                    onPressed: () {
                      _navigateToHomePage(false);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToHomePage(bool haveAtSign) async {
    AtOnboardingResult? result;

    if (!haveAtSign) {
      result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AtOnboardingGenerateScreen(
            config: widget.config,
            isFromIntroScreen: true,
          ),
        ),
      );
    } else {
      //Navigate user to screen to add new atsign
      result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (BuildContext context) {
            return AtOnboardingHomeScreen(
              config: widget.config,
              isFromIntroScreen: true,
            );
          },
        ),
      );
    }

    if (result != null) {
      if (!mounted) return;
      Navigator.pop(context, result);
    }
  }

  void _showReferenceWebview() {
    if (Platform.isAndroid || Platform.isIOS) {
      AtOnboardingReferenceScreen.push(
        context: context,
        title: AtOnboardingLocalizations.current.title_FAQ,
        url: AtOnboardingConstants.faqUrl,
        config: widget.config,
      );
    } else {
      launchUrl(
        Uri.parse(
          AtOnboardingConstants.faqUrl,
        ),
      );
    }
  }
}
