import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

class KeyStreamImpl<T> extends KeyStreamMixin<T?> implements KeyStream<T> {
  @override
  void handleStreamEvent(AtKey key, AtValue value, KeyStreamOperation operation) {
    T? data = convert(key, value);
    if (data == null) return controller.add(null);
    switch (operation) {
      case KeyStreamOperation.none:
      // TODO this is the resulting value from CommitOp being null, i.e. keyInfo.operation == null
      // Should I assume that the Key is bad and should be removed from the stream, OR
      // Should I do nothing to the Key... can CommitOp even be null here?
      case KeyStreamOperation.delete:
        return controller.add(null);
      default:
        controller.add(data);
    }
  }

  KeyStreamImpl({
    required T? Function(AtKey, AtValue) convert,
    String? regex,
    bool shouldGetKeys = true,
    String? sharedBy,
    String? sharedWith,
    FutureOr<void> Function(Object exception, [StackTrace? stackTrace])? onError,
    AtClientManager? atClientManager,
  }) : super(
          convert: convert,
          regex: regex,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          shouldGetKeys: shouldGetKeys,
          onError: onError,
          atClientManager: atClientManager,
        );
}
