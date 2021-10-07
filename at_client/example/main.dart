import 'dart:async';

import 'package:at_client/at_client.dart';

Future<void> main(List<String> arguments) async {
  var preference = AtClientPreference();
  //creating client for alice
  // buzz is the namespace
  final atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign('@alice', 'buzz', preference);
  print(await atClientManager.atClient.getKeys());
}
