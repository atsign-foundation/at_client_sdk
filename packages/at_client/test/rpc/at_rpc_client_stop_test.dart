import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockNotificationService extends Mock implements NotificationService {}

/// A client whose notify runs [notify], and the responses stream it listens
/// to. Closing that stream ends the responses.
(AtRpcClient, StreamController<AtNotification>) _client({
  required Future<NotificationResult> Function() notify,
  bool Function()? isStopped,
}) {
  final atClient = _MockAtClient();
  final notifications = _MockNotificationService();
  final responses = StreamController<AtNotification>.broadcast();

  when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
  when(() => atClient.isStopped).thenAnswer((_) => isStopped?.call() ?? false);
  when(() => atClient.notificationService).thenReturn(notifications);
  when(
    () => notifications.currentListenerState,
  ).thenReturn(NotificationListenerState.listening);
  when(
    () => notifications.currentListenerStateStream,
  ).thenAnswer((_) => const Stream.empty());
  when(
    () => notifications.subscribe(
      regex: any(named: 'regex'),
      shouldDecrypt: any(named: 'shouldDecrypt'),
    ),
  ).thenAnswer((_) => responses.stream);
  when(
    () => notifications.notify(
      any(),
      checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
      waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
      onSuccess: any(named: 'onSuccess'),
      onError: any(named: 'onError'),
      onSentToSecondary: any(named: 'onSentToSecondary'),
    ),
  ).thenAnswer((_) => notify());

  final client = AtRpcClient(
    serverAtsign: '@bob',
    atClient: atClient,
    baseNameSpace: 'testing',
    domainNameSpace: 'stop',
  );
  return (client, responses);
}

/// Runs [body], and returns the errors it left uncaught.
Future<List<Object>> _uncaught(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  unawaited(runZonedGuarded(() async {
    await body();
    done.complete();
  }, (e, _) => errors.add(e)));
  await done.future;
  await Future.delayed(const Duration(milliseconds: 10));
  return errors;
}

void main() {
  setUpAll(() => registerFallbackValue(NotificationParams()));

  group('AtRpcClient.call when the client stops', () {
    test(
      'a send that throws leaves no response pending, and nothing uncaught',
      () async {
        var stopped = false;
        late AtRpcClient client;
        final uncaught = await _uncaught(() async {
          final (c, responses) = _client(
            isStopped: () => stopped,
            notify: () async {
              stopped = true;
              throw StoppedException('notify stopped');
            },
          );
          client = c;
          await expectLater(
            client.call({'q': 1}),
            throwsA(isA<StoppedException>()),
          );
          await responses.close();
          await Future.delayed(const Duration(milliseconds: 10));
        });
        expect(client.completerMap, isEmpty);
        expect(uncaught, isEmpty);
      },
    );

    test(
      'responses ending while the send is in flight fail the call',
      () async {
        final uncaught = await _uncaught(() async {
          late StreamController<AtNotification> responses;
          final (client, r) = _client(
            notify: () async {
              await responses.close();
              await Future.delayed(const Duration(milliseconds: 10));
              return NotificationResult()
                ..notificationStatusEnum = NotificationStatusEnum.delivered;
            },
          );
          responses = r;
          await expectLater(
            client.call({'q': 2}),
            throwsA(isA<StoppedException>()),
          );
        });
        expect(uncaught, isEmpty);
      },
    );
  });
}
