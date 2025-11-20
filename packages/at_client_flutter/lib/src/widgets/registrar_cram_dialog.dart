import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/src/services/registrar_service.dart';
import 'package:at_client_flutter/src/widgets/cram_dialog.dart';
import 'package:at_client_flutter/src/widgets/shared/atsign_rootdomain_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegistrarCramDialog extends StatefulWidget {
  final AtOnboardingRequest request;
  final Function(AtOnboardingRequest req, String cramKey)? onSubmit;
  final Function(AtOnboardingResponse)? onDone;
  final VoidCallback? onResendCode;

  const RegistrarCramDialog({
    super.key,
    required this.request,
    this.onDone,
    this.onSubmit,
    this.onResendCode,
    this.primaryColor = Colors.black87,
    this.secondaryColor = Colors.black87,
    this.tertiaryColor = Colors.black38,
    this.accentTextColor = const Color(0xFFFF5722),
  });

  final Color primaryColor;
  final Color secondaryColor;
  final Color tertiaryColor;
  final Color accentTextColor;

  @override
  State<RegistrarCramDialog> createState() => _RegistrarCramDialogState();

  static Future<AtOnboardingResponse?> onboard(
    BuildContext context,
     String registrarUrl, 
     String apiKey, {
      Color primaryColor = Colors.black87, 
      Color secondaryColor = Colors.black87, 
      Color tertiaryColor = Colors.black38,
      Color accentTextColor = const Color(0xFFFF5722),
      Function(AtOnboardingResponse)? onDone,
      Function(AtOnboardingRequest req, String cramKey)? onSubmit,
    }) async {
    final registrar = RegistrarService(registrarUrl: registrarUrl, apiKey: apiKey);

    const defaultDomains = {
      'root.atsign.org': AtRootDomain.atsignDomain
    };

    const atsigns = <String>["@example", "@alice", "@bob", "@charlie"];

    var request = await AtSignSelectionDialog.show(
      context,
      existingAtSigns: atsigns,
      existingDomains: defaultDomains,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      accentTextColor: tertiaryColor,
    );
    if (request == null) throw Exception('AtOnboardingRequest is null / User may have cancelled the operation');
  
    if (!await registrar.sendActivationOtp(request.atSign)) {
      throw Exception('Failed to send activation OTP / Either atSign is invalid or already registered');
    }
    var otp =  await RegistrarCramDialog.show(
      context,
      request,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      tertiaryColor: tertiaryColor,
      accentTextColor: accentTextColor,
      onDone: onDone,
      onSubmit: onSubmit,
    );
    if (otp == null) {
      throw Exception('OTP submission was cancelled by the user');
    }
    var res = await registrar.verifyActivation(atsign: request.atSign, otp: otp);
    if (res.cramkey == null) {
      throw Exception('Failed to verify activation OTP / Invalid OTP or atSign');
    }
    return await CramDialog.show(
      context,
      request: request,
      cramKey: res.cramkey!,
    );
  }

  static Future<String?> show(BuildContext context,
    AtOnboardingRequest request, {
      Color primaryColor = Colors.black87, 
      Color secondaryColor = Colors.black87, 
      Color tertiaryColor = Colors.black38,
      Color accentTextColor = const Color(0xFFFF5722),
      Function(AtOnboardingResponse)? onDone,
      Function(AtOnboardingRequest req, String cramKey)? onSubmit,
    }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => RegistrarCramDialog(
        request: request,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tertiaryColor: tertiaryColor,
        accentTextColor: accentTextColor,
        onDone: onDone,
        onSubmit: onSubmit,
      ),
    );
  }
}


class _RegistrarCramDialogState extends State<RegistrarCramDialog> {
  final List<TextEditingController> _controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  Timer? _resendTimer;
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
      widget.onResendCode?.call();
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
            color: widget.primaryColor,
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
                        ? widget.accentTextColor 
                        : widget.tertiaryColor,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (!_canResend)
              TextSpan(
                text: ' (${_resendCountdown}s)',
                style: TextStyle(color: widget.tertiaryColor),
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
              // Back button and title
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      // Handle back navigation
                    },
                    child: const Icon(
                      Icons.arrow_back,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Use a different atSign',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.secondaryColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Enter OTP title
              Text(
                'Enter OTP',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: widget.primaryColor,
                ),
              ),
              const SizedBox(height: 16),

              // Description
              RichText(text: 
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'A 4 symbol verification code has sent to the email associated with ',
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.secondaryColor,
                        height: 1.5,
                      ),
                    ),
                    TextSpan(
                      text: widget.request.atSign,
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.accentTextColor,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ],
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.secondaryColor,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // OTP Input boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 45,
                      height: 56,
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
                                color: widget.secondaryColor,
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
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    // Handle OTP submission
                    String otp = _controllers.map((c) => c.text).join();
                    if (otp.length == 4) {
                      widget.onDone?.call(AtOnboardingResponse(otp));
                      Navigator.of(context).pop(otp);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.secondaryColor,
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

              // Resend code text
              _buildResendCodeText(),
              const SizedBox(height: 32),

              // License key option
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () {
                    // Handle license key option
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.primaryColor,
                    side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Or try using your licence key',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}