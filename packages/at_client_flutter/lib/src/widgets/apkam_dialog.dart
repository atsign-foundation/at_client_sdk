import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final FlutterEnrollmentService? enrollmentService;

  ApkamActivationDialog({
    super.key,
    required this.atSign,
    required this.rootDomain,
    required this.appName,
    required this.deviceName,
    required this.namespaces,
    required this.themeData,
    this.enrollmentService,
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
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  late final FlutterEnrollmentService enrollmentService;
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
    enrollmentService = widget.enrollmentService ?? FlutterEnrollmentService();
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
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  void _onKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 50,
                    height: 64,
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) => _onKeyEvent(event, index),
                      child: TextField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFE0E0E0),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: widget.themeData.colorScheme.secondary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onChanged: (value) => _onChanged(value, index),
                      ),
                    ),
                  ),
                );
              }),
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
                      onPressed: () async {
                        String otp = _controllers.map((c) => c.text).join();
                        if (otp.length == 6 && !_isLoading) {
                          setState(() {
                            _isLoading = true;
                          });
                          try {
                            final response = await _sendEnrollment(otp);
                            if (!mounted) return;
                            Navigator.of(context).pop(response);
                          } catch (e) {
                            if (mounted) {
                              _showError(context, e.toString());
                              Navigator.of(context).pop();
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          }
                        }
                      },
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

  void _showError(BuildContext context, String error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error.isNotEmpty ? error : 'Enrollment failed. Please try again.',
        ),
      ),
    );
  }
}
