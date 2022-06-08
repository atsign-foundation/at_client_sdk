import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/key_stream_mixin.dart';
import 'package:meta/meta.dart';

class KeyStreamMapBase<K, V, I extends Map<K, V>> extends KeyStreamMixin<I> implements Stream<I> {
  @visibleForTesting
  final Map<String, MapEntry<K, V>> store = {};

  final I Function(Iterable<MapEntry<K, V>> values) _castTo;
  final String Function(AtKey key, AtValue value) _generateRef;

  @override
  void handleNotification(AtKey key, AtValue value, String? operation) {
    MapEntry<K, V>? data = convert(key, value);
    switch (operation) {
      case 'delete':
      case 'remove':
        store.remove(_generateRef(key, value));
        break;
      case 'init':
      case 'update':
      case 'append':
      default:
        store[_generateRef(key, value)] = data!;
    }
    controller.add(_castTo(store.values));
  }

  KeyStreamMapBase({
    required MapEntry<K, V>? Function(AtKey, AtValue) convert,
    String? regex,
    bool shouldGetKeys = true,
    String? sharedBy,
    String? sharedWith,
    String Function(AtKey key, AtValue value)? generateRef,
    I Function(Iterable<MapEntry<K, V>> values)? castTo,
  })  : _generateRef = generateRef ?? ((key, value) => key.key ?? ''),
        _castTo = castTo ?? ((Iterable<MapEntry<K, V>> values) => values as I),
        super(
          convert: convert,
          regex: regex,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          shouldGetKeys: shouldGetKeys,
        );
}
