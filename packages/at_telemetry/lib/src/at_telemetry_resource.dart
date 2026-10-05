import 'at_telemetry_any_value.dart';

// Describes who produced the telemetry, for example the service name and the
// Atsign it runs as. It is the same for every record a program sends.
final class AtTelemetryResource {
  static const String serviceNameAttribute = 'service.name';

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
}
