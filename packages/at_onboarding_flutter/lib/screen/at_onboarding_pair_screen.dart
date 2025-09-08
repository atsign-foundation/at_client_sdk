import 'dart:convert';
import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_otp_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_reference_screen.dart';
import 'package:at_onboarding_flutter/services/free_atsign_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_strings.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// This screen is for pairing an atSign during onboarding process
class AtOnboardingPairScreen extends StatefulWidget {
  /// The atSign to be paired
  final String atSign;

  /// If true, will hide webpage references.
  final bool hideReferences;

  /// A function to be called when the pairing is successful
  /// It takes [atSign] and [secret] as required parameters
  final Function({
    required String atSign,
    required String secret,
  })? onGenerateSuccess;

  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  const AtOnboardingPairScreen({
    Key? key,
    required this.atSign,
    required this.hideReferences,
    required this.onGenerateSuccess,
    required this.config,
  }) : super(key: key);

  @override
  State<AtOnboardingPairScreen> createState() => _AtOnboardingPairScreenState();
}

class _AtOnboardingPairScreenState extends State<AtOnboardingPairScreen> {
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FreeAtsignService _freeAtsignService = FreeAtsignService();

  bool isParing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.unfocus();
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
      absorbing: isParing,
      child: Theme(
        data: theme,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              AtOnboardingLocalizations.current.title_setting_up_your_atSign,
            ),
            centerTitle: true,
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AtOnboardingLocalizations.current.enter_your_email_address,
                      style: const TextStyle(
                        fontSize: AtOnboardingDimens.fontLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextFormField(
                      enabled: true,
                      focusNode: _focusNode,
                      validator: (String? value) {
                        if ((value ?? '').isEmpty) {
                          return AtOnboardingLocalizations.current.msg_atSign_cannot_empty;
                        }
                        return null;
                      },
                      controller: _emailController,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(80),
                        // This inputFormatter function will convert all the input to lowercase.
                        TextInputFormatter.withFunction((TextEditingValue oldValue, TextEditingValue newValue) {
                          return newValue.copyWith(
                            text: newValue.text.toLowerCase(),
                            selection: newValue.selection,
                          );
                        })
                      ],
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        fillColor: Colors.blueAccent,
                        errorStyle: const TextStyle(fontSize: 12),
                        prefixStyle: TextStyle(color: theme.primaryColor, fontSize: 15),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: theme.primaryColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.grey[500]!,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AtOnboardingDimens.paddingSmall),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AtOnboardingLocalizations.current.note_pair_content,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AtOnboardingDimens.fontNormal,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AtOnboardingPrimaryButton(
                      height: 48,
                      borderRadius: 24,
                      isLoading: isParing,
                      onPressed: _onSendCodePressed,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AtOnboardingLocalizations.current.send_code,
                            style: const TextStyle(
                              fontSize: AtOnboardingDimens.fontLarge,
                            ),
                          ),
                          const Icon(Icons.arrow_right_alt_rounded)
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

  void _showReferenceWebview() {
    if (Platform.isAndroid || Platform.isIOS) {
      AtOnboardingReferenceScreen.push(
        context: context,
        title: AtOnboardingLocalizations.current.title_FAQ,
        url: AtOnboardingStrings.faqUrl,
        config: widget.config,
      );
    } else {
      launchUrl(
        Uri.parse(
          AtOnboardingStrings.faqUrl,
        ),
      );
    }
  }

  void _onSendCodePressed() async {
    _focusNode.unfocus();
    if (_emailController.text.isNotEmpty) {
      isParing = true;
      setState(() {});
      bool status = false;
      status = await registerPersona(widget.atSign, _emailController.text, context);
      isParing = false;
      setState(() {});
      if (status) {
        _showOTPScreen();
      } else {
        if (!mounted) return;
        AtOnboardingDialog.showError(
          context: context,
          message: AtOnboardingLocalizations.current.error_please_enter_email,
          onCancel: () {
            Navigator.pop(context);
          },
        );
      }
    } else {
      return AtOnboardingDialog.showError(
        context: context,
        message: AtOnboardingLocalizations.current.error_enter_valid_email,
      );
    }
  }

  Future<bool> registerPersona(String atsign, String email, BuildContext context, {String? oldEmail}) async {
    dynamic data;
    bool status = false;
    // String atsign;
    dynamic response = await _freeAtsignService.registerPerson(atsign, email, oldEmail: oldEmail);
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
        if (!context.mounted) return status;
        AtOnboardingDialog.showError(context: context, message: errorMessage);
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
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
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
                style: TextStyle(color: theme.primaryColor),
              ),
            )
          ],
        );
      },
    );
  }

  void _showOTPScreen() async {
    final String atSign = widget.atSign;
    final String email = _emailController.text;
    final result = await AtOnboardingOTPScreen.push(
      context: context,
      atSign: atSign,
      email: email,
      hideReferences: false,
      config: widget.config,
    );
    if (result != null && result.secret != null) {
      if (!mounted) return;
      Navigator.pop(context);
      widget.onGenerateSuccess?.call(atSign: result.atSign, secret: result.secret ?? '');
    } else if (result != null) {
      dynamic data;
      //User choose a difference atsign to onboard
      dynamic response = await _freeAtsignService.loginWithAtsign(result.atSign);
      if (response.statusCode == 200) {
        data = response.body;
        data = jsonDecode(data);
      } else {
        data = response.body;
        data = jsonDecode(data);
        String errorMessage = data['message'];
        if (!mounted) return;
        AtOnboardingDialog.showError(context: context, message: errorMessage);
      }
      if (!mounted) return;
      final result2 = await AtOnboardingOTPScreen.push(
        context: context,
        atSign: result.atSign,
        hideReferences: false,
        config: widget.config,
      );
      if (result2 != null) {
        if (!mounted) return;
        Navigator.pop(context);
        widget.onGenerateSuccess?.call(atSign: result2.atSign, secret: result2.secret ?? '');
      } else {
        if (!mounted) return;
        Navigator.pop(context);
      }
    }
  }
}
