import 'package:flutter/widgets.dart';

import '../notifiers/active_otp_notifier.dart';

class ActiveOtpProvider extends InheritedNotifier<ActiveOtpNotifier> {
  const ActiveOtpProvider({
    required ActiveOtpNotifier super.notifier,
    required super.child,
    super.key,
  });

  static ActiveOtpNotifier of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ActiveOtpProvider>()!
        .notifier!;
  }
}
