import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/map_key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

abstract class MapKeyStream<K, V> extends Stream<Map<K, V>> implements KeyStreamMixin<Map<K, V>> {
  /// Listens to notifications and exposes a Stream of the values stored as a Map.
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
  factory MapKeyStream({
    required MapEntry<K, V>? Function(AtKey key, AtValue value) convert,
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
    String Function(AtKey key, AtValue value)? generateRef,
    AtClientManager? atClientManager,
  }) {
    return MapKeyStreamImpl<K, V>(
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
