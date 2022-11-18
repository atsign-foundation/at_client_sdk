import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';
import 'package:meta/meta.dart';

class KeyStreamIterableBase<T, I extends Iterable<T>> extends KeyStreamMixin<I> implements Stream<I> {
  @visibleForTesting
  final Map<String, T> store = {};

  /// {@template KeyStreamCastTo}
  ///
  /// The [castTo] function defines how [store.entries] is cast before being added to the Stream.
  ///
  /// {@endtemplate}
  final I Function(Iterable<T> values) _castTo;

  /// {@template KeyStreamGenerateRef}
  ///
  /// The [generateRef] function defines how keys for [store] are created.
  ///
  /// In some cases, [key.key] (default) is not sufficient if you are receiving data from multiple atsigns.
  /// This function can be declared if you would like to change how the key for the internal store is generated.
  ///
  /// {@endtemplate}
  final String Function(AtKey key, AtValue value) _generateRef;

  @override
  void handleStreamEvent(AtKey key, AtValue value, KeyStreamOperation operation) {
    switch (operation) {
      case KeyStreamOperation.none:
      // TODO this is the resulting value from CommitOp being null, i.e. keyInfo.operation == null
      // Should I assume that the Key is bad and should be removed from the stream, OR
      // Should I do nothing to the Key... can CommitOp even be null here?
      case KeyStreamOperation.delete:
        store.remove(_generateRef(key, value));
        break;
      default:
        store[_generateRef(key, value)] = convert(key, value)! as T;
    }
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
    FutureOr<void> Function(Object exception, [StackTrace? stackTrace])? onError,
    AtClientManager? atClientManager,
  })  : _generateRef = generateRef ?? ((key, value) => key.key ?? ''),
        _castTo = castTo ?? ((Iterable<T> values) => values as I),
        super(
          convert: convert,
          regex: regex,
          sharedBy: sharedBy,
          sharedWith: sharedWith,
          shouldGetKeys: shouldGetKeys,
          onError: onError,
          atClientManager: atClientManager,
        );
}
