import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

/// Activates an atSign from its CRAM secret and reads back what the new
/// client holds; the keyfile lands in the home directory's keys folder.
Future<void> main() async {
  const atSign = '@your_atsign_here';
  final preference = AtOnboardingPreference()
    ..namespace =
        'your_namespace' // unique identifier that can be used to identify data from your app
    ..storagePath = 'storage/$atSign';

  final client = await Atsign(atSign).activate(
      cramSecret: '<your cram secret>',
      keys: FileAtKeysIo(),
      preference: preference,
      storage: preference.storageFor(atSign));
  print(await client.getKeys());
  await client.stop();
}
