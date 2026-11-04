import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';

import 'test_util.dart';
import '../test_utils/no_keys.dart';
import '../test_utils/transport.dart';

void main() async {
  try {
    final atsign = '@alice🛠';
    final preference = TestUtil.getPreferenceRemote();
    var atClientManager = AtClientManager.getInstance()
      ..use(await buildAtClient(
          atSign: atsign,
          namespace: 'wavi',
          preference: preference,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(preference),
          atKeysIo: noKeysFor(atsign),
          storage: InMemoryAtClientStorage(atSign: atsign)));
    var atClient = atClientManager.atClient;
    var statsResult = await atClient
        .getRemoteSecondary()!
        .executeCommand('stats\n', auth: true);
    print(statsResult);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
