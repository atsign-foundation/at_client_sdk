import 'package:flutter/widgets.dart';

import '../notifiers/keys_upload_notifier.dart';

class KeysUploadNotifierProvider extends InheritedNotifier<KeysUploadNotifier> {
  const KeysUploadNotifierProvider({
    required KeysUploadNotifier super.notifier,
    required super.child,
    super.key,
  });

  static KeysUploadNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<KeysUploadNotifierProvider>()!.notifier!;
  }
}
