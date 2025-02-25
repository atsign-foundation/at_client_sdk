import 'package:at_client_mobile/src/onboarding/notifiers/cram_authentication_notifier.dart';
import 'package:flutter/widgets.dart';

class CramAuthenticationNotifierProvider extends InheritedNotifier<CramAuthenticationNotifier> {
  const CramAuthenticationNotifierProvider({
    required CramAuthenticationNotifier super.notifier,
    required super.child,
    super.key,
  });

  static CramAuthenticationNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CramAuthenticationNotifierProvider>()!.notifier!;
  }
}
