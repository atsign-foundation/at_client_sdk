import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/iterable_key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

abstract class IterableKeyStream<T> extends Stream<Iterable<T>> implements KeyStreamMixin<Iterable<T>> {
  factory IterableKeyStream({
    required T? Function(AtKey key, AtValue value) convert,
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
    String Function(AtKey key, AtValue value)? generateRef,
  }) {
    return IterableKeyStreamImpl<T>(
      regex: regex,
      convert: convert,
      generateRef: generateRef,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      shouldGetKeys: shouldGetKeys,
    );
  }
}
