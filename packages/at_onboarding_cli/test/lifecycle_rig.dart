import 'dart:io';

import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

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
  when(() => lookUp.isConnectionAvailable()).thenReturn(false);
  return lookUp;
}
