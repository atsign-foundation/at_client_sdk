import 'dart:async';

import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

export 'collection/collection.dart';

abstract class KeyStream<T> extends Stream<T?> implements KeyStreamMixin<T?> {
  /// Listens to notifications and exposes a Stream of the values.
  /// 
  /// {@macro KeyStreamConvert}
  /// 
  /// {@macro KeyStreamRegex}
  /// 
  /// {@macro KeyStreamSharedBy}
  /// 
  /// {@macro KeyStreamSharedBy}
  /// 
  /// {@macro KeyStreamShouldGetKeys}
  factory KeyStream({
    required T? Function(AtKey key, AtValue value) convert,
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
  }) {
    return KeyStreamImpl(
      regex: regex,
      convert: convert,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      shouldGetKeys: shouldGetKeys,
    );
  }

}
