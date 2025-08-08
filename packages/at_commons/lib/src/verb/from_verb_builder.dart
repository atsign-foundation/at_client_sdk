import 'dart:convert';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/src/at_constants.dart';

class FromVerbBuilder implements VerbBuilder {
  late String atSign;

  /// Stores the client configurations. Defaults to empty Map.
  Map<String, dynamic> clientConfig = {};

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('from:$atSign');
    if (clientConfig.isNotEmpty) {
      var clientConfigStr = jsonEncode(clientConfig);
      serverCommandBuffer
          .write(':${AtConstants.clientConfig}:$clientConfigStr');
    }
    serverCommandBuffer.write('\n');
    return serverCommandBuffer.toString();
  }

  @override
  bool checkParams() {
    return atSign.isNotEmpty;
  }
}
