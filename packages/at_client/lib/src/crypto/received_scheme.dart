import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart' show legacyCryptoProviderId;
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('ReceivedSchemes');

/// How a value another atSign shared with this client was protected.
class ReceivedScheme {
  /// The provider the value names, and the one to answer it in:
  /// [legacyCryptoProviderId] when the sender stamped none.
  final String providerId;

  /// The key-establishment algorithm the value's content key was sealed under
  /// ([SecretSharingAlgos.xWing] or [SecretSharingAlgos.mlKem1024]), or null
  /// for a legacy value and for one whose conveyance this client cannot read.
  final String? keyAlgorithm;

  /// The sealing suite [keyAlgorithm] seals under, or null when it is null.
  final String? suite;

  const ReceivedScheme(
      {required this.providerId, this.keyAlgorithm, this.suite});

  /// Whether the value was sealed post-quantum.
  bool get isPostQuantum => pqCryptoProviderIds.contains(providerId);

  @override
  bool operator ==(Object other) =>
      other is ReceivedScheme &&
      other.providerId == providerId &&
      other.keyAlgorithm == keyAlgorithm &&
      other.suite == suite;

  @override
  int get hashCode => Object.hash(providerId, keyAlgorithm, suite);

  @override
  String toString() => 'ReceivedScheme($providerId'
      '${keyAlgorithm == null ? '' : ', $keyAlgorithm, $suite'})';
}

/// Tells how values shared with this client were protected.
extension ReceivedSchemes on AtClient {
  /// How [key]'s value was protected, read from its metadata without
  /// decrypting it.
  ///
  /// [key]'s own metadata is used when it carries `appMetadata`, as a
  /// received notification's does; otherwise the stored record's, from local
  /// storage first and then from the sharer's atServer, which serves the
  /// metadata without the value. For a post-quantum value the algorithm and
  /// suite come from the record that conveyed its content key, read the same
  /// way, and are null when that record cannot be read.
  ///
  /// Every value @alice has shared with this client, grouped by how it was
  /// sealed:
  ///
  /// ```dart
  /// final byScheme = <ReceivedScheme, List<AtKey>>{};
  /// for (final key in await atClient.getAtKeys(sharedBy: '@alice')) {
  ///   final scheme = await atClient.schemeOf(key);
  ///   (byScheme[scheme] ??= []).add(key);
  /// }
  /// ```
  ///
  /// To answer a notification in the scheme it arrived in, pass
  /// `AtNotification.receivedUnder` as the reply's `cryptoProviderId`.
  Future<ReceivedScheme> schemeOf(AtKey key) async {
    final appMetadata =
        key.metadata.appMetadata ?? (await _metadataOf(key))?.appMetadata;
    final providerId = appMetadata?.providerId ?? legacyCryptoProviderId;
    final keyAlgorithm = providerId == symmetricAesGcmCryptoProviderId
        ? await _conveyedUnder(key, appMetadata!)
        : _keyAlgorithmOf(providerId);
    return ReceivedScheme(
      providerId: providerId,
      keyAlgorithm: keyAlgorithm,
      suite: keyAlgorithm == null
          ? null
          : SecretSharingAlgos.suiteForKeyAlgo(keyAlgorithm),
    );
  }

  /// The key-establishment algorithm a content key conveyed under
  /// [providerId] was sealed with, or null for any other provider.
  static String? _keyAlgorithmOf(String? providerId) => switch (providerId) {
        nskeyCryptoProviderId => SecretSharingAlgos.xWing,
        mlKemNskeyCryptoProviderId => SecretSharingAlgos.mlKem1024,
        _ => null,
      };

  /// [key]'s stored metadata: local storage's, else the atServer's.
  Future<Metadata?> _metadataOf(AtKey key) async =>
      await _localMetadataOf(key) ?? await _remoteMetadataOf(key);

  /// The metadata of [key], which another atSign owns, as the atServer serves
  /// it without the value.
  Future<Metadata?> _remoteMetadataOf(AtKey key) async {
    final lookup = LookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = key.key
        ..namespace = key.namespace
        ..sharedBy = key.sharedBy)
      ..auth = true
      ..operation = 'meta';
    final response = await getRemoteSecondary()!.executeVerb(lookup);
    return AtClientUtil.prepareMetadata(
        JsonUtils.decodeJson(DefaultResponseParser().parse(response).response),
        false);
  }

  Future<Metadata?> _localMetadataOf(AtKey key) async {
    try {
      return (await getLocalSecondary()?.keyStore?.getMeta(key.toString()))
          ?.toCommonsMetadata();
    } on KeyNotFoundException {
      return null;
    }
  }

  /// The algorithm the content key of [value] was conveyed under, read from
  /// the conveyance record's provider; null when it cannot be read.
  Future<String?> _conveyedUnder(AtKey value, AppMetadata appMetadata) async {
    final additional = appMetadata.additional;
    final ckKid = additional?['ckKid'] as String?;
    final ckNs = additional?['ckNs'] as String? ??
        additional?['ns'] as String? ??
        value.namespace;
    if (ckKid == null || ckNs == null) return null;

    final conveyance = SymmetricAesGcmProvider.openableConveyanceKeyFor(
        value, ckKid, ckNs, getCurrentAtSign());
    final cachedCopy = AtKey()
      ..key = conveyance.key
      ..namespace = conveyance.namespace
      ..sharedBy = conveyance.sharedBy
      ..sharedWith = conveyance.sharedWith
      ..metadata = (Metadata()..isCached = true);
    try {
      for (final candidate in [cachedCopy, conveyance]) {
        final local = await _localMetadataOf(candidate);
        if (local?.appMetadata != null) {
          return _keyAlgorithmOf(local!.appMetadata!.providerId);
        }
      }
      return _keyAlgorithmOf(
          (await _remoteMetadataOf(conveyance))?.appMetadata?.providerId);
    } catch (e) {
      if (e is StoppedException) rethrow;
      _logger.info('Could not read the conveyance $conveyance, so the'
          ' algorithm its content key was sealed under is unknown: $e');
      return null;
    }
  }
}
