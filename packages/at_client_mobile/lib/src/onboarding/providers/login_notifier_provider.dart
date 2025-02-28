import 'package:at_client_mobile/src/onboarding/notifiers/login_notifier.dart';
import 'package:flutter/widgets.dart';

class LoginNotifierProvider extends InheritedNotifier<LoginNotifier> {
  const LoginNotifierProvider({
    required LoginNotifier super.notifier,
    required super.child,
    super.key,
  });

  static LoginNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LoginNotifierProvider>()!.notifier!;
  }
}
