import 'package:at_commons/at_commons.dart' show AtKey;

/// The `__ssenv` envelope address, in one place:
///
///     <msgId>.<inReplyTo>.<recipientKpid>.__ssenv.<appNamespace>@<atSign>
///
/// Every builder, matcher and parser of that shape lives here, so the emitted
/// name, the sweep filters and the namespace parse cannot drift apart. The
/// emitted forms are pinned in `test/wire_literal_pins_test.dart`, and an
/// intended change edits those pins in the same commit.
///
/// [inReplyTo] correlates an answer with the request that asked for it, and
/// exists because without it nothing in the address ordered one against the
/// other. A holder deciding whether some other holder had already answered a
/// requester could only ask "is any envelope addressed to that requester in
/// this namespace" — which is true of a *request* written to that same
/// address by a third enrollment's fan-out, and true of an unconsumed
/// leftover from an unrelated exchange. Holders that could serve the request
/// therefore stood down for records that were not answers, and the requester
/// got nothing back and no error.
///
/// ⚠️ The segment sits BEFORE the kpid on purpose. [fragmentFor], [regexFor],
/// [regexForAny], the sweep filters and [appNamespaceOf] all anchor on the
/// kpid-then-marker pair, so a segment inserted ahead of it is invisible to
/// every one of them and they keep matching unchanged. Putting it after the
/// kpid would have broken all of them at once.
class EnvelopeAddressing {
  /// Marker segment in envelope key names.
  static const String marker = '__ssenv';

  /// The [inReplyTo] value for an envelope that answers nothing — a request
  /// itself, or an unsolicited push.
  ///
  /// A single character rather than an absent segment, so the address always
  /// has the same number of parts and every parser can count on it.
  static const String unsolicited = '0';

  /// The at-key for one envelope addressed to [recipientKpid] through
  /// [appNamespace], answering the request identified by [inReplyTo].
  ///
  /// The namespace suffix is what scopes delivery — the atServer only lets
  /// enrollments authorized for it get/scan/sync the envelope — and [msgId]
  /// is the sender's random uuid, the only part of the address the recipient
  /// cannot know in advance.
  ///
  /// [inReplyTo] is [unsolicited] for a request or a push. It is required
  /// rather than defaulted here so that every call site has to state which it
  /// is; the one place it is defaulted is `PairwiseSecretSharing.sendEnvelope`,
  /// whose callers genuinely have no basis to choose.
  ///
  /// ⚠️ The copy in the address is a routing hint only. It is written by the
  /// sender into an unauthenticated key name, so a suppression decision must
  /// read the id from the SEALED payload instead.
  static AtKey envelopeKey({
    required String msgId,
    required String inReplyTo,
    required String recipientKpid,
    required String appNamespace,
    required String? sharedBy,
    required Duration ttl,
  }) =>
      AtKey()
        ..key = '$msgId.$inReplyTo.$recipientKpid.$marker'
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

  /// Envelopes addressed to [kpid] through [appNamespace] that answer the
  /// request [requestId].
  ///
  /// Replaces a filter that matched every envelope at an address regardless of
  /// what it was: a holder used it to decide whether a requester had already
  /// been answered, and a request or a stale push matched it just as well as
  /// an answer.
  static String answerSweepRegexFor(
          String requestId, String kpid, String appNamespace) =>
      '.*\\.$requestId\\.$kpid\\.$marker\\.$appNamespace.*';

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
