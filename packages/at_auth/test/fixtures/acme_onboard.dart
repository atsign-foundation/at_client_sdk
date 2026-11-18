import 'dart:isolate';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;

import '../test_utils/fake_cram_at_server.dart';

/// A program that activates an atSign through at_auth alone, passing no
/// client config, and sends back every `from:` its atServer received, or what
/// went wrong.
Future<void> main(List<String> args, SendPort results) async {
  final atServer = FakeCramAtServer('@alice', cramReply: 'data:success');
  final lookUp = atServer.lookUp();
  try {
    await activateAtSign(
        atSign: '@alice',
        cramSecret: 'the-one-time-secret',
        // ignore: invalid_use_of_visible_for_testing_member
        keys: InMemoryAtKeysIo(),
        signingAlgo: SigningAlgoType.rsa2048,
        atLookUp: lookUp);
    results.send({'froms': atServer.froms.toList()});
  } catch (e) {
    results.send({'error': '$e'});
  } finally {
    await lookUp.close();
  }
}
