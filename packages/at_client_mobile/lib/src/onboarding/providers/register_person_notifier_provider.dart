import 'package:at_client_mobile/src/onboarding/notifiers/register_person_notifier.dart';
import 'package:flutter/widgets.dart';

class RegisterPersonNotifierProvider extends InheritedNotifier<RegisterPersonNotifier> {
  const RegisterPersonNotifierProvider({
    required RegisterPersonNotifier super.notifier,
    required super.child,
    super.key,
  });

  static RegisterPersonNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RegisterPersonNotifierProvider>()!.notifier!;
  }
}
