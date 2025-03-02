import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/material.dart';

import '../notifiers/authenticate_atsign_notifier.dart';
import '../notifiers/enrollment_notifier.dart';
import '../notifiers/keys_upload_notifier.dart';
import '../notifiers/login_notifier.dart';
import '../providers/authenticate_atsign_notifier_provider.dart';
import '../providers/enrollment_notifier_provider.dart';
import '../providers/keys_upload_notifier_provider.dart';
import '../providers/login_notifier_provider.dart';
import '../providers/selected_atsign_notifier_provider.dart';
import '../widgets/onboarding_init_form.dart';
import 'authenticating_page.dart';
import 'enrollment_page.dart';
import 'register_page.dart';

/// Top level states of the onboarding process.
enum _OnboardingPageType {
  /// The initial state where a form to login or a button to register is displayed.
  init,

  /// The register flow.
  register,

  /// The loading state where a loading indicator is displayed.
  /// This screen can show more detailed information about the loading process.
  authenticating,

  /// The enrollment flow.
  enrollment,
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  OnboardingPageState createState() => OnboardingPageState();
}

class OnboardingPageState extends State<OnboardingPage> {
  late _OnboardingPageType _type;
  late final LoginNotifier _loginNotifier;
  late final AuthenticateAtsignNotifier _authenticateAtsignNotifier;
  late final EnrollmentNotifier _enrollmentNotifier;
  late final KeysUploadNotifier _keysUploadNotifier;

  @override
  void initState() {
    super.initState();
    _type = _OnboardingPageType.init;
    _authenticateAtsignNotifier = AuthenticateAtsignNotifier();
    _enrollmentNotifier = EnrollmentNotifier();
    _keysUploadNotifier = KeysUploadNotifier();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loginNotifier = LoginNotifierProvider.of(context);
      _loginNotifier.addListener(loginNotifierListener);
    });
  }

  @override
  void dispose() {
    _loginNotifier.removeListener(loginNotifierListener);
    // Login notifier is created and disposed of higher up the tree.
    _authenticateAtsignNotifier.dispose();
    _enrollmentNotifier.dispose();
    _keysUploadNotifier.dispose();
    super.dispose();
  }

  void loginNotifierListener() {
    print(_loginNotifier.status);
    if (_loginNotifier.error != null) {
      // TODO: Pass in error code
      Navigator.of(context).pop(
        AtOnboardingResult.error(
          errorMessage: _loginNotifier.error.toString(),
          errorCode: '',
        ),
      );
    } else {
      switch (_loginNotifier.status) {
        case LoginStatus.contactingServer:
          setState(() {
            _type = _OnboardingPageType.authenticating;
          });
          break;
        case LoginStatus.fetchingKeys:
          setState(() {
            _type = _OnboardingPageType.authenticating;
          });
          break;
        case LoginStatus.authenticating:
          setState(() {
            _type = _OnboardingPageType.authenticating;
          });
          break;
        case LoginStatus.authenticated:
          Navigator.of(context).pop(
            AtOnboardingResult.success(
              atsign: SelectedAtsignNotifierProvider.of(context).value,
            ),
          );
          break;
        case LoginStatus.cramAuthenticating:
          setState(() {
            _type = _OnboardingPageType.authenticating;
          });
          break;
        case LoginStatus.otpRequired:
          setState(() {
            _type = _OnboardingPageType.authenticating;
          });
          break;
        case LoginStatus.enrollmentRequired:
          setState(() {
            _type = _OnboardingPageType.enrollment;
          });
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: Builder(
        key: ObjectKey(_type),
        builder: (context) {
          if (_type == _OnboardingPageType.init) {
            return OnboardingInitForm(
              onRegisterPressed: () {
                setState(() {
                  _type = _OnboardingPageType.register;
                });
              },
            );
          } else if (_type == _OnboardingPageType.register) {
            return RegisterPage(
              onCramKeyReceived: (cramKey, atSign) async {
                SelectedAtsignNotifierProvider.of(context).value = atSign;
                await _loginNotifier.cramAuthenticate(cramKey, atSign);
              },
              onBack: () {
                setState(() {
                  _type = _OnboardingPageType.init;
                });
              },
            );
          } else if (_type == _OnboardingPageType.enrollment) {
            return KeysUploadNotifierProvider(
              notifier: _keysUploadNotifier,
              child: EnrollmentNotifierProvider(
                notifier: _enrollmentNotifier,
                child: EnrollmentPage(
                  onKeysUpload: (keysFile) async {
                    await _loginNotifier.keysAuthenticate(keysFile);
                  },
                ),
              ),
            );
          } else if (_type == _OnboardingPageType.authenticating) {
            return AuthenticateAtsignNotifierProvider(
              notifier: _authenticateAtsignNotifier,
              child: AuthenticatingPage(
                onCramKeyReceived: (cramKey, atSign) async {
                  await _loginNotifier.cramAuthenticate(cramKey, atSign);
                },
              ),
            );
          } else {
            throw Exception('Unknown onboarding page type');
          }
        },
      ),
    );
  }
}
