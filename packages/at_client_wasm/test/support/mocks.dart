import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

void _answerCommandsWithNothing(AtLookUp lookUp) {
  when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
      .thenAnswer((_) async => null);
}

class MockAtLookupImpl extends Mock implements AtLookupImpl {
  MockAtLookupImpl() {
    _answerCommandsWithNothing(this);
  }
}

class MockRemoteSecondary extends Mock implements RemoteSecondary {
  MockRemoteSecondary() {
    when(() => closeConnection()).thenAnswer((_) async {});
    final atLookUp = MockAtLookupImpl();
    // ignore: deprecated_member_use
    when(() => atLookUp.enrollmentId).thenReturn(null);
    when(() => this.atLookUp).thenReturn(atLookUp);
  }
}
