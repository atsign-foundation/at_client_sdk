enum AtTelemetryAuthenticationMethod {
  apiKey,
  atsignNotification,
}

final class AtTelemetryProducerIdentity {
  final String producerId;
  final String tenantId;
  final AtTelemetryAuthenticationMethod authenticationMethod;

  AtTelemetryProducerIdentity({
    required this.producerId,
    required this.tenantId,
    required this.authenticationMethod,
  }) {
    if (producerId.trim().isEmpty) {
      throw ArgumentError.value(
        producerId,
        'producerId',
        'must not be empty',
      );
    }
    if (tenantId.trim().isEmpty) {
      throw ArgumentError.value(
        tenantId,
        'tenantId',
        'must not be empty',
      );
    }
  }
}
