import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/map_key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';


abstract class MapKeyStream<K, V> extends Stream<Map<K, V>> implements KeyStreamMixin<Map<K, V>> {
  factory MapKeyStream({
    String? regex,
    required MapEntry<K, V> Function(AtKey key, AtValue value) convert,
    String Function(AtKey key, AtValue value)? generateRef,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
  }) {
    return MapKeyStreamImpl<K, V>(
      regex: regex,
      convert: convert,
      generateRef: generateRef,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      shouldGetKeys: shouldGetKeys,
    );
  }
}
