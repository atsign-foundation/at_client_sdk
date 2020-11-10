import 'package:at_client/at_client.dart';

Future<void> main(List<String> arguments) async {
  var preference = AtClientPreference();
  //creating client for alice
  // buzz is the namespace
  await AtClientImpl.createClient('@alice', 'buzz', preference);
  var atClient = await AtClientImpl.getClient('@alice');
  print(await atClient.getKeys());
}
