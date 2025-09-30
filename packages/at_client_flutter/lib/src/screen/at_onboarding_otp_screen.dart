import 'dart:convert';
import 'dart:io';

import 'package:at_client_flutter/src/localizations/generated/l10n.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_app_constants.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart' show OnboardingUtil;
import 'package:at_client_flutter/src/screen/at_onboarding_accounts_screen.dart';
import 'package:at_client_flutter/src/screen/at_onboarding_reference_screen.dart';
import 'package:at_client_flutter/src/services/at_onboarding_config.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_dimens.dart';
import 'package:at_client_flutter/src/utils/at_onboarding_input_formatter.dart';
import 'package:at_client_flutter/src/widgets/at_onboarding_button.dart';
import 'package:at_client_flutter/src/widgets/at_onboarding_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:url_launcher/url_launcher.dart';

/// Represent the result of OTP-based onboarding for an atSign
class AtOnboardingOTPResult {
  /// The atSign associated with the OTP result
  String atSign;

  /// The secret value, if available
  String? secret;

  AtOnboardingOTPResult({
    required this.atSign,
    required this.secret,
  });
}

/// This screen is to perform OTP-based verification
class AtOnboardingOTPScreen extends StatefulWidget {
  /// Static method to navigate to this screen
  static Future<AtOnboardingOTPResult?> push({
    required BuildContext context,
    required String atSign,
    String? email,
    required bool hideReferences,
    required AtOnboardingConfig config,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AtOnboardingOTPScreen(
          atSign: atSign,
          email: email,
          hideReferences: hideReferences,
          config: config,
        ),
      ),
    );
  }

  /// The atSign to be displayed on the OTP screen
  final String atSign;

  /// The email address, if provided
  final String? email;

  /// If true, will hide webpage references
  final bool hideReferences;

  /// The configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingOTPScreen({
    Key? key,
    required this.atSign,
    this.email,
    required this.hideReferences,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingOTPScreen> createState() => _AtOnboardingOTPScreenState();
}

class _AtOnboardingOTPScreenState extends State<AtOnboardingOTPScreen> {
  final TextEditingController _pinCodeController = TextEditingController();
  final OnboardingUtil _onboardingUtil = OnboardingUtil();
  bool isVerifing = false;
  bool isResendingCode = false;

