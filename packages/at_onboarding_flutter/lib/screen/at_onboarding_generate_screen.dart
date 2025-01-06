import 'dart:convert';
import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_backup_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_home_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_pair_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_reference_screen.dart';
import 'package:at_onboarding_flutter/services/at_onboarding_tutorial_service.dart';
import 'package:at_onboarding_flutter/services/free_atsign_service.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_dimens.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_error_util.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_response_status.dart';
import 'package:at_onboarding_flutter/utils/at_onboarding_strings.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_dialog.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:url_launcher/url_launcher.dart';

/// This screen is for generating atKey
class AtOnboardingGenerateScreen extends StatefulWidget {
  /// Callback function to be called when atKey generation is successful
  /// It receives the generated atSign and its corresponding secret
  final Function({
    required String atSign,
    required String secret,
  })? onGenerateSuccess;

  /// Configuration for the onboarding process
  final AtOnboardingConfig config;

  /// Indicates whether the screen is navigated from the intro screen
  final bool isFromIntroScreen;

  const AtOnboardingGenerateScreen({
    Key? key,
    required this.config,
    this.onGenerateSuccess,
    this.isFromIntroScreen = false,
  }) : super(key: key);

  @override
  State<AtOnboardingGenerateScreen> createState() =>
      _AtOnboardingGenerateScreenState();
}

