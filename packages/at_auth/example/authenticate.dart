import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart' show AtRootDomain, AtsignString;
import 'package:at_utils/at_progress.dart';

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
    final atAuth = AtAuth.create();
    atAuth.progressStream.listen((ProgressEvent event) {
      print('Progress: ${event.group} : ${event.msg}');
    });
    final atsign = (argResults['atsign'] as String).toAtsign();

    // Throws AtAuthenticationException on failure; reaching here means the
    // atsign is authenticated.
    await atAuth.authenticate(
      atsign,
      AtRootDomain.atsignDomain,
      FileAtKeysIo(filePath: (_) => argResults['keysFilePath']),
    );

    // atAuth.atLookUp is the connection that just authenticated — hand it to
    // client creation rather than opening and PKAMing a second one.
    print('authenticated $atsign '
        '(enrollmentId: ${atAuth.atLookUp?.enrollmentId})');
  } on Exception catch (e, trace) {
    print(e);
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  }
}
