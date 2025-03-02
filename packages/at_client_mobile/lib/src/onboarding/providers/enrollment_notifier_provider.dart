import 'package:flutter/widgets.dart';

import '../notifiers/enrollment_notifier.dart';

class EnrollmentNotifierProvider extends InheritedNotifier<EnrollmentNotifier> {
  const EnrollmentNotifierProvider({
    required EnrollmentNotifier super.notifier,
    required super.child,
    super.key,
  });

  static EnrollmentNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EnrollmentNotifierProvider>()!.notifier!;
  }
}
