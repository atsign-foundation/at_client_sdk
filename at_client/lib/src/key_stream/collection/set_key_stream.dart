import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/set_key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

abstract class SetKeyStream<T> extends Stream<Set<T>> implements KeyStreamMixin<Set<T>> {
  /// Listens to notifications and exposes a Stream of the values stored as a Set.
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
  /// 
  /// {@macro KeyStreamGenerateRef}
  factory SetKeyStream({
    required T? Function(AtKey key, AtValue value) convert,
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
    String Function(AtKey key, AtValue value)? generateRef,
    AtClientManager? atClientManager,
  }) {
    return SetKeyStreamImpl<T>(
      regex: regex,
      convert: convert,
      generateRef: generateRef,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      shouldGetKeys: shouldGetKeys,
      atClientManager: atClientManager,
    );
  }
}
