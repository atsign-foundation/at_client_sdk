import 'dart:convert';
import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_result.dart';
import 'package:at_onboarding_flutter/localizations/generated/l10n.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_backup_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_otp_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_reference_screen.dart';
import 'package:at_onboarding_flutter/services/at_onboarding_config.dart';
import 'package:at_onboarding_flutter/services/free_atsign_service.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_app_constants.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_error_util.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_response_status.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_dialog.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// This screen is for activating an atSign during onboarding process
class AtOnboardingActivateScreen extends StatefulWidget {
  /// If true, will hide webpage references
  final bool hideReferences;

  /// The atSign to be activated
  final String? atSign;

  /// The configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingActivateScreen({
    Key? key,
    required this.hideReferences,
    this.atSign,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingActivateScreen> createState() =>
      _AtOnboardingActivateScreenState();
}

class _AtOnboardingActivateScreenState
    extends State<AtOnboardingActivateScreen> {
  final FreeAtsignService _freeAtsignService = FreeAtsignService();
  final OnboardingService _onboardingService = OnboardingService.getInstance();

  bool isVerifing = false;
  ServerStatus? atSignStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      loginWithAtsignAfterReset(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      textTheme: widget.config.theme?.textTheme,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return AbsorbPointer(
      absorbing: isVerifing,
      child: Theme(
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
                padding: const EdgeInsets.all(AtOnboardingDimens.paddingNormal),
                margin: const EdgeInsets.all(AtOnboardingDimens.paddingNormal),
                constraints: const BoxConstraints(
                  maxWidth: 400,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AtSyncIndicator(
                      color: theme.primaryColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AtOnboardingLocalizations
                          .current.msg_wait_fetching_atSign,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  //It will validate the person with atsign, email and the OTP.
  //If the validation is successful, it will return a cram secret for the user to login
  void loginWithAtsignAfterReset(BuildContext context) async {
    String? atsign = widget.atSign ?? _onboardingService.currentAtsign;
    atsign ??= await _onboardingService.getAtSign();
    if (atsign != null) {
      atsign = atsign.split('@').last;
    }

    // check if atSign already activated
    AtSignStatus? atsignStatus =
        await _onboardingService.checkAtsignStatus(atsign: atsign);
    if (atsignStatus == AtSignStatus.activated) {
      bool isPaired = await _onboardingService.isExistingAtsign(atsign);
      await showErrorDialog(
        isPaired
            ? AtOnboardingLocalizations.current.error_atSign_logged
            : AtOnboardingLocalizations.current.error_atSign_activated,
      );
      return;
    }

    dynamic data;

    dynamic response = await _freeAtsignService
        .loginWithAtsign(atsign ?? (widget.atSign ?? ''));
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);

      AtOnboardingOTPResult? result;
      if (context.mounted) {
        result = await AtOnboardingOTPScreen.push(
          context: context,
          atSign: atsign ?? (widget.atSign ?? ''),
          hideReferences: false,
          config: widget.config,
        );
      }

      if (result != null) {
        String? secret = result.secret?.split(':').last ?? '';
        _processSharedSecret(atsign: result.atSign, secret: secret);
      } else {
        if (!context.mounted) return;
        Navigator.pop(context, AtOnboardingResult.cancelled());
      }
    } else {
      data = response.body;
      data = jsonDecode(data);
      String errorMessage = data['message'];
      await showErrorDialog(errorMessage);
    }
  }

  Future<void> showErrorDialog(String? errorMessage) async {
    return AtOnboardingDialog.showError(
      context: context,
      title: AtOnboardingLocalizations.current.notice,
      message: errorMessage ?? '',
      onCancel: () {
        Navigator.of(context).pop();
      },
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

  Future<void> _processSharedSecret({
    required String atsign,
    required String secret,
  }) async {
    try {
      atsign = atsign.startsWith('@') ? atsign : '@$atsign';

      bool isExist = await _onboardingService.isExistingAtsign(atsign);
      if (isExist) {
        await _showAlertDialog(
            AtOnboardingErrorToString().pairedAtsign(atsign));
        return;
      }

      //Delay for waiting for ServerStatus change to teapot when activating an atsign
      await Future.delayed(const Duration(seconds: 10));

      _onboardingService.setAtClientPreference =
          widget.config.atClientPreference;

      String? previousAtsign = _onboardingService.currentAtsign;
      _onboardingService.setAtsign = atsign;
      final authResponse = await _onboardingService.onboard(
        cramSecret: secret,
      );

      int round = 1;
      var atSignStatus =
          await _onboardingService.checkAtSignServerStatus(atsign);
      while (atSignStatus != ServerStatus.activated) {
        if (round > 10) {
          break;
        }

        await Future.delayed(const Duration(seconds: 3));
        round++;
        atSignStatus = await _onboardingService.checkAtSignServerStatus(atsign);
        debugPrint("currentAtSignStatus: $atSignStatus");
      }

      if (!authResponse || atSignStatus == ServerStatus.teapot) {
        _onboardingService.setAtsign = previousAtsign;
      }

      if (authResponse) {
        if (atSignStatus == ServerStatus.teapot) {
          await _showAlertDialog(
            AtOnboardingLocalizations.current.msg_atSign_unreachable,
          );
          return;
        }

        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AtOnboardingBackupScreen(
              config: widget.config,
            ),
          ),
        );

        if (!mounted) return;
        Navigator.pop(context, AtOnboardingResult.success(atsign: atsign));
      } else {
        await showErrorDialog(
          AtOnboardingLocalizations.current.title_session_expired,
        );
      }
    } catch (e) {
      if (e == AtOnboardingResponseStatus.authFailed) {
        await _showAlertDialog(
          e,
          title: AtOnboardingLocalizations.current.error_authenticated_failed,
        );
      } else if (e == AtOnboardingResponseStatus.serverNotReached) {
        await _showAlertDialog(
          e,
          title: AtOnboardingLocalizations.current.msg_atSign_unreachable,
        );
      } else if (e == AtOnboardingResponseStatus.timeOut) {
        await _showAlertDialog(
          e,
          title: AtOnboardingLocalizations.current.msg_response_time_out,
        );
      }
    }
  }

  Future<void> _showAlertDialog(dynamic errorMessage, {String? title}) async {
    String? messageString =
        AtOnboardingErrorToString().getErrorMessage(errorMessage);

    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return AtOnboardingDialog.showError(
      context: context,
      title: title,
      message: messageString,
      themeData: theme,
      onCancel: () {
        Navigator.pop(context);
      },
    );
  }
}
