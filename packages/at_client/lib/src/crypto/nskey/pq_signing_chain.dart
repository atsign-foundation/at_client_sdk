import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show EnvelopeSigning;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// The approval chain: every enrollment's APKAM public key is signed by the
/// enrollment that approved it, up to the atSign's signing root.
///
/// The link is a plain APKAM-signed envelope, which is what makes the chain
/// self-describing: the envelope already names the enrollment that signed it,
/// and verifying it already resolves that enrollment's published `_apsk`. So a
/// verifier walks upward without any approval graph having been published, and
/// a forged parent claim simply fails the signature check against the parent it
/// names.
///
/// **The parent signs and the child publishes** ([decisions.md 22.2b][] ruling
/// 7). `_apsk` writes are restricted to the owning enrollment's own
/// authenticated connection, so the signer is not a permitted writer: the
/// approver conveys the link over the substrate, and the child stamps it onto
/// its own record on first run. Until the child runs, verifiers see a bare key,
/// which the transition rule already tolerates.
///
/// [decisions.md 22.2b]: ../../../../../docs/projects/pq/decisions.md
@experimental
class PqSigningChain {
  /// Reserved [Secret] name for a conveyed chain link.
  ///
  /// Per-enrollment, so it is never forwarded on: a link vouches for one
  /// enrollment's key and means nothing attached to another's.
  static const String linkSecretName =
      '${PairwiseSecretSharing.perEnrollmentSecretPrefix}apskChainLink';

  /// The `appMetadata.additional` field the child stamps the link into.
  static const String linkField = 'apskChainLink';

