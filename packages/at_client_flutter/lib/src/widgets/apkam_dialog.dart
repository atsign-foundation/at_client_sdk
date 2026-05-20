import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

/// A dialog widget that facilitates APKAM activation via OTP verification.
///
/// Use `ApkamActivationDialog.show` to display the dialog and handle the OTP verification process.
///
/// Required Parameters:
/// - [request]: An `AtOnboardingRequest` containing details for the onboarding process.
/// - [registrar]: An instance of `RegistrarService` to interact with the registrar.
/// - [themeData]: ThemeData for styling the dialog. NOTE: Handled internally via show method.
///
/// Returns:
/// - A `String` representing the activation result upon successful OTP verification, or null if the process fails or is cancelled.
class ApkamActivationDialog extends StatefulWidget {
  final String atSign;
  final AtRootDomain rootDomain;
  final String appName;
  final String deviceName;
  final Map<String, String> namespaces;

  final ThemeData themeData;

  ApkamActivationDialog({
    super.key,
    required this.atSign,
    required this.rootDomain,
    required this.appName,
    required this.deviceName,
    required this.namespaces,
    required this.themeData,
  });

  @override
  State<ApkamActivationDialog> createState() => _ApkamActivationDialogState(
    atSign,
    rootDomain,
    appName,
    deviceName,
    namespaces,
  );

  /// Show the ApkamActivationDialog and return the activation result.
  static Future<AtEnrollmentResponse?> show(
    BuildContext context, {
    required String atSign,
    required AtRootDomain rootDomain,
    required String appName,
    required String deviceName,
    required Map<String, String> namespaces,
  }) async {
    return showDialog<AtEnrollmentResponse>(
      context: context,
      builder: (context) => ApkamActivationDialog(
        atSign: atSign,
        rootDomain: rootDomain,
        appName: appName,
        deviceName: deviceName,
        namespaces: namespaces,
        themeData: Theme.of(context),
      ),
    );
  }
}

class _ApkamActivationDialogState extends State<ApkamActivationDialog> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  final ScrollController _pinScrollController = ScrollController();
  bool _isLoading = false;
  final enrollmentService = FlutterEnrollmentService();
  final String atSign;
  final AtRootDomain rootDomain;
  final String appName;
  final String deviceName;
  final Map<String, String> namespaces;

  _ApkamActivationDialogState(
    this.atSign,
    this.rootDomain,
    this.appName,
    this.deviceName,
    this.namespaces,
  );

  @override
  void initState() {
    super.initState();
  }

  Future<AtEnrollmentResponse> _sendEnrollment(String otp) async {
    AtEnrollmentRequest request = AtEnrollmentRequest(
      atSign: atSign,
      rootDomain: rootDomain,
      deviceName: deviceName,
      appName: appName,
      namespaces: namespaces,
      otp: otp,
    );
    return await enrollmentService.enroll(request, waitForApproval: true);
  }

  @override
  void dispose() {
    _otpController.dispose();
    _otpFocusNode.dispose();
    _pinScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text;
    if (otp.length != 6 || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _sendEnrollment(otp);
      if (!mounted) return;
      Navigator.of(context).pop(response);
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 24,
        24,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.white,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button
            Row(
              children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: const Icon(Icons.arrow_back, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Activate APKAM',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: widget.themeData.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            // Description
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'A 6-digit verification code needs to generated for ',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: widget.atSign,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: '. Enter the code below to activate APKAM.',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      height: 1.5,
                    ),
                  ),
                ],
                style: TextStyle(
                  fontSize: 14,
                  color: widget.themeData.colorScheme.secondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // OTP Input boxes
            LayoutBuilder(
              builder: (context, constraints) {
                const otpCount = 6;
                const itemGap = 12.0;
                final idealSize =
                    (constraints.maxWidth - ((otpCount - 1) * itemGap)) /
                    otpCount;
                final otpSize = idealSize.clamp(52.0, 56.0).toDouble();
                final viewportWidth = constraints.maxWidth;

                final defaultPinTheme = PinTheme(
                  width: otpSize,
                  height: otpSize,
                  textStyle: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: const Border.fromBorderSide(
                      BorderSide(color: Color(0xFFE0E0E0), width: 1),
                    ),
                  ),
                );

                return SingleChildScrollView(
                  controller: _pinScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Pinput(
                    controller: _otpController,
                    focusNode: _otpFocusNode,
                    autofocus: true,
                    length: otpCount,
                    closeKeyboardWhenCompleted: false,
                    separatorBuilder: (_) => const SizedBox(width: itemGap),
                    keyboardType: TextInputType.number,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: defaultPinTheme.copyWith(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.themeData.colorScheme.secondary,
                          width: 2,
                        ),
                      ),
                    ),
                    submittedPinTheme: defaultPinTheme,
                    onChanged: (value) {
                      final activeIndex = value.length >= otpCount
                          ? otpCount - 1
                          : value.length;

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || !_pinScrollController.hasClients) {
                          return;
                        }

                        final pinStart = activeIndex * (otpSize + itemGap);
                        final pinEnd = pinStart + otpSize;
                        final currentOffset = _pinScrollController.offset;
                        final viewStart = currentOffset;
                        final viewEnd = currentOffset + viewportWidth;
                        const edgePadding = 8.0;

                        double? targetOffset;
                        if (pinStart < viewStart + edgePadding) {
                          targetOffset = pinStart - edgePadding;
                        } else if (pinEnd > viewEnd - edgePadding) {
                          targetOffset = pinEnd - viewportWidth + edgePadding;
                        }

                        if (targetOffset == null) return;

                        final clampedOffset = targetOffset.clamp(
                          _pinScrollController.position.minScrollExtent,
                          _pinScrollController.position.maxScrollExtent,
                        );

                        if ((clampedOffset - currentOffset).abs() < 1) {
                          return;
                        }

                        _pinScrollController.animateTo(
                          clampedOffset,
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                        );
                      });
                    },
                    onCompleted: (_) => _submitOtp(),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),

            // Submit button
            _isLoading
                ? const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        Text("Waiting for approval.."),
                      ],
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _submitOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeData.colorScheme.secondary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Activate APKAM',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
