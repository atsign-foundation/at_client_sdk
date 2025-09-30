import 'dart:io';

import 'package:at_client_flutter/src/localizations/generated/l10n.dart';
import 'package:at_client_flutter/src/screen/at_onboarding_reference_screen.dart';
import 'package:at_client_flutter/src/services/at_onboarding_config.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_app_constants.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_dimens.dart';
import 'package:at_client_flutter/src/widgets/at_onboarding_button.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// [AtOnboardingInputAtSignScreen] allows to enter atSign for activation process
class AtOnboardingInputAtSignScreen extends StatefulWidget {
  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingInputAtSignScreen({
    super.key,
    required this.config,
  });

  @override
  State<AtOnboardingInputAtSignScreen> createState() => _AtOnboardingInputAtSignScreenState();
}

class _AtOnboardingInputAtSignScreenState extends State<AtOnboardingInputAtSignScreen> {
  final TextEditingController _atsignController = TextEditingController();

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
          actions: [
            IconButton(
              onPressed: _showReferenceWebview,
              icon: const Icon(Icons.help),
            ),
          ],
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
                  Text(
                    AtOnboardingLocalizations.current.activate_an_atSign,
                    style: const TextStyle(
                      fontSize: AtOnboardingDimens.fontLarge,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AtOnboardingLocalizations.current.enter_atSign_need_to_activate,
                    style: const TextStyle(
                      fontSize: AtOnboardingDimens.fontSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    enabled: true,
                    validator: (String? value) {
                      if ((value ?? '').isEmpty) {
                        return AtOnboardingLocalizations.current.msg_atSign_cannot_empty;
                      }
                      return null;
                    },
                    controller: _atsignController,
                    decoration: InputDecoration(
                      hintText: AtOnboardingConstants.atsignHintText,
                      prefix: Text(
                        '@',
                        style: TextStyle(color: theme.primaryColor),
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.primaryColor,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: AtOnboardingDimens.paddingSmall),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AtOnboardingPrimaryButton(
                    height: 48,
                    borderRadius: 24,
                    onPressed: _activateAtSign,
                    child: Center(
                      child: Text(
                        AtOnboardingLocalizations.current.activate,
                        style: const TextStyle(
                          fontSize: AtOnboardingDimens.fontLarge,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  void _activateAtSign() async {
    final String atSign = _atsignController.text;
    Navigator.pop(context, atSign);
  }
}
