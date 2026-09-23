import 'dart:async';

import 'package:at_client/at_client.dart' show AtNotification;
import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence_sqlite.dart';
import 'package:at_telemetry_service/at_telemetry_service.dart';
import 'package:test/test.dart';

void main() {
  const AtTelemetryNotificationCodec codec = AtTelemetryNotificationCodec();
  final AtTelemetryEvent event = AtTelemetryEvent(
    name: 'atsign.app.started',
    timestamp: DateTime.utc(2026, 2, 25, 9),
    attributes: const <String, Object?>{
      'app.version': '1.2.3',
      'tenant.id': 'tenant-b',
    },
  );

  late AtTelemetrySqlitePersistence persistence;
  late List<AtTelemetryNotificationOutcome> outcomes;
  late AtTelemetryNotificationReceiver receiver;

  setUp(() {
    persistence = AtTelemetrySqlitePersistence.inMemory();
    outcomes = <AtTelemetryNotificationOutcome>[];
    receiver = AtTelemetryNotificationReceiver(
      authenticator: AtTelemetryAtsignAuthenticator(
        <AtTelemetryAtsignCredential>[
          AtTelemetryAtsignCredential(atsign: '@alice', tenantId: 'tenant-a'),
        ],
      ),
      ingestor: AtTelemetryIngestor(persistence: persistence),
      maxPayloadCharacters: 4096,
      onOutcome: (
        AtNotification notification,
        AtTelemetryNotificationOutcome outcome,
      ) {
        outcomes.add(outcome);
      },
    );
  });

  tearDown(() async {
    await persistence.close();
  });

  Future<List<AtTelemetryRecord>> recordsFor(String tenantId) {
    return persistence.query(AtTelemetryQuery(tenantId: tenantId));
  }

  test('stores events from an allowed Atsign under its configured tenant',
      () async {
    final AtTelemetryNotificationOutcome outcome = await receiver.handle(
      _notification(
          from: '@Alice', value: codec.encode(<AtTelemetryEvent>[event])),
    );

    expect(outcome, AtTelemetryNotificationOutcome.accepted);
    expect(outcomes, <AtTelemetryNotificationOutcome>[outcome]);
    final List<AtTelemetryRecord> records = await recordsFor('tenant-a');
    expect(records, hasLength(1));
    expect(records.single.event.name, event.name);
    expect(records.single.event.timestamp, event.timestamp);
    expect(records.single.event.attributes['app.version'], '1.2.3');
    expect(await recordsFor('tenant-b'), isEmpty);
  });

  test('rejects events from an unlisted Atsign', () async {
    final AtTelemetryNotificationOutcome outcome = await receiver.handle(
      _notification(
          from: '@mallory', value: codec.encode(<AtTelemetryEvent>[event])),
    );

    expect(outcome, AtTelemetryNotificationOutcome.unauthorized);
    expect(await recordsFor('tenant-a'), isEmpty);
  });

  test('rejects missing, oversized, and malformed payloads', () async {
    for (final String? value in <String?>[
      null,
      '',
      'A' * 4097,
      'not base64!',
      'AAAA',
    ]) {
      final AtTelemetryNotificationOutcome outcome = await receiver.handle(
        _notification(from: '@alice', value: value),
      );
      expect(
        outcome,
        AtTelemetryNotificationOutcome.invalid,
        reason: 'payload length ${value?.length}',
      );
    }
    expect(await recordsFor('tenant-a'), isEmpty);
  });

  test('processes a notification stream in order', () async {
    final StreamController<AtNotification> controller =
        StreamController<AtNotification>();
    final StreamSubscription<AtTelemetryNotificationOutcome> subscription =
        receiver.listen(controller.stream);
    addTearDown(subscription.cancel);

    for (int hour = 1; hour <= 3; hour++) {
      controller.add(
        _notification(
          from: '@alice',
          value: codec.encode(<AtTelemetryEvent>[
            AtTelemetryEvent(
              name: 'atsign.app.tick',
              timestamp: DateTime.utc(2026, 2, 25, hour),
            ),
          ]),
        ),
      );
    }
    controller.add(_notification(from: '@mallory', value: 'AAAA'));
    await controller.close();
    await subscription.asFuture<void>();

    expect(outcomes, <AtTelemetryNotificationOutcome>[
      AtTelemetryNotificationOutcome.accepted,
      AtTelemetryNotificationOutcome.accepted,
      AtTelemetryNotificationOutcome.accepted,
      AtTelemetryNotificationOutcome.unauthorized,
    ]);
    expect(await recordsFor('tenant-a'), hasLength(3));
  });

  test('rejects duplicate Atsigns after normalization', () {
    expect(
      () => AtTelemetryAtsignAuthenticator(<AtTelemetryAtsignCredential>[
        AtTelemetryAtsignCredential(atsign: '@alice', tenantId: 'tenant-a'),
        AtTelemetryAtsignCredential(atsign: 'ALICE', tenantId: 'tenant-b'),
      ]),
      throwsArgumentError,
    );
  });
}

AtNotification _notification({required String from, required String? value}) {
  return AtNotification(
    'notification-id',
    '@telemetry:${AtTelemetryNotificationCodec.idAndNamespace}$from',
    from,
    '@telemetry',
    DateTime.utc(2026, 2, 25).millisecondsSinceEpoch,
    'MessageType.key',
    true,
    value: value,
    operation: 'update',
  );
}