  String limitExceeded = 'limitExceeded';
  bool hasOTPError = false;

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
                      AtOnboardingLocalizations.current.enter_verification_code,
                      style: const TextStyle(
                        fontSize: AtOnboardingDimens.fontLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    PinCodeTextField(
                      controller: _pinCodeController,
                      animationType: AnimationType.none,
                      textCapitalization: TextCapitalization.characters,
                      appContext: context,
                      length: 4,
                      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      pinTheme: PinTheme(
                        selectedColor: hasOTPError ? Colors.red : theme.primaryColor,
                        activeColor: hasOTPError ? Colors.red : theme.primaryColor,
                        inactiveColor: hasOTPError ? Colors.red : Colors.grey[500],
                        shape: PinCodeFieldShape.box,
                        borderRadius: BorderRadius.circular(5),
                        fieldHeight: 48,
                        fieldWidth: MediaQuery.of(context).size.width > 400
                            ? 80
                            : (MediaQuery.of(context).size.width - 100) / 4,
                      ),
                      cursorHeight: 24,
                      cursorColor: Colors.grey,
                      // controller: _otpController,
                      keyboardType: TextInputType.text,
                      inputFormatters: <TextInputFormatter>[
                        AtOnboardingInputFormatter(),
                      ],
                      onChanged: (String value) {
                        setState(() {
                          hasOTPError = false;
                        });
                      },
                    ),
                    Text(
                      '${AtOnboardingLocalizations.current.verification_code_has_been_sent_to} ${widget.email ?? AtOnboardingLocalizations.current.your_registered_email}',
                      style: const TextStyle(
                        fontSize: AtOnboardingDimens.fontNormal,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AtOnboardingPrimaryButton(
                      height: 48,
                      borderRadius: 24,
                      width: double.infinity,
                      isLoading: isVerifing,
                      onPressed: _onVerifyPressed,
                      child: Text(
                        AtOnboardingLocalizations.current.verify_and_login,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AtOnboardingSecondaryButton(
                      height: 48,
                      borderRadius: 24,
                      width: double.infinity,
                      isLoading: isResendingCode,
                      onPressed: () {
                        _onResendPressed(theme);
                      },
                      child: Text(
                        AtOnboardingLocalizations.current.resend_code,
                      ),
                    ),
                    const SizedBox(height: 20),
                    RichText(
                      text: TextSpan(
                        children: <TextSpan>[
                          TextSpan(
                            text: AtOnboardingLocalizations.current.note,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: AtOnboardingDimens.fontSmall,
                              height: 1.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: AtOnboardingLocalizations.current.note_otp_content,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: AtOnboardingDimens.fontSmall,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
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

  Future<void> showErrorDialog(String? errorMessage) async {
    return AtOnboardingDialog.showError(context: context, message: errorMessage ?? '');
  }

  Future<void> _showSuccessDialog(ThemeData theme) {
    return showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: theme,
          child: AtOnboardingDialog(
            title: AtOnboardingLocalizations.current.notice,
            message: '${AtOnboardingLocalizations.current.verification_code_sent_to} ${widget.email}',
            actions: [
              AtOnboardingSecondaryButton(
                child: Text(
                  AtOnboardingLocalizations.current.btn_close,
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
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

  void _onVerifyPressed() async {
    if (_pinCodeController.text.length < 4) {
      return AtOnboardingDialog.showError(
        context: context,
        title: AtOnboardingLocalizations.current.notice,
        message: AtOnboardingLocalizations.current.enter_code,
      );
    }

    if ((widget.email ?? '').isEmpty) {
      isVerifing = true;
      setState(() {});
      final secret = await validatewithAtsign(widget.atSign, _pinCodeController.text, context);
      isVerifing = false;
      setState(() {});
      if (!mounted) return;
      if (secret.isNotEmpty) {
        Navigator.pop(
          context,
          AtOnboardingOTPResult(
            atSign: widget.atSign,
            secret: secret,
          ),
        );
      } else {
        setState(() {
          hasOTPError = true;
        });
      }
      return;
    } else {
      isVerifing = true;
      setState(() {});

      String? result = await validatePerson(widget.atSign, widget.email!, _pinCodeController.text);

      isVerifing = false;
      setState(() {});
      if (result != null && result != limitExceeded) {
        List<String> params = result.split(':');
        if (!mounted) return;
        Navigator.pop(
          context,
          AtOnboardingOTPResult(
            atSign: params[0],
            secret: params[1],
          ),
        );
      }
    }
  }

  ///With activate account
  Future<String> validatewithAtsign(String atsign, String otp, BuildContext context,
      {bool isConfirmation = false}) async {
    dynamic data;
    String? cramSecret;

    dynamic response = await _onboardingUtil.(atsign, otp);
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);
      //check for the atsign list and display them.
      if (data['message'] == 'Verified') {
        cramSecret = data['cramkey'];
      } else {
        String errorMessage = data['message'];
        if (!context.mounted) return '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(errorMessage),
          ),
        );
      }
    } else {
      data = response.body;
      data = jsonDecode(data);
      String errorMessage = data['message'];
      if (!context.mounted) return '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(errorMessage),
        ),
      );
    }
    return cramSecret ?? '';
  }

  Future<bool> loginWithAtsign(String atsign, BuildContext context) async {
    dynamic data;
    bool status = false;

    dynamic response = await _onboardingUtil.postRequest(
    AtOnboardingConstants.apiEndPoint,
    AtOnboardingConstants.authWithAtsign,
    data);
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);

      status = true;
      // atsign = data['data']['atsign'];
    } else {
      data = response.body;
      data = jsonDecode(data);
      String errorMessage = data['message'];
      await showErrorDialog(errorMessage);
    }
    return status;
  }

  ///With new account
  void _onResendPressed(ThemeData theme) async {
    if ((widget.email ?? '').isEmpty) {
      setState(() {
        isResendingCode = true;
        hasOTPError = false;
      });

      final result = await loginWithAtsign(widget.atSign, context);
      if (result) {
        _pinCodeController.text = '';
      }

      setState(() {
        isResendingCode = false;
      });
      return;
    }

    setState(() {
      isResendingCode = true;
      hasOTPError = false;
    });
    // String atsign;
    dynamic response = await _onboardingUtil.registerAtSign(widget.atSign, widget.email!);
    if (response.statusCode == 200) {
      //Success
      _pinCodeController.text = '';
      _showSuccessDialog(theme);
      // status = true;
      // atsign = data['data']['atsign'];
    } else {
      //Error
      final data = jsonDecode(response.body);
      String errorMessage = data['message'];
      // if (errorMessage.contains('Invalid Email')) {
      //   oldEmail = email;
      // }
      if (errorMessage.contains('maximum number of free atSigns')) {
        await showlimitDialog();
      } else {
        await showErrorDialog(errorMessage);
      }
    }
    setState(() {
      isResendingCode = false;
    });
  }

  Future<String?> validatePerson(String atsign, String email, String? otp, {bool isConfirmation = false}) async {
    dynamic data;
    String? cramSecret;
    List<String> atsigns = <String>[];
    // String atsign;

    dynamic response = await _onboardingUtil.validateOtp(atsign, email, otp!, confirmation: isConfirmation.toString());
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);
      //check for the atsign list and display them.
      if (data['data'] != null && data['data'].length == 2 && data['status'] != 'error') {
        dynamic responseData = data['data'];
        atsigns.addAll(List<String>.from(responseData['atsigns']));

        if (responseData['newAtsign'] == null) {
          if (!mounted) return null;
          final value = await Navigator.push(
            context,
            MaterialPageRoute<String?>(
              builder: (_) => AtOnboardingAccountsScreen(
                atsigns: atsigns,
                message: responseData['message'],
                config: widget.config,
              ),
            ),
          );
          if (value != null) {
            if (!mounted) return null;
            Navigator.pop(context, AtOnboardingOTPResult(atSign: value, secret: null));
          }
          return null;
        }
        //displays list of atsign along with newAtsign
        else {
          if (!mounted) return null;
          final value = await Navigator.push(
            context,
            MaterialPageRoute<String?>(
              builder: (_) => AtOnboardingAccountsScreen(
                atsigns: atsigns,
                newAtsign: responseData['newAtsign']!,
                config: widget.config,
              ),
            ),
          );
          if (value == responseData['newAtsign']) {
            cramSecret = await validatePerson(value as String, email, otp, isConfirmation: true);
            return cramSecret;
          } else {
            if (value != null) {
              if (!mounted) return null;
              Navigator.pop(context, AtOnboardingOTPResult(atSign: value, secret: null));
            }
            return null;
          }
        }
      } else if (data['status'] != 'error') {
        cramSecret = data['cramkey'];
      } else {
        String? errorMessage = data['message'];
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(errorMessage ?? ''),
          ),
        );
      }
      // atsign = data['data']['atsign'];
    } else {
      data = response.body;
      data = jsonDecode(data);
      String? errorMessage = data['message'];
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(errorMessage ?? ''),
        ),
      );
    }
    return cramSecret;
  }

