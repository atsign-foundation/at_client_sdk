// Attribute names shared by apps, atServers and the collector. Standard
// OpenTelemetry names where one exists, atsign.* names for the rest.
final class AtTelemetryAttributes {
  // Resource attributes, describing the program that sent the telemetry: its
  // name (required, such as at_secondary_server or an app's name), its
  // version, and an id for this run of it. An atServer uses its boot id as
  // the instance id, which changes on every start.
  static const String serviceName = 'service.name';
  static const String serviceVersion = 'service.version';
  static const String serviceInstanceId = 'service.instance.id';

  // Resource attribute. The atSign of the atServer that sent the telemetry.
  // The collector rejects an atServer's batch unless this matches the
  // atServer that signed it.
  static const String atServerId = 'atsign.atserver.id';

  // Correlation ids on app records, which atServer events carry too, so the
  // two can be lined up. The notification exporter stamps the enrollment id
  // and the client id (as declared in the from verb) on every record.
  // AtTelemetry.event sets the notification ids and atKeys an event produced.
  static const String enrollmentId = 'atsign.enrollment.id';
  static const String clientId = 'atsign.client.id';
  static const String notificationIds = 'atsign.notification.ids';
  static const String keys = 'atsign.keys';

  // Heartbeat event attribute: how long the atServer has been running, in
  // seconds.
  static const String atServerUptimeSeconds = 'atsign.atserver.uptime_seconds';

  const AtTelemetryAttributes._();
}
