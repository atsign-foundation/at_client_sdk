import 'package:at_client/at_client.dart';
import 'package:at_client/remote_only.dart';

import 'common.dart';

Future<void> main() async {
  final remote = RemoteSecondary('@payload', AtClientPreference());
  await exercise(
      RemoteOnlyAtClientStorage(atSign: '@payload', remoteSecondary: remote));
}
