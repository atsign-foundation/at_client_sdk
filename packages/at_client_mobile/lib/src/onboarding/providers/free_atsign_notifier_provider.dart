import 'package:at_client_mobile/src/onboarding/notifiers/free_atsign_notifier.dart';
import 'package:flutter/widgets.dart';

class FreeAtsignNotifierProvider extends InheritedNotifier<FreeAtsignNotifier> {
  const FreeAtsignNotifierProvider({
    required FreeAtsignNotifier super.notifier,
    required super.child,
    super.key,
  });

  static FreeAtsignNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FreeAtsignNotifierProvider>()!.notifier!;
  }
}
