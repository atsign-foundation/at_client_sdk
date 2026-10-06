import '../at_telemetry_any_value.dart';
import '../at_telemetry_attributes.dart';

// Describes who produced the telemetry, for example the service name and the
// Atsign it runs as. It is the same for every record a program sends.
final class AtTelemetryResource {
  static const String serviceNameAttribute = AtTelemetryAttributes.serviceName;

  final Map<String, Object?> attributes;

  AtTelemetryResource({
    required String serviceName,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) : attributes = Map<String, Object?>.unmodifiable(<String, Object?>{
          ...attributes,
          serviceNameAttribute: serviceName,
        }) {
    if (serviceName.trim().isEmpty) {
      throw ArgumentError.value(
          serviceName, 'serviceName', 'must not be empty');
    }
    for (final MapEntry<String, Object?> entry in this.attributes.entries) {
      AtTelemetryAnyValue.check(entry.value, 'attributes.${entry.key}');
    }
  }

  String get serviceName => attributes[serviceNameAttribute]! as String;

  // Resource attributes for an app. Named fields win over attributes.
  static Map<String, Object?> app({
    String? serviceVersion,
    String? serviceInstanceId,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    return <String, Object?>{
      ...attributes,
      if (serviceVersion != null)
        AtTelemetryAttributes.serviceVersion: serviceVersion,
      if (serviceInstanceId != null)
        AtTelemetryAttributes.serviceInstanceId: serviceInstanceId,
    };
  }

  // Resource attributes for an atServer. The collector rejects an atServer's
  // batch unless atServerId matches the atServer that sent it.
  static Map<String, Object?> atServer({
    required String atServerId,
    String? serviceVersion,
    String? serviceInstanceId,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    if (atServerId.trim().isEmpty) {
      throw ArgumentError.value(atServerId, 'atServerId', 'must not be empty');
    }
    return <String, Object?>{
      ...app(
        serviceVersion: serviceVersion,
        serviceInstanceId: serviceInstanceId,
        attributes: attributes,
      ),
      AtTelemetryAttributes.atServerId: atServerId,
    };
  }
}
