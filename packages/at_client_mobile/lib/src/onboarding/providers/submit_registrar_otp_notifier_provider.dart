import 'package:at_client_mobile/src/onboarding/notifiers/submit_registrar_otp_notifier.dart';
import 'package:flutter/widgets.dart';

class SubmitRegistrarOtpNotifierProvider extends InheritedNotifier<SubmitRegistrarOtpNotifier> {
  const SubmitRegistrarOtpNotifierProvider({
    required SubmitRegistrarOtpNotifier super.notifier,
    required super.child,
    super.key,
  });

  static SubmitRegistrarOtpNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SubmitRegistrarOtpNotifierProvider>()!.notifier!;
  }
}
