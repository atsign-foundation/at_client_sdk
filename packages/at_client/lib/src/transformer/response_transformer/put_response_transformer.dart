import 'dart:async';

import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/transformer/at_transformer.dart';

/// Class responsible for transforming the put response.
class PutResponseTransformer implements Transformer<String, AtResponse> {
  @override
  FutureOr<AtResponse> transform(String value) {
    return DefaultResponseParser().parse(value);
  }
}
