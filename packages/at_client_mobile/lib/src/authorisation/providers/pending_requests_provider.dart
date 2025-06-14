import 'package:flutter/widgets.dart';

import '../notifiers/pending_requests_notifier.dart';

class PendingRequestsProvider
    extends InheritedNotifier<PendingRequestsNotifier> {
  const PendingRequestsProvider({
    required PendingRequestsNotifier super.notifier,
    required super.child,
    super.key,
  });

  static PendingRequestsNotifier of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PendingRequestsProvider>()!
        .notifier!;
  }
}
