import 'package:flutter/widgets.dart';

import '../notifiers/approved_requests_notifier.dart';

class ApprovedRequestsProvider extends InheritedNotifier<ApprovedRequestsNotifier> {
  const ApprovedRequestsProvider({
    required ApprovedRequestsNotifier super.notifier,
    required super.child,
    super.key,
  });

  static ApprovedRequestsNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ApprovedRequestsProvider>()!.notifier!;
  }
}
