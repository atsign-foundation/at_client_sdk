import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/set_key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

abstract class SetKeyStream<T> extends Stream<Set<T>> implements KeyStreamMixin<Set<T>> {
  factory SetKeyStream({
    required T? Function(AtKey key, AtValue value) convert,
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
    String Function(AtKey key, AtValue value)? generateRef,
  }) {
    return SetKeyStreamImpl<T>(
      regex: regex,
      convert: convert,
      generateRef: generateRef,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      shouldGetKeys: shouldGetKeys,
    );
  }
}