  Future<bool> registerPersona(String atsign, String email, BuildContext context, {String? oldEmail}) async {
    dynamic data;
    bool status = false;
    // String atsign;
    dynamic response = await _onboardingUtil.registerAtSign(atsign, email, oldEmail: oldEmail);
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);
      status = true;
    } else {
      data = response.body;
      data = jsonDecode(data);
      String errorMessage = data['message'];
      if (errorMessage.contains('Invalid Email')) {
        oldEmail = email;
      }
      if (errorMessage.contains('maximum number of free atSigns')) {
        await showlimitDialog();
      } else {
        await showErrorDialog(errorMessage);
      }
    }
    return status;
  }

  Future<AlertDialog?> showlimitDialog() async {
    final theme = Theme.of(context).copyWith(
      primaryColor: widget.config.theme?.primaryColor,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: widget.config.theme?.primaryColor,
          ),
    );

    return showDialog<AlertDialog>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  style: const TextStyle(color: Colors.black, fontSize: 16, letterSpacing: 0.5),
                  text: AtOnboardingLocalizations.current.msg_maximum_atSign_prev,
                ),
                TextSpan(
                    text: 'https://my.atsign.com',
                    style: TextStyle(
                        fontSize: 16,
                        color: theme.primaryColor,
                        letterSpacing: 0.5,
                        decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        String url = 'https://my.atsign.com';
                        if (!widget.hideReferences && await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(Uri.parse(url));
                        }
                      }),
                TextSpan(
                  text: AtOnboardingLocalizations.current.msg_maximum_atSign_next,
                  style: const TextStyle(color: Colors.black, fontSize: 16, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                AtOnboardingLocalizations.current.btn_close,
                style: TextStyle(
                  color: theme.primaryColor,
                ),
              ),
            )
          ],
        );
      },
    );
  }
}
