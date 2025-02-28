import 'package:flutter/widgets.dart';

import '../notifiers/authenticate_atsign_notifier.dart';

class AuthenticateAtsignNotifierProvider extends InheritedNotifier<AuthenticateAtsignNotifier> {
  const AuthenticateAtsignNotifierProvider({
    required AuthenticateAtsignNotifier super.notifier,
    required super.child,
    super.key,
  });

  static AuthenticateAtsignNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AuthenticateAtsignNotifierProvider>()!.notifier!;
  }
}
