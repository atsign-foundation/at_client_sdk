import 'package:at_client/src/client/at_client_spec.dart' show AtClient;

/// A per-client registry for an SDK-chosen era default.
///
/// A preference object is routinely shared across atSigns, so resolving the
/// SDK's default *into* it would leak one client's resolution to another; the
/// association is kept in an [Expando] beside the client instead, and an entry
/// lives and dies with the client that holds it.
class EraDefaults<T extends Object> {
  final Expando<T> _byClient = Expando<T>('eraDefault');

  /// The era default [atClient] holds, or null when it was never given one.
  T? of(AtClient atClient) => _byClient[atClient];

  /// Gives [atClient] the era default [value], unless it already holds one.
  /// Idempotent — a re-used cached client keeps the value it was built
  /// with, so per-client state hanging off the value survives re-creation.
  void adoptIfAbsent(AtClient atClient, T value) {
    _byClient[atClient] ??= value;
  }

  /// Forgets [atClient]'s era default, for a test that rebuilds a client's
  /// crypto world.
  void clear(AtClient atClient) {
    _byClient[atClient] = null;
  }
}
