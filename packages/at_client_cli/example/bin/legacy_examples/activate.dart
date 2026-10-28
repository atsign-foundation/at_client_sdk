import 'package:at_client/at_client_io.dart';
import 'package:at_client_cli/at_client_cli.dart';

/// Activates an atSign from its CRAM secret and reads back what the new
/// client holds; the keyfile lands at `~/.atsign/keys/<atSign>_key.atKeys`.
Future<void> main() async {
  const atSign = '@your_atsign_here';
  final preference = AtClientPreference()..namespace = 'your_namespace';

  final client = await Atsign(atSign).activate(
      cramSecret: '<your cram secret>',
      keys: CliKeys.fileFor(atSign),
      preference: preference,
      storage: CliKeys.storageFor(atSign, program: 'your_namespace'),
      lookUps: secureSocketLookUps(),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort));
  print(await client.getKeys());
  await client.stop();
}
