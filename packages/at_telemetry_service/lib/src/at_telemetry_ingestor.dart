import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry_persistence/at_telemetry_persistence.dart';

import 'at_telemetry_producer_identity.dart';

final class AtTelemetryIngestor {
  final AtTelemetryPersistence _persistence;

  const AtTelemetryIngestor({
    required AtTelemetryPersistence persistence,
  }) : _persistence = persistence;

  Future<void> ingest({
    required AtTelemetryProducerIdentity producer,
    required Iterable<AtTelemetryEvent> events,
  }) async {
    await _persistence.storeAll(
      tenantId: producer.tenantId,
      events: events,
    );
  }
}
