import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('SchemeNegotiation');

/// Chooses the scheme a write goes out under, per destination, from what that
/// destination's fleet has advertised it can read.
///
/// The migration invariant, in one sentence: **write only what every required
/// reader supports.** A record is written in the best scheme present in every
/// required reader's capability marker, and falls back to legacy when there is
/// no shared post-quantum one. That is what makes adoption a rollout rather
/// than a flag day — an upgraded client can be deployed everywhere, reading
/// everything and writing nothing anyone else cannot open, and the write side
/// moves later on evidence rather than on a release date.
///
/// **What counts as a required reader is the record's own, not the writer's
/// wider intent.** A self record is read by the writer's own fleet; a record
/// shared with `@bob` is read by bob's. Alice's other enrollments do not read
/// what she wrote *for bob* out of bob's copy — that is a separate record with
/// its own negotiation, which is why a partially-upgraded `@alice` can share
/// post-quantum with a ready `@bob` while her own self copies stay legacy.
@experimental
class SchemeNegotiation {
  final AtClient _atClient;
  final PublishedCapabilities? _injectedCapabilities;

  SchemeNegotiation(this._atClient, {PublishedCapabilities? capabilities})
      : _injectedCapabilities = capabilities;

  /// Where the marker answers come from.
  ///
  /// Resolved per call rather than captured at construction. This object is
  /// cached per client and outlives any single write, so capturing would pin it
  /// to whichever [PublishedCapabilities] happened to exist when the client's
  /// *first* write ran — and a client does several during start-up, before an
  /// app or a test has had any chance to supply its own. The symptom is
  /// exactly what it sounds like: `CryptoRollout` reads a fresh marker while
  /// the write path keeps answering from an instance nobody can reach.
  PublishedCapabilities get capabilities =>
      _injectedCapabilities ?? PublishedCapabilities.forClient(_atClient);

  /// The negotiator [atClient] resolves its writes through.
  ///
  /// One per client, because this holds the "already said that" set below: a
  /// fresh instance per write would turn a once-per-destination warning into
  /// one per write, which is how a real warning becomes noise nobody reads.
  static SchemeNegotiation forClient(AtClient atClient) =>
      _perClient[atClient] ??= SchemeNegotiation(atClient);

  static final Expando<SchemeNegotiation> _perClient =
      Expando('SchemeNegotiation.forClient');

  /// `atSign|namespace` already reported as un-negotiated, so an app that has
  /// deliberately overridden the default is told once per destination rather
  /// than once per write.
  final Set<String> _reportedUnevidenced = {};

  /// The provider id [atKey] should be written under, given [configured] — the
  /// id this client's [CryptoConfig] would use on its own.
  ///
  /// Returns [configured] unchanged when there is nothing to negotiate on: a
  /// key with no namespace (the SDK's own internal records), or a destination
  /// that has advertised nothing.
  ///
  /// **No evidence is not the same as a legacy-only fleet.** A destination that
  /// has published no marker is either running builds that predate markers
  /// entirely or was unreachable, and neither says what it can read. So the
  /// client writes what it was configured to write — which for every client
  /// that has not deliberately chosen otherwise is legacy, since the era
  /// default reads the post-quantum path and writes legacy. An app that *has*
  /// chosen otherwise has written code to say so, and is told, once per
  /// destination, that its choice is going out unnegotiated.
  Future<String> select(AtKey atKey, String configured) async {
    final namespace = atKey.namespace;
    final reader = atKey.sharedWith ?? atKey.sharedBy;
    if (namespace == null || namespace.isEmpty) return configured;
    if (reader == null || reader.isEmpty) return configured;

    final Set<String>? supported;
    try {
      supported = await capabilities.advertisedBy(reader, namespace);
    } catch (e) {
      // Negotiation is an optimisation on top of a working write path, and a
      // marker read that blew up must not take the write with it. The
      // configured scheme is what this client would have written before
      // negotiation existed.
      _logger.warning('Could not read $reader\'s capability marker for '
          '$namespace, so $configured is used unnegotiated: $e');
      return configured;
    }

    if (supported == null) {
      if (configured != legacyCryptoProviderId &&
          _reportedUnevidenced.add('$reader|$namespace')) {
        _logger.warning(
            '$reader advertises no capability marker for $namespace, so there '
            'is no evidence it can read $configured — writing it anyway '
            'because this client is configured to. Records written now are '
            'unreadable to any enrollment of $reader that has not upgraded.');
      }
      return configured;
    }

    final config = CryptoConfig.forClient(_atClient);
    for (final candidate in _candidates(config, configured, atKey)) {
      if (supported.containsAll(_requirementsOf(config, candidate))) {
        if (candidate != configured) {
          _logger.finer('Negotiated $candidate for $reader:$namespace, '
              'over the configured $configured');
        }
        return candidate;
      }
    }

    _logger.finer('$reader:$namespace supports none of this client\'s '
        'post-quantum schemes, so the write falls back to '
        '$legacyCryptoProviderId');
    return legacyCryptoProviderId;
  }

  /// The schemes this client could write [atKey] under, best first.
  ///
  /// [CryptoConfig.preferredProviderId] leads: it is the scheme the config
  /// would rather write once the fleet can read it, and the era default's whole
  /// shape is "read the post-quantum path, write legacy until the markers say
  /// otherwise". Without it here the flip could never happen — the configured
  /// default would win every time and readiness would advertise into nothing.
  Iterable<String> _candidates(
      CryptoConfig config, String configured, AtKey atKey) sync* {
    final preferred = config.preferredProviderId;
    if (preferred != null &&
        preferred != configured &&
        _canHandle(config, preferred, atKey)) {
      yield preferred;
    }
    yield configured;
    if (configured != legacyCryptoProviderId) yield legacyCryptoProviderId;
  }

  static bool _canHandle(CryptoConfig config, String id, AtKey atKey) {
    final provider = config.lookup(id);
    if (provider == null) return false;
    return provider is! HandlesSelectively ||
        (provider as HandlesSelectively).canHandle(atKey);
  }

  /// Every provider id a reader must have registered to open a value written
  /// under [id].
  ///
  /// Usually just [id] itself. The nskey data path is the exception that makes
  /// this an interface rather than an assumption: a value stamped
  /// `at/symmetric/AES/GCM` cites a content key that arrives in a separate
  /// `at/nskey/...` conveyance, so a reader with only the first can see the
  /// value and never open it.
  static Set<String> _requirementsOf(CryptoConfig config, String id) {
    final provider = config.lookup(id);
    return provider is RequiresReaderSupport
        ? (provider as RequiresReaderSupport).readerRequirements
        : {id};
  }
}
