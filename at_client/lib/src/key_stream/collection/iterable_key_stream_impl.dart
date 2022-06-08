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
  }) : super(
          convert: convert,
          regex: regex,
          shouldGetKeys: shouldGetKeys,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          castTo: (values) => castTo<T>(values),
        );
}

@visibleForTesting
Iterable<T> castTo<T>(Iterable<T> values) => values;