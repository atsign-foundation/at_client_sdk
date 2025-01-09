import 'package:flutter/widgets.dart';

import '../notifiers/spp_notifier.dart';

class SppProvider extends InheritedNotifier<SppNotifier> {
  const SppProvider({
    required SppNotifier super.notifier,
    required super.child,
    super.key,
  });

  static SppNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SppProvider>()!.notifier!;
  }
}
