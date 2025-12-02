import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/services/registrar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';



/// A dialog widget that facilitates obtaining a CRAM key via Registrar OTP verification.
/// 
/// Use `RegistrarCramDialog.show` to display the dialog and handle the OTP verification process.
/// 
/// Required Parameters:
/// - [request]: An `AtOnboardingRequest` containing details for the onboarding process.
/// - [registrar]: An instance of `RegistrarService` to interact with the registrar.
/// - [themeData]: ThemeData for styling the dialog. NOTE: Handled internally via show method.
/// 
/// Returns:
/// - A `String` representing the CRAM key upon successful OTP verification, or null if the process fails or is cancelled.
class RegistrarCramDialog extends StatefulWidget {
  final AtOnboardingRequest request;
  final RegistrarService registrar;
  final ThemeData themeData;

  const RegistrarCramDialog({
    super.key,
    required this.request,
    required this.registrar,
    required this.themeData,
  });

  @override
  State<RegistrarCramDialog> createState() => _RegistrarCramDialogState();

  /// Show the RegistrarCramDialog and return the cram key.
  static Future<String?> show(
    BuildContext context,
    AtOnboardingRequest request, {
    required RegistrarService registrar,
  }) async {
    if (!await registrar.sendActivationOtp(request.atSign)) {
      throw Exception('Failed to send activation OTP');
    }
    return showDialog<String>(
      context: context,
      builder: (context) => RegistrarCramDialog(
        request: request,
        themeData: Theme.of(context),
        registrar: registrar,
      ),
    );
  }
}

class _RegistrarCramDialogState extends State<RegistrarCramDialog> {
  final List<TextEditingController> _controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  Timer? _resendTimer;
  bool _isLoading = false;
  int _resendCountdown = 30;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    setState(() {
      _canResend = false;
      _resendCountdown = 30; // Reset to 30 seconds
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  void _handleResendCode() {
    if (_canResend) {
      widget.registrar.sendActivationOtp(widget.request.atSign);
      _startResendTimer(); // Restart the timer after resending
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty && index < 3) {
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

  Widget _buildResendCodeText() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 14,
            color: widget.themeData.primaryColor,
          ),
          children: [
            const TextSpan(text: "Didn't receive a code? "),
            WidgetSpan(
              child: InkWell(
                onTap: _canResend ? _handleResendCode : null,
                child: Text(
                  'Resend code',
                  style: TextStyle(
                    fontSize: 14,
                    color: _canResend
                        ? widget.themeData.colorScheme.secondary
                        : widget.themeData.disabledColor,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (!_canResend)
              TextSpan(
                text: ' (${_resendCountdown}s)',
                style: TextStyle(color: widget.themeData.disabledColor),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      backgroundColor: Colors.white,
      child: Container(
        width: 360,
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
                  child: const Icon(
                    Icons.arrow_back,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Enter OTP',
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
                    text:
                        'A 4 symbol verification code has sent to the email associated with ',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: widget.request.atSign,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.themeData.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
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
              children: List.generate(4, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 56,
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
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        String otp = _controllers.map((c) => c.text).join();
                        if (otp.length == 4 && !_isLoading) {
                          try {
                            setState(() {
                              _isLoading = true;
                            });
                            var cram = await widget.registrar.verifyActivation(
                              atsign: widget.request.atSign,
                              otp: otp,
                            );
                            Navigator.of(context).pop(cram);
                          } catch (e) {
                            setState(() {
                              _isLoading = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Error verifying OTP: $e')),
                            );
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
                        'Submit OTP',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),

            _buildResendCodeText(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
