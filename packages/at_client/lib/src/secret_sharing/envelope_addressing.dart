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

  /// [regexFor] anchored for full-match filters (`getAtKeys`).
  static String sweepRegexFor(String kpid) => '.*${regexFor(kpid)}.*';

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
