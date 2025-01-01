import 'package:apkam_example/authorisation/notifiers/spp_notifier.dart';
import 'package:flutter/widgets.dart';

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
