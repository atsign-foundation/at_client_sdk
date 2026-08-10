import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;

/// Each client's PKAM signing algorithm as resolved from its enrollment's
/// key material — recorded at init by `AtClientImpl`, read by anything that
/// signs on the client's behalf.
///
/// The record lives here, below the client implementation, so the signing
/// mixins can consult a client's resolved algorithm without depending on
/// `AtClientImpl`. Keyed by the client instance (an [Expando], the same
/// client-associated-state pattern the crypto config uses), so the record
/// lives and dies with the client and two concurrent clients of one atSign
/// each keep their own resolution.
final Expando<SigningAlgoType> _resolvedSigningAlgo =
    Expando<SigningAlgoType>('resolvedSigningAlgo');

/// Records [algo] as [atClient]'s key-material-resolved signing algorithm.
///
/// A null [algo] clears the record: the enrollment has no typed key material
/// (a legacy flat-fields keyfile), so [signingAlgoOf] falls back to the
/// preference.
void recordResolvedSigningAlgo(AtClient atClient, SigningAlgoType? algo) {
  _resolvedSigningAlgo[atClient] = algo;
}

/// [atClient]'s recorded resolution, or null when no key-material resolution
/// has been recorded. Callers that must distinguish "resolved" from
/// "falling back" use this; everything else uses [signingAlgoOf].
SigningAlgoType? resolvedSigningAlgoFor(AtClient atClient) =>
    _resolvedSigningAlgo[atClient];

/// The PKAM signing algorithm [atClient]'s connections authenticate with:
/// the key-material resolution when one was recorded, else the preference —
/// the documented legacy fallback for untyped key material.
SigningAlgoType signingAlgoOf(AtClient atClient) =>
    _resolvedSigningAlgo[atClient] ??
    // The documented legacy fallback for untyped key material.
    // ignore: deprecated_member_use_from_same_package
    atClient.getPreferences()?.signingAlgoType ??
    SigningAlgoType.rsa2048;
