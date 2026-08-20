import 'package:at_commons/at_commons.dart' show AtKey;

/// The `__ssenv` envelope address, in one place:
///
///     <msgId>.<recipientKpid>.__ssenv.<appNamespace>@<atSign>
///
/// Every builder, matcher and parser of that shape lives here, so the emitted
/// name, the sweep filters and the namespace parse cannot drift apart. The
/// marker is frozen wire vocabulary — unconsumed envelopes carrying today's
/// names sit on live atServers until their ttl expires — and the emitted forms
/// are pinned in `test/wire_literal_pins_test.dart`.
class EnvelopeAddressing {
  /// Marker segment in envelope key names.
  static const String marker = '__ssenv';

  /// The at-key for one envelope addressed to [recipientKpid] through
  /// [appNamespace].
  ///
  /// The namespace suffix is what scopes delivery — the atServer only lets
  /// enrollments authorized for it get/scan/sync the envelope — and [msgId]
  /// is the sender's random uuid, the only part of the address the recipient
  /// cannot know in advance.
  static AtKey envelopeKey({
    required String msgId,
    required String recipientKpid,
    required String appNamespace,
    required String? sharedBy,
    required Duration ttl,
  }) =>
      AtKey()
        ..key = '$msgId.$recipientKpid.$marker'
        ..namespace = appNamespace
        ..sharedBy = sharedBy
        ..metadata.ttl = ttl.inMilliseconds;

  /// The literal `.<kpid>.__ssenv.` fragment every envelope addressed to
  /// [kpid] contains, for plain substring checks.
  static String fragmentFor(String kpid) => '.$kpid.$marker.';

  /// [fragmentFor] as a regex, for `subscribe` and scan filters that search
  /// rather than full-match.
  static String regexFor(String kpid) => '\\.$kpid\\.$marker\\.';

  /// [regexFor] over any of [kpids] — one filter for a client that answers at
  /// more than one address.
  ///
  /// A client that has rotated its enc key still holds the superseded one so
  /// that envelopes already in flight to it can be opened, and an envelope it
  /// never scans for is one it never opens however willing it is to. One
  /// alternation rather than a scan per address, because a sweep is a round
  /// trip and the addresses are known together.
  ///
  /// [kpids] must not be empty: a filter over no addresses would either match
  /// nothing (a client that silently receives nothing) or, spelled carelessly,
  /// match every envelope on the atServer.
  static String regexForAny(Iterable<String> kpids) {
    if (kpids.isEmpty) {
      throw ArgumentError.value(
          kpids,
          'kpids',
          'an envelope filter over no addresses matches either nothing or '
              'everything, and neither is a thing to ask the atServer for');
    }
    return '\\.(${kpids.join('|')})\\.$marker\\.';
  }

  /// [regexFor] anchored for full-match filters (`getAtKeys`).
  static String sweepRegexFor(String kpid) => '.*${regexFor(kpid)}.*';

  /// [regexForAny] anchored for full-match filters (`getAtKeys`).
  static String sweepRegexForAny(Iterable<String> kpids) =>
      '.*${regexForAny(kpids)}.*';

  /// [sweepRegexFor] narrowed to envelopes addressed through one namespace.
  static String namespaceSweepRegexFor(String kpid, String appNamespace) =>
      '.*\\.$kpid\\.$marker\\.$appNamespace.*';

  /// The full application namespace of an envelope key: everything between
  /// the `.__ssenv.` marker and the atSign. `AtKey.namespace` only carries
  /// the last dot segment, which would truncate dotted app namespaces
  /// (`examples.demos` would arrive as `demos`).
  static String appNamespaceOf(AtKey envelopeKey) {
    final String keyString = envelopeKey.toString();
    final int markerIndex = keyString.indexOf('.$marker.');
    final int atIndex = keyString.lastIndexOf('@');
    if (markerIndex < 0 || atIndex <= markerIndex) {
      return envelopeKey.namespace ?? '';
    }
    return keyString.substring(markerIndex + '.$marker.'.length, atIndex);
  }
}
