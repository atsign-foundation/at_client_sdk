import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;

/// Activates [atSign] with the CRAM secret on [preference], writing its first
/// keys to the keyfile the preference names, and stops the client the
/// activation opened once its startup has settled; a test opens its own
/// afterwards, the way a program does.
Future<void> activateThroughCli(
    String atSign, AtOnboardingPreference preference) async {
  final client = await Atsign(atSign).activate(
      cramSecret: preference.cramSecret!,
      keys: FileAtKeysIo(
          filePath: (_) => preference.atKeysFilePath!,
          passPhrase: preference.passPhrase),
      preference: preference,
      storage: preference.storageFor(atSign));
  await auth_cli.awaitStartupTail(client);
  await client.stop();
}

/// The store the enrollment verbs write into for the keyfile [preference]
/// names.
FileAtKeysIo keyfileOf(AtOnboardingPreference preference) => FileAtKeysIo(
    filePath: (_) => preference.atKeysFilePath!,
    passPhrase: preference.passPhrase);
