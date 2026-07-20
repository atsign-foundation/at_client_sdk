import 'dart:typed_data';

/// Where the `at/nskey` provider gets namespace key material.
///
/// Per `(atSign, namespace)` there is exactly **one** X-Wing nskey keypair. It
/// is the recipient key for both directions: the owner encapsulates her own CKs
/// to it for self data, and external senders encapsulate CKs to it when sharing
/// with her. The private half decapsulates CKs — it never decrypts application
/// data.
///
/// In production the private half is minted fresh and conveyed per-APKAM over
/// the secret-sharing substrate, and the public half is published lazily (the
/// owner-only self at-key `nskey.<ns>@<owner>`, promoted to the world-readable
/// `public:nskey.<ns>@<owner>` on the namespace's first cross-atSign share).
/// This interface is the seam that work lands behind; see
/// [InMemoryNskeyKeyRing] for the fixture that stands in until it does.
abstract class NskeyKeyRing {
  /// The public half of `(owner, namespace)`'s nskey — the encapsulation
  /// target. For self data this is the owner's own; for a share it is the
  /// recipient's, fetched via `plookup` once published.
  ///
  /// Null when the namespace has no nskey, which is the cold-start case: the
  /// caller falls back to sealing the CK to `public:pqpublickey@<recipient>`.
  Future<Uint8List?> publicHalf(String owner, String namespace);

  /// The private half held by this client for `(owner, namespace)`.
  ///
  /// Null when this client is not authorised for the namespace, or has not yet
  /// received the private over the substrate. Values in that namespace are then
  /// left undecryptable rather than silently skipped.
  Future<Uint8List?> privateHalf(String owner, String namespace);
}

/// An in-memory [NskeyKeyRing] seeded directly with keypairs.
///
/// This exists so the data path can be exercised end-to-end before the
/// substrate delivers privates for real — it inverts the dependency order for
/// demonstration only. The production path is unchanged: when nskey minting and
/// per-APKAM conveyance land, they supply a real [NskeyKeyRing] and this becomes
/// test-only scaffolding.
class InMemoryNskeyKeyRing implements NskeyKeyRing {
  final Map<String, Uint8List> _public = {};
  final Map<String, Uint8List> _private = {};

  static String _k(String owner, String namespace) => '$owner|$namespace';

  /// Seed both halves for `(owner, namespace)` — the state a client is in once
  /// it holds the namespace key.
  void seedKeypair(
    String owner,
    String namespace, {
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    _public[_k(owner, namespace)] = publicKey;
    _private[_k(owner, namespace)] = privateKey;
  }

  /// Seed only the public half — a sender who can encapsulate to a recipient
  /// but cannot decapsulate, which is every cross-atSign sender.
  void seedPublicOnly(
    String owner,
    String namespace, {
    required Uint8List publicKey,
  }) {
    _public[_k(owner, namespace)] = publicKey;
  }

  @override
  Future<Uint8List?> publicHalf(String owner, String namespace) async =>
      _public[_k(owner, namespace)];

  @override
  Future<Uint8List?> privateHalf(String owner, String namespace) async =>
      _private[_k(owner, namespace)];
}
