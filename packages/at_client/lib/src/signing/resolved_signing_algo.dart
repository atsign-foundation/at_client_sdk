import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;

/// Each client's PKAM signing algorithm as resolved from its enrollment's key
/// material, keyed by client instance so the record dies with the client and
/// two concurrent clients of one atSign each keep their own resolution.
final Expando<SigningAlgoType> _resolvedSigningAlgo =
    Expando<SigningAlgoType>('resolvedSigningAlgo');

/// Records [algo] as [atClient]'s key-material-resolved signing algorithm.
///
/// A null [algo] clears the record — the enrollment has no typed key material
/// — so [signingAlgoOf] falls back to the preference.
void recordResolvedSigningAlgo(AtClient atClient, SigningAlgoType? algo) {
  _resolvedSigningAlgo[atClient] = algo;
}

/// [atClient]'s recorded resolution, or null when none has been recorded.
///
/// Use [signingAlgoOf] unless the caller must tell a resolution apart from the
/// fallback.
SigningAlgoType? resolvedSigningAlgoFor(AtClient atClient) =>
    _resolvedSigningAlgo[atClient];

/// The PKAM signing algorithm [atClient]'s connections authenticate with:
/// the key-material resolution when one was recorded, else the preference —
/// the documented legacy fallback for untyped key material.
SigningAlgoType signingAlgoOf(AtClient atClient) =>
    _resolvedSigningAlgo[atClient] ??
    // ignore: deprecated_member_use_from_same_package
    atClient.getPreferences()?.signingAlgoType ??
    SigningAlgoType.rsa2048;
