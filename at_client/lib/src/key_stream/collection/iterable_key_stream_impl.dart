import 'dart:async';

import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/iterable_key_stream.dart';
import 'package:at_client/src/key_stream/key_stream_iterable_base.dart';
import 'package:meta/meta.dart';

class IterableKeyStreamImpl<T> extends KeyStreamIterableBase<T, Iterable<T>> implements IterableKeyStream<T> {
  IterableKeyStreamImpl({
    required T? Function(AtKey, AtValue) convert,
    String? regex,
    bool shouldGetKeys = true,
    String? sharedBy,
    String? sharedWith,
    String Function(AtKey key, AtValue value)? generateRef,
    FutureOr<void> Function(Object exception, [StackTrace? stackTrace])? onError,
    AtClientManager? atClientManager,
  }) : super(
          convert: convert,
          regex: regex,
          shouldGetKeys: shouldGetKeys,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          generateRef: generateRef,
          castTo: (values) => castTo<T>(values),
          onError: onError,
          atClientManager: atClientManager,
        );
}

@visibleForTesting
Iterable<T> castTo<T>(Iterable<T> values) => [...values];
