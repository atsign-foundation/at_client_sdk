import 'dart:io';

import 'package:at_client_mobile/src/onboarding/onboarding.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../notifiers/enrollment_notifier.dart';
import '../providers/enrollment_notifier_provider.dart';
import '../providers/selected_atsign_notifier_provider.dart';
import '../widgets/apkam_choice.dart';

class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({
    required this.onKeysUpload,
    super.key,
  });

  final void Function(String keysFile) onKeysUpload;

  @override
  EnrollmentPageState createState() => EnrollmentPageState();
}

class EnrollmentPageState extends State<EnrollmentPage> {
  // Whether the user has made a choice (between keys or enrollment).
  bool choiceMade = false;

  static const _kPinLength = 6;

  late final TextEditingController pinController;
  late final EnrollmentNotifier enrollmentNotifier;

  @override
  void initState() {
    super.initState();
    pinController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      enrollmentNotifier = EnrollmentNotifierProvider.of(context);
      enrollmentNotifier.addListener(enrollmentNotifierListener);
      enrollmentNotifier.init();
    });
  }

  @override
  void dispose() {
    pinController.dispose();
    enrollmentNotifier.removeListener(enrollmentNotifierListener);
    super.dispose();
  }

  Future<void> enrollmentNotifierListener() async {
    final status = enrollmentNotifier.status;
    if (status == OnboardingEnrollmentStatus.success) {
      await Future.delayed(const Duration(seconds: 2));
      Navigator.of(context).pop(
        AtOnboardingResult.success(
          atsign: SelectedAtsignNotifierProvider.of(context).value,
        ),
      );
    } else if (status == OnboardingEnrollmentStatus.denied) {
      await Future.delayed(const Duration(seconds: 2));
      Navigator.of(context).pop(
        AtOnboardingResult.error(
          errorMessage: 'Enrollment denied',
          errorCode: '',
        ),
      );
    }
  }

  static Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return '${androidInfo.manufacturer} ${androidInfo.model}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return '${iosInfo.name} (${iosInfo.model})';
    } else if (Platform.isMacOS) {
      final macInfo = await deviceInfo.macOsInfo;
      return macInfo.computerName;
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return windowsInfo.computerName;
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      return linuxInfo.name;
    } else {
      return 'Unknown Device';
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentNotifier = EnrollmentNotifierProvider.of(context);
    if (choiceMade) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: Builder(
          key: ObjectKey(EnrollmentNotifierProvider.of(context).status),
          builder: (context) {
            final enrollmentStatus = enrollmentNotifier.status;
            print(enrollmentStatus);
            if (enrollmentStatus == OnboardingEnrollmentStatus.preparing) {
              return const CircularProgressIndicator(
                key: Key('preparing'),
              );
            } else if (enrollmentStatus == OnboardingEnrollmentStatus.otpRequired ||
                enrollmentStatus == OnboardingEnrollmentStatus.validatingOtp) {
              return Column(
                key: const Key('otp'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter OTP',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.black),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The request will be displayed in the Authenticator under Requests in any app connected to your atSign with manager keys.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  IntrinsicHeight(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 280,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PinCodeTextField(
                                autoDisposeControllers: false,
                                appContext: context,
                                length: _kPinLength,
                                controller: pinController,
                                autoFocus: true,
                                textCapitalization: TextCapitalization.characters,
                                // Styling
                                animationType: AnimationType.fade,
                                pinTheme: PinTheme(
                                  shape: PinCodeFieldShape.box,
                                  borderRadius: BorderRadius.circular(5),
                                  activeFillColor: Colors.white,
                                  inactiveFillColor: const Color(0xFFF3F3F3),
                                  disabledColor: Colors.blue,
                                  inactiveColor: const Color(0xFF747474),
                                  selectedFillColor: Colors.white,
                                  selectedColor: Theme.of(context).colorScheme.primary,
                                  fieldOuterPadding: const EdgeInsets.all(2),
                                ),
                                cursorColor: Colors.black,
                                animationDuration: const Duration(milliseconds: 300),
                                enableActiveFill: true,
                                keyboardType: TextInputType.text,
                                beforeTextPaste: (text) => true,
                              ),
                              const SizedBox(height: 8),
                              AnimatedBuilder(
                                animation: pinController,
                                builder: (context, _) {
                                  return FilledButton(
                                    style: FilledButton.styleFrom(
                                      textStyle: const TextStyle(
                                        fontSize: 18,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: pinController.text.length == _kPinLength &&
                                            enrollmentStatus != OnboardingEnrollmentStatus.validatingOtp
                                        ? () async {
                                            await enrollmentNotifier.submitOtp(pinController.text);
                                          }
                                        : null,
                                    child: enrollmentStatus == OnboardingEnrollmentStatus.validatingOtp
                                        ? const CircularProgressIndicator()
                                        : Text('Submit OTP'),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Transform.translate(
                            offset: const Offset(32, 0),
                            child: Placeholder(),
                            // child: Image.asset(
                            //   Constants.authenticatorMockup,
                            //   fit: BoxFit.cover,
                            // ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else if (enrollmentStatus == OnboardingEnrollmentStatus.pendingApproval) {
              return Column(
                key: const Key('activating'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // This is a little hacky to get the white background.
                      // If this is a problem, we can rethink the EnrollmentDialog widget.
                      Positioned.fill(
                        child: Transform.scale(
                          scaleX: 1.15,
                          scaleY: 2.8,
                          child: Container(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Waiting for approval...',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Theme.of(context).primaryColor,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const CircularProgressIndicator(),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 56),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Just to slightly offset from the top
                            const SizedBox(height: 12),
                            Text(
                              'Where to accept?',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              'Please approve the request in an app with a manager key.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: Transform.translate(
                          offset: const Offset(16, 0),
                          child: Placeholder(),
                          // child: Image.asset(
                          //   Constants.authenticatorApprovalMockup,
                          // ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            } else if (enrollmentStatus == OnboardingEnrollmentStatus.success) {
              return Row(
                key: const Key('success'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check,
                    color: Colors.green,
                    size: 32,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Enrollment request approved',
                    style: Theme.of(context).textTheme.titleLarge,
                  )
                ],
              );
            } else if (enrollmentStatus == OnboardingEnrollmentStatus.denied) {
              return Row(
                key: const Key('denied'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Enrollment request denied',
                    style: Theme.of(context).textTheme.titleLarge,
                  )
                ],
              );
            } else {
              return const SizedBox.shrink(); // Default case
            }
          },
        ),
      );
    } else {
      return ApkamChoice(
        onKeysUpload: widget.onKeysUpload,
        onApkamChosen: () {
          setState(() {
            choiceMade = true;
          });
        },
      );
    }
  }
}
