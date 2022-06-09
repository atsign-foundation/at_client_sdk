import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/key_stream_mixin.dart';
import 'package:meta/meta.dart';

class KeyStreamIterableBase<T, I extends Iterable<T>> extends KeyStreamMixin<I> implements Stream<I> {
  @visibleForTesting
  final Map<String, T> store = {};

  final I Function(Iterable<T> values) _castTo;
  final String Function(AtKey key, AtValue value) _generateRef;

  @override
  void handleNotification(AtKey key, AtValue value, String? operation) {
    switch (operation) {
      case 'delete':
      case 'remove':
        store.remove(_generateRef(key, value));
        break;
      case 'init':
      case 'update':
      case 'append':
      default:
        store[_generateRef(key, value)] = convert(key, value)! as T;
    }
    print(_castTo(store.values));
    print(store);
    controller.add(_castTo(store.values));
  }

  KeyStreamIterableBase({
    required T? Function(AtKey, AtValue) convert,
    String? regex,
    bool shouldGetKeys = true,
    String? sharedBy,
    String? sharedWith,
    String Function(AtKey key, AtValue value)? generateRef,
    I Function(Iterable<T> values)? castTo,
  })  : _generateRef = generateRef ?? ((key, value) => key.key ?? ''),
        _castTo = castTo ?? ((Iterable<T> values) => values as I),
        super(
          convert: convert,
          regex: regex,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          shouldGetKeys: shouldGetKeys,
        );
}
