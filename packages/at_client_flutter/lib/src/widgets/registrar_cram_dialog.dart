import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

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
    await registrar.requestActivationOtp(request.atSign);
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
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  final ScrollController _pinScrollController = ScrollController();
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
      widget.registrar.requestActivationOtp(widget.request.atSign);
      _startResendTimer(); // Restart the timer after resending
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _pinScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text;
    if (otp.length != 4 || _isLoading) return;

    try {
      setState(() {
        _isLoading = true;
      });
      var cram = await widget.registrar.verifyActivation(
        atSign: widget.request.atSign,
        otp: otp,
      );
      if (!mounted) return;
      Navigator.of(context).pop(cram);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error verifying OTP: $e')));
    }
  }

  Widget _buildResendCodeText() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 14, color: widget.themeData.primaryColor),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  child: const Icon(Icons.arrow_back, size: 20),
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
                        'A 4-symbol verification code was sent to the email associated with ',
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
            LayoutBuilder(
              builder: (context, constraints) {
                const otpCount = 4;
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
                  physics: const BouncingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: Pinput(
                    controller: _otpController,
                    focusNode: _otpFocusNode,
                    autofocus: true,
                    length: otpCount,
                    closeKeyboardWhenCompleted: false,
                    separatorBuilder: (_) => const SizedBox(width: itemGap),
                    keyboardType: TextInputType.visiblePassword,
                    textCapitalization: TextCapitalization.characters,
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
                ? const Center(child: CircularProgressIndicator())
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
