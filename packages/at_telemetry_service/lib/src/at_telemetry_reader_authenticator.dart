import 'at_telemetry_api_key.dart';

final class AtTelemetryReaderIdentity {
  final String readerId;
  final String tenantId;

  AtTelemetryReaderIdentity({
    required this.readerId,
    required this.tenantId,
  }) {
    if (readerId.trim().isEmpty) {
      throw ArgumentError.value(readerId, 'readerId', 'must not be empty');
    }
    if (tenantId.trim().isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', 'must not be empty');
    }
  }
}

abstract interface class AtTelemetryReaderAuthenticator {
  Future<AtTelemetryReaderIdentity?> authenticate(String credential);
}

final class AtTelemetryReaderApiKeyCredential {
  final AtTelemetryReaderIdentity identity;
  final List<int> _digest;

  AtTelemetryReaderApiKeyCredential({
    required String apiKey,
    required String readerId,
    required String tenantId,
  })  : identity = AtTelemetryReaderIdentity(
          readerId: readerId,
          tenantId: tenantId,
        ),
        _digest = digestValidatedApiKey(apiKey);
}

final class AtTelemetryReaderApiKeyAuthenticator
    implements AtTelemetryReaderAuthenticator {
  final List<AtTelemetryReaderApiKeyCredential> _credentials;

  AtTelemetryReaderApiKeyAuthenticator(
    Iterable<AtTelemetryReaderApiKeyCredential> credentials,
  ) : _credentials = List<AtTelemetryReaderApiKeyCredential>.unmodifiable(
          credentials,
        ) {
    if (_credentials.isEmpty) {
      throw ArgumentError.value(
        credentials,
        'credentials',
        'must contain at least one API key',
      );
    }
    requireUniqueDigests(<List<int>>[
      for (final AtTelemetryReaderApiKeyCredential credential in _credentials)
        credential._digest,
    ]);
  }

  @override
  Future<AtTelemetryReaderIdentity?> authenticate(String credential) async {
    final List<int> candidateDigest = digestApiKey(credential);
    for (final AtTelemetryReaderApiKeyCredential configured in _credentials) {
      if (constantTimeEquals(configured._digest, candidateDigest)) {
        return configured.identity;
      }
    }
    return null;
  }
}
