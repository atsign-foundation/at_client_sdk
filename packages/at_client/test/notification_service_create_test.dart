import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';
import 'test_utils/transport.dart';

/// What `NotificationServiceImpl.create` needs to build a monitor of its own.
void main() {
  group('Given a client and no monitor', () {
    test(
        'when the service is created with no lookUps, then it is refused by '
        'name before anything is built', () async {
      final atClient = MockAtClientImpl();
      when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => atClient.atSign).thenReturn('@alice'.toAtsign());
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());

      await expectLater(
          NotificationServiceImpl.create(atClient,
              secondaryAddressFinder: defaultAtDirectory),
          throwsA(
              isA<ArgumentError>().having((e) => e.name, 'name', 'lookUps')));
      verifyNever(() => atClient.getPreferences());
    });
  });
}
