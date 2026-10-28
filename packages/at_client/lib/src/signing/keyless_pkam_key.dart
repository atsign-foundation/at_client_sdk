import 'package:at_client/src/client/at_client_spec.dart' show AtClient;

/// The PKAM private key each client built without a keyfile found in its local
/// store at start, keyed by client instance so the record dies with the
/// client.
final Expando<String> _localPkamPrivateKey =
    Expando<String>('localPkamPrivateKey');

/// Records [privateKey] as the PKAM private key [atClient]'s local store held
/// at start; null clears the record.
void recordLocalPkamPrivateKey(AtClient atClient, String? privateKey) {
  _localPkamPrivateKey[atClient] = privateKey;
}

/// The PKAM private key [atClient] authenticates with when it has no keyfile:
/// its preference's, else the one its local store held at start; null when
/// neither holds one.
String? pkamPrivateKeyWithoutKeyfile(AtClient atClient) =>
    atClient.getPreferences()?.privateKey ?? _localPkamPrivateKey[atClient];
