import 'dart:async';

/// Class responsible for Transforming the data.
abstract class Transformer<T, V> {
  /// Accepts the data of type <T> transform's to type <V>
  FutureOr<V> transform(T value);
}
