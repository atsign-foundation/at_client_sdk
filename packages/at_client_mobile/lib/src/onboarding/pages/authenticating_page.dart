import 'package:at_client_mobile/src/onboarding/notifiers/login_notifier.dart';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../providers/authenticate_atsign_notifier_provider.dart';
import '../providers/login_notifier_provider.dart';
import '../providers/selected_atsign_notifier_provider.dart';

class AuthenticatingPage extends StatefulWidget {
  const AuthenticatingPage({
    required this.onCramKeyReceived,
    super.key,
  });

  final void Function(String cramSecret, String atSign) onCramKeyReceived;

  @override
  AuthenticatingPageState createState() => AuthenticatingPageState();
}

class AuthenticatingPageState extends State<AuthenticatingPage> {
  late TextEditingController _controller;

  static const _pinLength = 4;

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

  String loadingMessage(LoginStatus loginStatus) {
    switch (loginStatus) {
      case LoginStatus.contactingServer:
        return 'Contacting atServer...';
      case LoginStatus.fetchingKeys:
        return 'Fetching keys...';
      case LoginStatus.authenticating:
        return 'Authenticating...';
      case LoginStatus.authenticated:
        return 'Authenticated';
      case LoginStatus.cramAuthenticating:
        return 'CRAM Authentication...';
      case LoginStatus.otpRequired:
        return 'OTP Required';
      case LoginStatus.enrollmentRequired:
        return 'Enrollment Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginNotifier = LoginNotifierProvider.of(context);
    final authenticateAtsignNotifier = AuthenticateAtsignNotifierProvider.of(context);
    if (loginNotifier.status == LoginStatus.otpRequired) {
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
            length: _pinLength,
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
          Text('A verification code has been sent to your email.'),
          SizedBox(height: 8),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final enoughChars = _controller.text.length == _pinLength;
              return FilledButton.icon(
                onPressed: enoughChars && !authenticateAtsignNotifier.isFetching
                    ? () async {
                        final atSign = SelectedAtsignNotifierProvider.of(context).value!;
                        print(atSign);
                        await authenticateAtsignNotifier.submitOtp(
                          otp: _controller.text,
                          atSign: atSign,
                        );
                        if (authenticateAtsignNotifier.error == null) {
                          widget.onCramKeyReceived(
                            authenticateAtsignNotifier.cramSecret!,
                            SelectedAtsignNotifierProvider.of(context).value!,
                          );
                        }
                      }
                    : null,
                icon: Icon(Icons.arrow_forward),
                iconAlignment: IconAlignment.end,
                label: Text('Submit'),
              );
            },
          ),
          if (authenticateAtsignNotifier.error != null) ...[
            SizedBox(height: 8),
            Text(
              authenticateAtsignNotifier.error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            SizedBox(height: 8),
          ],
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 8),
        Text(
          loadingMessage(loginNotifier.status),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        )
      ],
    );
  }
}
