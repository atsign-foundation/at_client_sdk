import 'package:at_client_mobile/src/onboarding/providers/free_atsign_notifier_provider.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../providers/register_person_notifier_provider.dart';
import '../providers/submit_registrar_otp_notifier_provider.dart';

class RegisterOtpPage extends StatefulWidget {
  const RegisterOtpPage({required this.onCramKeyReceived, super.key});

  final ValueChanged<String> onCramKeyReceived;

  @override
  RegisterOtpPageState createState() => RegisterOtpPageState();
}

class RegisterOtpPageState extends State<RegisterOtpPage> {
  late final TextEditingController _controller;

  static const _pinCodeLength = 4;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registerPersonNotifier = RegisterPersonNotifierProvider.of(context);
    final subRegistrarOtpNotifier = SubmitRegistrarOtpNotifierProvider.of(context);
    final freeAtSignNotifier = FreeAtsignNotifierProvider.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter Verification Code',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 16),
        PinCodeTextField(
          appContext: context,
          controller: _controller,
          length: _pinCodeLength,
          mainAxisAlignment: MainAxisAlignment.start,
          textCapitalization: TextCapitalization.characters,
          cursorColor: Theme.of(context).colorScheme.primary,
          animationType: AnimationType.fade,
          enableActiveFill: true,
          autoFocus: true,
          autoDisposeControllers: false,
          pinTheme: PinTheme(
            shape: PinCodeFieldShape.box,
            borderRadius: BorderRadius.circular(4),
            fieldOuterPadding: EdgeInsets.only(right: 16),
            inactiveColor: Theme.of(context).colorScheme.onSurfaceVariant,
            selectedColor: Theme.of(context).colorScheme.primary,
            activeFillColor: Theme.of(context).colorScheme.surface,
            selectedFillColor: Theme.of(context).colorScheme.surface,
            inactiveFillColor: Theme.of(context).colorScheme.surface,
            borderWidth: 1,
          ),
        ),
        SizedBox(height: 16),
        Text('A verification code has been sent to ${registerPersonNotifier.email!}.'),
        SizedBox(height: 8),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final enoughChars = _controller.text.length == _pinCodeLength;
            return FilledButton.icon(
              onPressed: enoughChars && !subRegistrarOtpNotifier.isFetching
                  ? () async {
                      await subRegistrarOtpNotifier.submitOtp(
                        otp: _controller.text,
                        email: registerPersonNotifier.email!,
                        atSign: freeAtSignNotifier.freeAtsign!,
                      );
                      if (subRegistrarOtpNotifier.error == null) {
                        widget.onCramKeyReceived(subRegistrarOtpNotifier.cramSecret!);
                      }
                    }
                  : null,
              icon: Icon(Icons.arrow_forward),
              iconAlignment: IconAlignment.end,
              label: Text('Verify & Login'),
            );
          },
        ),
        if (subRegistrarOtpNotifier.error != null) ...[
          SizedBox(height: 8),
          Text(
            subRegistrarOtpNotifier.error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          SizedBox(height: 8),
        ],
        SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: registerPersonNotifier.isFetching
              ? null
              : () async {
                  await registerPersonNotifier.registerPerson(
                    registerPersonNotifier.email!,
                    FreeAtsignNotifierProvider.of(context).freeAtsign!,
                  );
                },
          icon: Icon(Icons.refresh),
          iconAlignment: IconAlignment.end,
          label: Text('Resend Code'),
        ),
        if (registerPersonNotifier.error != null) ...[
          SizedBox(height: 8),
          Text(
            registerPersonNotifier.error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
        SizedBox(height: 24),
        RichText(
          textScaler: MediaQuery.of(context).textScaler,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodySmall,
            children: [
              TextSpan(
                text: 'Note:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: ' If you did not receive our email:\n',
              ),
              TextSpan(
                text: '- Confirm that your email address was entered correctly.\n',
              ),
              TextSpan(
                text: '- Check your spam/junk/promotions folder.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
