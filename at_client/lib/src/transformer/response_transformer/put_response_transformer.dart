import 'dart:async';

import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/transformer/at_transformer.dart';

/// Class responsible for transforming the put response.
class PutResponseTransformer implements Transformer<String, AtResponse> {
  @override
  FutureOr<AtResponse> transform(String value) {
    // If the put response is null or empty put failed, return false.
    // If put response contains the non null response(commitId), return true.
    return DefaultResponseParser().parse(value);
  }
}
