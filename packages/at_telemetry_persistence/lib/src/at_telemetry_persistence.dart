import 'package:at_telemetry/at_telemetry.dart';

import 'at_telemetry_query.dart';
import 'at_telemetry_record.dart';

abstract interface class AtTelemetryPersistence {
  Future<AtTelemetryRecord> store({
    required String tenantId,
    required AtTelemetryEvent event,
    DateTime? receivedAt,
  });

  Future<List<AtTelemetryRecord>> storeAll({
    required String tenantId,
    required Iterable<AtTelemetryEvent> events,
    DateTime? receivedAt,
  });

  Future<List<AtTelemetryRecord>> query(AtTelemetryQuery query);

  Future<void> close();
}
