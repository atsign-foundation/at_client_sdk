import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_commons/at_commons.dart' show AtRootDomain;

/// Perform authentication for an onboarded atsign
/// 1. Read the PKAM private key from atKeys file saved after running onboard.dart
/// 2. Perform PKAM authentication
/// 3. Listening to new enrollment notifications
/// Usage: `dart authenticate.dart -a <atsign> -k <path_to_atkeys_file>`
void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption('keysFilePath',
          abbr: 'k', help: 'Path of .atKeys file', mandatory: true);
    final argResults = parser.parse(args);
    final atAuth = AtAuthImpl();
    final atSign = argResults['atsign'];
    final atAuthRequest = AtAuthRequest(atSign)
      ..rootDomain = AtRootDomain('root.atsign.org', 64)
      ..atKeysIo = FileAtKeysIo(filePath: argResults['keysFilePath']);
    final atAuthResponse = await atAuth.authenticate(atAuthRequest);
    print('atAuthResponse: $atAuthResponse');
  } on Exception catch (e, trace) {
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  }
}
