import 'dart:io';

import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

/// Answers a challenge-response without an atServer.
///
/// The `from:` reply has to be well formed — at_auth refuses to sign a
/// challenge that does not carry a uuid and this atSign — or every arm fails
/// for that reason instead of the one under test.
class OfflineExchange implements AtCommandExecutor {
  OfflineExchange(this.atSign);

  final String atSign;
  final List<String> sent = [];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command.trim());
    if (command.startsWith('from:')) {
      return 'data:_6c9f8b1e-6f7a-4d3b-9a1a-2f5e7c8d9012$atSign'
          ':b2d4a6c8-1e3f-4a5b-8c7d-9e0f1a2b3c4d';
    }
    return 'data:success';
  }
}

/// A port on the loopback interface that nothing listens on, so a connect to
/// it is refused at once.
Future<int> refusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// A lookup whose PKAM attempt does what [onPkam] says.
MockAtLookupImpl lookUpAnswering(Future<bool> Function() onPkam) {
  final lookUp = MockAtLookupImpl();
  when(() => lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
      .thenAnswer((_) => onPkam());
  when(() => lookUp.close()).thenAnswer((_) async {});
  when(() => lookUp.dropConnection()).thenAnswer((_) async {});
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  return lookUp;
}
