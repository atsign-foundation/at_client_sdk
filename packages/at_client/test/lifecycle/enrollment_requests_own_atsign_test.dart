import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/recorded_logs.dart';

/// Catalogue: features/enrollment/requests_from_own_atsign.feature
void main() {
  const alice = '@alice';
  const id = 'e0e0e0e0-1a2e-43e4-93bd-378f1d366ea7';
  final logs = RecordedLogs();
  late MockAtClient client;
  late MockNotificationService notifications;

  setUpAll(() => logs.installOn());

  setUp(() {
    logs.records.clear();
    client = MockAtClient();
    notifications = MockNotificationService();
    when(() => client.getCurrentAtSign()).thenReturn(alice);
    when(() => client.notificationService).thenReturn(notifications);
  });

  AtNotification request(String from, String key) => AtNotification('n-$from',
      key, from, alice, DateTime.now().millisecondsSinceEpoch, 'key', false)
    ..value = jsonEncode({
      'appName': 'wavi',
      'deviceName': 'phone',
      'namespace': {'wavi': 'rw'},
    });

  void deliver(List<AtNotification> delivered) =>
      when(() => notifications.subscribe(
              regex: any(named: 'regex'),
              shouldDecrypt: any(named: 'shouldDecrypt')))
          .thenAnswer((_) => Stream.fromIterable(delivered));

  test('a request announced by the client\'s own atSign is reported', () async {
    deliver([request(alice, '$id.new.enrollments.__manage$alice')]);

    final reported = await client.enrollments.requests.toList();

    expect(reported.map((e) => e.enrollmentId), [id],
        reason: 'a request the client\'s own atSign announces is reported');
    expect(logs.at('WARNING'), isEmpty,
        reason: 'a request from the client\'s own atSign is not dropped');
  });

  test(
      'a matching notification from another atSign is dropped, and the drop '
      'is logged', () async {
    const key = '$alice:$id.new.enrollments.__manage@bob';
    deliver([request('@bob', key)]);

    final reported = await client.enrollments.requests.toList();

    expect(reported, isEmpty,
        reason: 'requests reports only notifications from the client\'s own '
            'atSign');
    expect(logs.at('WARNING'), contains(allOf(contains('@bob'), contains(key))),
        reason: 'the drop is logged at warning, naming the sender and the key');
  });

  group('Given an AtClient listening on Enrollments.requests', () {
    test(
        'when a request arrives from @Alice for a client of @alice, then it '
        'is reported', () async {
      deliver([request('@Alice', '$id.new.enrollments.__manage$alice')]);

      final reported = await client.enrollments.requests.toList();

      expect(reported.map((e) => e.enrollmentId), [id],
          reason: 'the sender is compared in canonical form');
    });

    test(
        'when a request arrives from @alice for a client of @Alice, then it '
        'is reported', () async {
      when(() => client.getCurrentAtSign()).thenReturn('@Alice');
      deliver([request(alice, '$id.new.enrollments.__manage$alice')]);

      final reported = await client.enrollments.requests.toList();

      expect(reported.map((e) => e.enrollmentId), [id],
          reason: 'the client\'s atSign is compared in canonical form');
    });

    test(
        'when a matching notification names no atSign as its sender, then it '
        'is dropped and logged, and the next request is reported', () async {
      const next = 'e1e1e1e1-1a2e-43e4-93bd-378f1d366ea7';
      deliver([
        request('', '$id.new.enrollments.__manage$alice'),
        request(alice, '$next.new.enrollments.__manage$alice'),
      ]);

      final reported = await client.enrollments.requests.toList();

      expect(reported.map((e) => e.enrollmentId), [next],
          reason: 'a sender that is not an atSign is not the client\'s own '
              'atSign, and dropping it leaves the subscription running');
      expect(logs.at('WARNING'),
          contains(contains('$id.new.enrollments.__manage$alice')),
          reason: 'the drop is logged at warning, naming the key');
    });
  });
}
