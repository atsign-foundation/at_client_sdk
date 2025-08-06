import 'dart:async';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:mocktail/mocktail.dart';

int mockSocketNumber = 1;

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockSecondaryUrlFinder extends Mock implements SecondaryUrlFinder {}

class MockSecureSocketFactory extends Mock
    implements AtLookupSecureSocketFactory {}

class MockStreamSubscription<T> extends Mock implements StreamSubscription<T> {}

class MockSecureSocket extends Mock implements SecureSocket {
  bool destroyed = false;
  int mockNumber = mockSocketNumber++;
}

class MockSecureSocketListenerFactory extends Mock
    implements AtLookupSecureSocketListenerFactory {}

class MockOutboundConnectionFactory extends Mock
    implements AtLookupOutboundConnectionFactory {}

class MockOutboundMessageListener extends Mock
    implements OutboundMessageListener {}

class MockAtChops extends Mock implements AtChopsImpl {}

class MockOutboundConnectionImpl extends Mock
    implements OutboundConnectionImpl {}

SecureSocket createMockAtServerSocket(String address, int port) {
  SecureSocket mss = MockSecureSocket();
  when(() => mss.destroy()).thenAnswer((invocation) {
    (mss as MockSecureSocket).destroyed = true;
  });
  when(() => mss.setOption(SocketOption.tcpNoDelay, true)).thenReturn(true);
  when(() => mss.remoteAddress).thenReturn(InternetAddress('127.0.0.66'));
  when(() => mss.remotePort).thenReturn(port);
  when(() => mss.listen(any(),
      onError: any(named: "onError"),
      onDone: any(named: "onDone"))).thenReturn(MockStreamSubscription());
  return mss;
}
