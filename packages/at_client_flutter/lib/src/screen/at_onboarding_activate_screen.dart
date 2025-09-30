import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart' show OnboardingUtil;
import 'package:at_client_flutter/src/at_onboarding_status.dart';
import 'package:at_client_flutter/src/localizations/generated/l10n.dart';
import 'package:at_client_flutter/src/screen/at_onboarding_backup_screen.dart';
import 'package:at_client_flutter/src/screen/at_onboarding_otp_screen.dart';
import 'package:at_client_flutter/src/screen/at_onboarding_reference_screen.dart';
import 'package:at_client_flutter/src/services/at_onboarding_config.dart';
import 'package:at_client_flutter/src/services/at_onboarding_service.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_app_constants.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_dimens.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_error_util.dart';
import 'package:at_client_flutter/src/widgets/at_onboarding_dialog.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// This screen is for activating an atSign during onboarding process
class AtOnboardingActivateScreen extends ConsumerStatefulWidget {
  /// If true, will hide webpage references
  final bool hideReferences;

  /// The atSign to be activated
  final String? atSign;

  /// The configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingActivateScreen({
    super.key,
    required this.hideReferences,
    this.atSign,
    required this.config,
  });

  @override
  ConsumerState<AtOnboardingActivateScreen> createState() =>
      _AtOnboardingActivateScreenState();
}

class _AtOnboardingActivateScreenState
    extends ConsumerState<AtOnboardingActivateScreen> {
  final OnboardingUtil _onboardingUtil = OnboardingUtil();
  late AtOnboardingService _onboardingService;
  bool isVerifing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      loginWithAtsignAfterReset(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    _onboardingService = ref.watch(atOnboardingService.notifier);
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
    String? atsign = widget.atSign;
    atsign ??= _onboardingService.getAtSign();

    // check if atSign already activated
    ServerStatus? atsignStatus =
        await _onboardingService.checkAtsignStatus(atsign);
    if (atsignStatus == ServerStatus.activated) {
      bool isPaired = await _onboardingService.isExistingAtsign(atsign);
      await showErrorDialog(
        isPaired
            ? AtOnboardingLocalizations.current.error_atSign_logged
            : AtOnboardingLocalizations.current.error_atSign_activated,
      );
      return;
    }

    dynamic data;
    dynamic response = await _onboardingUtil.postRequest(
        AtOnboardingConstants.apiEndPoint,
        AtOnboardingConstants.authWithAtsign,
        data);
    
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);

      AtOnboardingOTPResult? result;
      if (context.mounted) {
        result = await AtOnboardingOTPScreen.push(
          context: context,
          atSign: atsign,
          hideReferences: false,
          config: widget.config,
        );
      }

      if (result != null) {
        String? secret = result.secret?.split(':').last ?? '';
        _processSharedSecret(atsign: result.atSign, secret: secret);
      } else {
        if (!context.mounted) return;
        Navigator.pop(context, AtOnboardingStatusCancelled());
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
      var atClientPreference = widget.config.atClientPreference;
      _onboardingService.setAtClientPreference(atClientPreference);

      String? previousAtsign = _onboardingService.getAtSign();
      AtOnboardingRequest atAuthRequest = AtOnboardingRequest(atsign)
        ..rootDomain = AtRootDomain(
            atClientPreference.rootDomain, atClientPreference.rootPort);

      final authResponse =
          await _onboardingService.onboard(atAuthRequest, cramSecret: secret);


      if (authResponse == AtOnboardingStatus.serverNotReached  ) {
        _onboardingService.setAtsign(previousAtsign);
        await _showAlertDialog(
            AtOnboardingLocalizations.current.msg_atSign_unreachable,
          );
          return;
      }
      if (authResponse == AtOnboardingStatus.authSuccess) {
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
        Navigator.pop(context, AtOnboardingStatusSuccess());
      } else {
        await showErrorDialog(
          AtOnboardingLocalizations.current.title_session_expired,
        );
      }
    } catch (e) {
      if (e == AtOnboardingStatus.authFailed) {
        await _showAlertDialog(
          e,
          title: AtOnboardingLocalizations.current.error_authenticated_failed,
        );
      } else if (e == AtOnboardingStatus.serverNotReached) {
        await _showAlertDialog(
          e,
          title: AtOnboardingLocalizations.current.msg_atSign_unreachable,
        );
      } else if (e == AtOnboardingStatus.timeOut) {
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
