import 'dart:async';

import 'package:at_client/src/client/request_options.dart';

/// Class responsible for Transforming the data.
abstract class Transformer<T, V> {
  /// Accepts the data of type <T> transform's to type <V>
  FutureOr<V> transform(T value);
}

abstract class RequestTransformer<T, V> extends Transformer<T, V> {
  @override
  FutureOr<V> transform(T value, {RequestOptions? requestOptions});
}