  static final AtSignLogger _logger = AtSignLogger('PqSigningChain');

  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>` — where an enrollment's
  /// APKAM public key lives, and the one record its own connection may write.
  static String apskUri(String atSign, String enrollmentId) => 'public:'
      '_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
      '$atSign';

  /// The payload a parent signs to vouch for [childEnrollmentId].
  ///
  /// Both fields are bound in, not just the key: a signature over the key
  /// alone would verify equally well if replayed onto a different
  /// enrollment's record, and the whole point of the link is to say *which*
  /// enrollment this approver vouched for.
  static Map<String, Object?> linkPayload({
    required String childEnrollmentId,
    required String childApkamPublicKey,
  }) =>
      {
        'v': 1,
        'childEnrollmentId': childEnrollmentId,
        'apkamPublicKey': childApkamPublicKey,
      };

  /// Signs a link vouching for [childEnrollmentId], for the approver to convey.
  ///
  /// Reads the child's APKAM public key from the record the **atServer**
  /// published at approval rather than from the enrollment request, so what is
  /// signed is exactly what a verifier will later resolve. Signing a key taken
  /// from anywhere else would leave the two free to disagree.
  ///
  /// Returns null when the child's `_apsk` is not readable, which is not worth
  /// failing an approval over — the chain link is additive, and an enrollment
  /// without one is simply unsigned, which verifiers already tolerate.
  static Future<Map<String, Object?>?> signLinkFor(
    AtClient atClient,
    EnvelopeSigning signer,
    String childEnrollmentId,
  ) async {
    final atSign = atClient.getCurrentAtSign()!;
    final String childKey;
    try {
      final value = await atClient.get(
        AtKey.fromString(apskUri(atSign, childEnrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      childKey = value.value as String;
    } catch (e) {
      _logger.warning('No readable _apsk for enrollment $childEnrollmentId, '
          'so no chain link was signed for it; it stays unsigned: $e');
      return null;
    }

    return await signer.wrapAndSign(linkPayload(
      childEnrollmentId: childEnrollmentId,
      childApkamPublicKey: childKey,
    ));
  }

  /// Stamps a conveyed [link] onto this enrollment's own `_apsk`.
  ///
  /// Rewrites the record with its value unchanged and the link added to
  /// `appMetadata.additional`. The value has to be re-sent because a put
  /// replaces the record; re-reading it first means the key published is the
  /// one already there rather than one this client believes it should be.
  ///
  /// The provider id is the legacy one, which is accurate rather than a
  /// placeholder: `_apsk` is a public plaintext key and no provider encrypts
  /// it. Only `additional` carries anything new.
  static Future<void> publishLink(
    AtClient atClient,
    String enrollmentId,
    Map<String, Object?> link,
  ) async {
    final atSign = atClient.getCurrentAtSign()!;
    final uri = apskUri(atSign, enrollmentId);

    final AtValue current = await atClient.get(
      AtKey.fromString(uri),
      getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
    );

    final atKey = AtKey.fromString(uri);
    atKey.metadata.appMetadata = AppMetadata(
      providerId: CryptoRuntime.legacyProviderId,
      additional: {
        ...?atKey.metadata.appMetadata?.additional,
        linkField: link,
      },
    );

    await atClient.put(
      atKey,
      current.value,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
    _logger.info('Published chain link on $uri, signed by enrollment '
        '${link['enrollmentId']}');
  }

  /// The chain link an enrollment has published, or null if it has none.
  ///
  /// An absent link is ordinary — the enrollment has not run since approval,
  /// or predates the chain — so this reports absence rather than failing.
  static Future<Map<String, Object?>?> readLink(
    AtClient atClient,
    String enrollmentId,
  ) async {
    final atSign = atClient.getCurrentAtSign()!;
    try {
      final value = await atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      final link = value.metadata?.appMetadata?.additional?[linkField];
      if (link is Map) return link.cast<String, Object?>();
      return null;
    } catch (e) {
      _logger.info('No _apsk readable for enrollment $enrollmentId: $e');
      return null;
    }
  }

  /// Publishes the chain link this enrollment was conveyed, if one is waiting
  /// and its key does not already carry it. Returns whether it published.
  ///
  /// Self-gating: an enrollment nobody vouched for has no link in its store and
  /// this writes nothing, so it costs a client that will never have one an
  /// in-memory lookup at start and no atServer traffic at all.
  ///
  /// A link that arrives *after* this runs is published at the next start
  /// rather than immediately — the same trade the namespace-key seeding makes,
  /// and acceptable for the same reason: until it lands the enrollment is
  /// simply unsigned, which verifiers tolerate during the changeover.
  ///
  /// Three things are checked before anything is written, because this record
  /// is the enrollment's published identity and a bad link on it is worse than
  /// no link:
  ///
  /// - the link names **this** enrollment, so one conveyed for a sibling is
  ///   never stamped here;
  /// - it verifies against the parent it names, so a link that could never be
  ///   verified downstream is not published as though it could;
  /// - the key it vouches for is the key actually published, so a link that
  ///   silently covers something else is refused.
  static Future<bool> publishPendingLink(AtClient atClient) async {
    final sharing = AtClientSecretSharing.forClient(atClient);
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentId = sharing.enrollmentId;

    final secret = sharing.secretStore
        .listSecrets()
        .where((s) => s.name == linkSecretName)
        .firstOrNull;
    if (secret == null) return false;

    final Map<String, Object?> link;
    final Map payload;
    try {
      link = decodeConveyedLink(secret.value);
      payload = link['payload'] as Map;
    } catch (e) {
      _logger.warning('Conveyed chain link is malformed; not publishing: $e');
      return false;
    }

    if (payload['childEnrollmentId'] != enrollmentId) {
      _logger.warning('Conveyed chain link vouches for enrollment '
          '${payload['childEnrollmentId']}, not for $enrollmentId; not '
          'publishing it here');
      return false;
    }

    try {
      await sharing.verifyEnvelopeSignature(link, signerAtSign: atSign);
    } catch (e) {
      _logger.warning('Conveyed chain link does not verify against the '
          'enrollment it names as signer, so publishing it would advertise a '
          'link no verifier can follow: $e');
      return false;
    }

    final AtValue current;
    try {
      current = await atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } catch (e) {
      _logger.warning('This enrollment has no readable _apsk to publish a '
          'chain link onto: $e');
      return false;
    }

    if (payload['apkamPublicKey'] != current.value) {
      _logger.warning('Conveyed chain link vouches for a key that is not the '
          'one published for $enrollmentId; not publishing it');
      return false;
    }

    final existing = await readLink(atClient, enrollmentId);
    if (existing != null && existing['signature'] == link['signature']) {
      return false;
    }

    await publishLink(atClient, enrollmentId, link);
    return true;
  }

  /// Decodes a link that arrived over the substrate as a [Secret] value.
  static Map<String, Object?> decodeConveyedLink(String secretValue) =>
      (jsonDecode(secretValue) as Map).cast<String, Object?>();

  /// Encodes a link for conveyance as a [Secret] value.
  static String encodeLink(Map<String, Object?> link) => jsonEncode(link);
}
