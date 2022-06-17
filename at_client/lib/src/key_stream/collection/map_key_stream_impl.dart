import 'dart:core';

import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/collection/map_key_stream.dart';
import 'package:at_client/src/key_stream/key_stream_map_base.dart';
import 'package:meta/meta.dart';

class MapKeyStreamImpl<K, V> extends KeyStreamMapBase<K, V, Map<K, V>> implements MapKeyStream<K, V> {
  MapKeyStreamImpl({
    required MapEntry<K, V>? Function(AtKey, AtValue) convert,
    String? regex,
    bool shouldGetKeys = true,
    String? sharedBy,
    String? sharedWith,
    String Function(AtKey key, AtValue value)? generateRef,
    AtClientManager? atClientManager,
  }) : super(
          convert: convert,
          regex: regex,
          shouldGetKeys: shouldGetKeys,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          castTo: (values) => castTo<K, V>(values),
          atClientManager: atClientManager,
        );
}

@visibleForTesting
Map<K, V> castTo<K, V>(Iterable<MapEntry<K, V>> values) => Map.fromEntries(values);