class _AtOnboardingGenerateScreenState
    extends State<AtOnboardingGenerateScreen> {
  final TextEditingController _atsignController = TextEditingController();
  final FreeAtsignService _freeAtsignService = FreeAtsignService();
  late AtSyncDialog _inprogressDialog;
  bool _isGenerating = false;

  final OnboardingService _onboardingService = OnboardingService.getInstance();
  final AtSignLogger _logger = AtSignLogger('At Onboarding');

  GlobalKey keyGenerateAtSign = GlobalKey();
  GlobalKey keyHaveAnAtSign = GlobalKey();
  late TutorialCoachMark tutorialCoachMark;
  List<TargetFocus> signUpTargets = <TargetFocus>[];

  @override
  void initState() {
    _inprogressDialog = AtSyncDialog(context: context);
    super.initState();
    _getFreeAtsign();
    _init();
  }

  void _init() async {
    initTargets();
    _checkShowTutorial();
  }

  void _checkShowTutorial() async {
    if (widget.config.tutorialDisplay == AtOnboardingTutorialDisplay.always) {
      await Future.delayed(const Duration(milliseconds: 300));
      _showTutorial();
    } else if (widget.config.tutorialDisplay ==
        AtOnboardingTutorialDisplay.never) {
      return;
    } else {
      final result = await AtOnboardingTutorialService.checkShowTutorial();
      if (!result) {
        await Future.delayed(const Duration(milliseconds: 300));

        final result =
            await AtOnboardingTutorialService.hasShowTutorialSignUp();
        if (!result) {
          _showTutorial();
        }
      }
    }
  }

  void _showTutorial() {
    tutorialCoachMark = TutorialCoachMark(
      targets: signUpTargets,
      skipWidget: Text(
        AtOnboardingLocalizations.current.btn_skip_tutorial,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: _endTutorial,
      onSkip: skipTutorial,
    )..show(context: context);
  }

  bool skipTutorial() {
    _endTutorial();
    return true;
  }

  void _endTutorial() async {
    var tutorialInfo = await AtOnboardingTutorialService.getTutorialInfo();
    tutorialInfo ??= AtTutorialServiceInfo();

    tutorialInfo.hasShowSignUpPage = true;

    AtOnboardingTutorialService.setTutorialInfo(tutorialInfo);
  }

  void initTargets() {
    signUpTargets.add(
      TargetFocus(
        identify: "keyGenerateAtSign",
        keyTarget: keyGenerateAtSign,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Center(
                child: Text(
                  AtOnboardingLocalizations.current.tutorial_generate_atSign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: AtOnboardingDimens.fontLarge,
                  ),
                ),
              );
            },
          ),
        ],
        shape: ShapeLightFocus.RRect,
        radius: 8.0,
        paddingFocus: 8.0,
      ),
    );

    signUpTargets.add(
      TargetFocus(
        identify: "keyHaveAnAtSign",
        keyTarget: keyHaveAnAtSign,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return Center(
                child: Text(
                  AtOnboardingLocalizations.current.tutorial_generate_atSign,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: AtOnboardingDimens.fontLarge,
                  ),
                ),
              );
            },
          ),
        ],
        shape: ShapeLightFocus.RRect,
        radius: 8.0,
        paddingFocus: 8.0,
      ),
    );
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
      absorbing: _isGenerating,
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
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius:
                        BorderRadius.circular(AtOnboardingDimens.borderRadius)),
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
                      AtOnboardingLocalizations.current.btn_generate_atSign,
                      style: const TextStyle(
                        fontSize: AtOnboardingDimens.fontLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextFormField(
                      enabled: false,
                      validator: (String? value) {
                        if ((value ?? '').isEmpty) {
                          return AtOnboardingLocalizations
                              .current.msg_atSign_cannot_empty;
                        }
                        return null;
                      },
                      controller: _atsignController,
                      decoration: InputDecoration(
                        hintText: AtOnboardingStrings.atsignHintText,
                        prefix: Text(
                          '@',
                          style: TextStyle(color: theme.primaryColor),
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: theme.primaryColor,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AtOnboardingDimens.paddingSmall),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AtOnboardingLocalizations.current.msg_refresh_atSign,
                      style: const TextStyle(
                        fontSize: AtOnboardingDimens.fontNormal,
                        // fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      highlightColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      onTap: _showReferenceWebview,
                      child: Text(
                        AtOnboardingLocalizations.current.learn_about_atSign,
                        style: const TextStyle(
                          fontSize: AtOnboardingDimens.fontNormal,
                          fontStyle: FontStyle.italic,
                          // fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AtOnboardingSecondaryButton(
                      key: keyGenerateAtSign,
                      height: 48,
                      borderRadius: 24,
                      onPressed: () async {
                        _getFreeAtsign();
                      },
                      isLoading: _isGenerating,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Center(
                            child: Text(
                              AtOnboardingLocalizations.current.btn_refresh,
                              style: const TextStyle(
                                fontSize: AtOnboardingDimens.fontLarge,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.refresh,
                            size: 20,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    AtOnboardingPrimaryButton(
                      height: 48,
                      borderRadius: 24,
                      onPressed: _showPairScreen,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AtOnboardingLocalizations.current.btn_pair,
                            style: const TextStyle(
                              fontSize: AtOnboardingDimens.fontLarge,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_right_alt_rounded,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: () async {
                        if (widget.isFromIntroScreen) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (BuildContext context) {
                                return AtOnboardingHomeScreen(
                                  config: widget.config,
                                );
                              },
                            ),
                          );
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      highlightColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      child: Text(
                        AtOnboardingLocalizations
                            .current.btn_already_have_atSign,
                        key: keyHaveAnAtSign,
                        style: TextStyle(
                          fontSize: AtOnboardingDimens.fontNormal,
                          fontWeight: FontWeight.w500,
                          color: theme.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
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

  void _getFreeAtsign() async {
    setState(() {
      _isGenerating = true;
    });
    dynamic data;
    String? atsign;
    dynamic response = await _freeAtsignService.getFreeAtsigns();
    if (response.statusCode == 200) {
      data = response.body;
      data = jsonDecode(data);
      atsign = data['data']['atsign'];
    } else {
      data = response.body;
      data = jsonDecode(data);
      String? errorMessage = data['message'];
      await showErrorDialog(errorMessage);
    }
    setState(() {
      _isGenerating = false;
    });
    if ((atsign ?? '').isNotEmpty) {
      _atsignController.text = atsign ?? '';
    }
  }

  Future<void> showErrorDialog(dynamic errorMessage, {String? title}) async {
    String? messageString =
        AtOnboardingErrorToString().getErrorMessage(errorMessage);
    return AtOnboardingDialog.showError(
        context: context, message: messageString);
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

  void _showPairScreen() async {
    final String atSign = _atsignController.text;
    Navigator.push(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) => AtOnboardingPairScreen(
          atSign: atSign,
          hideReferences: false,
          onGenerateSuccess: ({
            required String atSign,
            required String secret,
          }) {
            if (widget.onGenerateSuccess != null) {
              Navigator.pop(context);
              widget.onGenerateSuccess?.call(atSign: atSign, secret: secret);
            } else {
              _processSharedSecret(atSign: atSign, secret: secret);
            }
          },
          config: widget.config,
        ),
      ),
    );
  }

  Future<void> _processSharedSecret({
    required String atSign,
    required String secret,
  }) async {
    String verifiedAtSign = atSign.startsWith('@') ? atSign : '@$atSign';

    try {
      _inprogressDialog.show(
        message: AtOnboardingLocalizations.current.processing,
      );
      await Future.delayed(const Duration(milliseconds: 400));
      bool isExist = await _onboardingService.isExistingAtsign(verifiedAtSign);

      if (isExist) {
        _inprogressDialog.close();
        await _showAlertDialog(
            AtOnboardingErrorToString().pairedAtsign(verifiedAtSign));
        return;
      }

      await Future.delayed(const Duration(seconds: 10));

      String? previousAtsign = _onboardingService.currentAtsign;
      _onboardingService.setAtsign = verifiedAtSign;

      final authResponse = await _onboardingService.onboard(
        cramSecret: secret,
      );

      _inprogressDialog.close();
      if (authResponse) {
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
        Navigator.pop(
          context,
          AtOnboardingResult.success(atsign: verifiedAtSign),
        );
      } else {
        _onboardingService.setAtsign = previousAtsign;
        await _showAlertDialog(
          AtOnboardingLocalizations.current.error_authenticated_failed,
        );
      }
    } catch (e) {
      _inprogressDialog.close();
      if (e == AtOnboardingResponseStatus.authFailed) {
        _logger.severe('Error in authenticateWith cram secret');
        await _showAlertDialog(
          e,
          title: AtOnboardingLocalizations.current.error_authenticated_failed,
        );
      } else if (e == AtOnboardingResponseStatus.serverNotReached) {
        await _processSharedSecret(
          atSign: atSign,
          secret: secret,
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
    return AtOnboardingDialog.showError(
        context: context, title: title, message: messageString);
  }
}
