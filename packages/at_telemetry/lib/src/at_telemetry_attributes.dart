// Attribute names shared by apps, atServers and the collector. Standard
// OpenTelemetry names where one exists, atsign.* names for the rest.
final class AtTelemetryAttributes {
  static const String serviceName = 'service.name';
  static const String serviceVersion = 'service.version';
  static const String serviceInstanceId = 'service.instance.id';

  static const String atServerId = 'atsign.atserver.id';
  static const String atServerUptimeSeconds = 'atsign.atserver.uptime_seconds';

  static const String enrollmentId = 'atsign.enrollment.id';
  static const String clientId = 'atsign.client.id';
  static const String notificationIds = 'atsign.notification.ids';
  static const String keys = 'atsign.keys';

  static const String telemetryClasses = 'atsign.telemetry.classes';
  static const String outboxBatches = 'atsign.telemetry.outbox.batches';
  static const String outboxBytes = 'atsign.telemetry.outbox.bytes';
  static const String outboxDropped = 'atsign.telemetry.outbox.dropped';

  const AtTelemetryAttributes._();
}
