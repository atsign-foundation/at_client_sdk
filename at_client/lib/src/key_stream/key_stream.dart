import 'dart:async';

import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/key_stream/key_stream_impl.dart';
import 'package:at_client/src/key_stream/key_stream_mixin.dart';

export 'collection/collection.dart';

/// Class to expose a stream of [AtKey](s) based on the provided query parameters
///
/// [KeyStream] exposes a stream where each stream element represents data for a single [AtKey]
///
/// {@template KeyStream}
/// Pass the [convert] callback function to define how an [AtKey] and [AtValue] will converted into elements of the
/// stream. To filter [AtKey]s that will be included in this stream, you may apply a custom [regex] filter, or pass in
/// [sharedBy] and/or [sharedWith] atSigns. By default [shouldGetKeys] is enabled, which will initially populate the
/// stream with available keys that match the [regex], [sharedBy], and [sharedWith] filters. You may also override
/// the [atClientManager] if necessary.
/// {@endtemplate}
///
/// In addition to [KeyStream], there are collection based versions for [Iterable], [List], [Set], and [Map] represented
/// by [IterableKeyStream], [ListKeyStream], [SetKeyStream], and [MapKeyStream] respectively.
///
/// [KeyStream]s can be used with Flutter's [StreamBuilder]s to achieve seamless data flow from the at_client straight
/// to the user interface. For example, to get a stream containing all messages from '@alice' to '@bob' in a list:
///
/// ```
/// ListKeyStream stream = ListKeyStream(
///   convert: (key, value) => value,
///   regex: r'\.message',
///   sharedBy: '@alice',
///   sharedWith: '@bob'
/// );
/// ```
abstract class KeyStream<T> extends Stream<T?> implements KeyStreamMixin<T?> {
  /// Create a [KeyStream] instance
  ///
  /// {@macro KeyStream}
  factory KeyStream({
    required T? Function(AtKey key, AtValue value) convert,
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool shouldGetKeys = true,
    AtClientManager? atClientManager,
  }) {
    return KeyStreamImpl(
      regex: regex,
      convert: convert,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      shouldGetKeys: shouldGetKeys,
      atClientManager: atClientManager,
    );
  }
}
