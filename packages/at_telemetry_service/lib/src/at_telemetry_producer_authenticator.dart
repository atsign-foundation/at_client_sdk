import 'package:at_commons/at_commons.dart';

import 'at_telemetry_api_key.dart';
import 'at_telemetry_producer_identity.dart';

abstract interface class AtTelemetryProducerAuthenticator {
  Future<AtTelemetryProducerIdentity?> authenticate(String credential);
}

final class AtTelemetryApiKeyCredential {
  final AtTelemetryProducerIdentity identity;
  final List<int> _digest;

  AtTelemetryApiKeyCredential({
    required String apiKey,
    required String producerId,
    required String tenantId,
  })  : identity = AtTelemetryProducerIdentity(
          producerId: producerId,
          tenantId: tenantId,
          authenticationMethod: AtTelemetryAuthenticationMethod.apiKey,
        ),
        _digest = digestValidatedApiKey(apiKey);
}

final class AtTelemetryApiKeyAuthenticator
    implements AtTelemetryProducerAuthenticator {
  final List<AtTelemetryApiKeyCredential> _credentials;

  AtTelemetryApiKeyAuthenticator(
    Iterable<AtTelemetryApiKeyCredential> credentials,
  ) : _credentials = List<AtTelemetryApiKeyCredential>.unmodifiable(
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
      for (final AtTelemetryApiKeyCredential credential in _credentials)
        credential._digest,
    ]);
  }

  @override
  Future<AtTelemetryProducerIdentity?> authenticate(String credential) async {
    final List<int> candidateDigest = digestApiKey(credential);
    for (final AtTelemetryApiKeyCredential configured in _credentials) {
      if (constantTimeEquals(configured._digest, candidateDigest)) {
        return configured.identity;
      }
    }
    return null;
  }
}

final class AtTelemetryAtsignCredential {
  final Atsign atsign;
  final AtTelemetryProducerIdentity identity;

  factory AtTelemetryAtsignCredential({
    required String atsign,
    required String tenantId,
  }) {
    final Atsign normalizedAtsign = Atsign(atsign);
    return AtTelemetryAtsignCredential._(
      atsign: normalizedAtsign,
      identity: AtTelemetryProducerIdentity(
        producerId: normalizedAtsign,
        tenantId: tenantId,
        authenticationMethod:
            AtTelemetryAuthenticationMethod.atsignNotification,
      ),
    );
  }

  const AtTelemetryAtsignCredential._({
    required this.atsign,
    required this.identity,
  });
}

final class AtTelemetryAtsignAuthenticator
    implements AtTelemetryProducerAuthenticator {
  final Map<Atsign, AtTelemetryProducerIdentity> _identities;

  AtTelemetryAtsignAuthenticator(
    Iterable<AtTelemetryAtsignCredential> credentials,
  ) : _identities = <Atsign, AtTelemetryProducerIdentity>{} {
    for (final AtTelemetryAtsignCredential credential in credentials) {
      if (_identities.containsKey(credential.atsign)) {
        throw ArgumentError('Atsigns must be unique: ${credential.atsign}');
      }
      _identities[credential.atsign] = credential.identity;
    }
    if (_identities.isEmpty) {
      throw ArgumentError.value(
        credentials,
        'credentials',
        'must contain at least one Atsign',
      );
    }
  }

  @override
  Future<AtTelemetryProducerIdentity?> authenticate(String credential) async {
    final Atsign atsign;
    try {
      atsign = Atsign(credential);
    } on InvalidAtSignException {
      return null;
    }
    return _identities[atsign];
  }
}
