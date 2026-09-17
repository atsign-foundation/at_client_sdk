// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart'
    show NamespaceKeyUnavailableException;
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

final AtSignLogger _logger = AtSignLogger('NotificationRequestTransformer');

/// Class is responsible for taking the [NotificationParams] and converting into [NotifyVerbBuilder]
class NotificationRequestTransformer
    implements Transformer<NotificationParams, VerbBuilder> {
  String get currentAtSign => _atClient.getCurrentAtSign()!;
  AtClientPreference get atClientPreference => _atClient.getPreferences()!;
  final AtClient _atClient;

  NotificationRequestTransformer(this._atClient);

  @override
  Future<NotifyVerbBuilder> transform(
      NotificationParams notificationParams) async {
    // NOTE: provider selection is namespace-sensitive — the nskey path is
    // (owner, namespace) scoped and declines a key without one — so the
    // namespace has to be resolved before a provider is chosen.
    _resolveNamespace(notificationParams);

    if (_shouldRouteThroughProvider(notificationParams)) {
      // NOTE: the provider id is stamped only once routing has settled — the
      // catch below may re-route to legacy, and a key stamped with a provider
      // that then declined would claim a scheme its value was never sealed
      // under.
      String providerId;
      try {
        providerId = await CryptoRuntime(_atClient).prepareWrite(
            notificationParams.atKey,
            requestedProviderId: notificationParams.cryptoProviderId,
            useRemoteAtServer: true,
            stampProviderId: false);
      } on NamespaceKeyUnavailableException catch (e) {
        if (!CryptoRuntime.mayFallBackToLegacy(atClientPreference)) rethrow;
        _logger.warning('falling back to legacy encryption for the '
            'notification of ${notificationParams.atKey.key}: ${e.message}');
        providerId = await CryptoRuntime(_atClient).prepareWrite(
            notificationParams.atKey,
            requestedProviderId: CryptoRuntime.legacyProviderId,
            useRemoteAtServer: true,
            stampProviderId: false);
      }
      notificationParams.atKey.metadata.appMetadata ??=
          AppMetadata(providerId: providerId);
    }
    // prepares notification builder
    NotifyVerbBuilder builder = await _prepareNotificationBuilder(
        notificationParams, atClientPreference);
    // If notification value is set and metadata.isEncrypted is true, encrypt
    // the value.
    if (notificationParams.value.isNotNull &&
        notificationParams.atKey.metadata.isEncrypted) {
      builder.value = await _encryptNotificationValue(
          notificationParams.atKey, notificationParams.value!);
    } else {
      builder.value = notificationParams.value;
    }
    // add metadata to notify verb builder.
    // Encrypt the data and then call addMetadataToBuilder method inorder to
    // populate the sharedKeyEnc and publicKey checksum that are set during encryption process.
    _addMetadataToBuilder(builder, notificationParams);
    return builder;
  }

  Future<NotifyVerbBuilder> _prepareNotificationBuilder(
    NotificationParams notificationParams,
    AtClientPreference atClientPreference,
  ) async {
    // ignore: deprecated_member_use
    if (notificationParams.messageType == MessageTypeEnum.text) {
      // NB: message type 'text' is obsolete and does not work.

      NotifyVerbBuilder builder = NotifyVerbBuilder()
        ..useAtKeyToString = false
        ..id = notificationParams.id
        ..atKey.sharedBy = notificationParams.atKey.sharedBy
        ..atKey.sharedWith = notificationParams.atKey.sharedWith
        ..operation = notificationParams.operation
        ..messageType = notificationParams.messageType
        ..priority = notificationParams.priority
        ..strategy = notificationParams.strategy
        ..latestN = notificationParams.latestN
        ..notifier = notificationParams.notifier
        ..ttln = notificationParams.notificationExpiry.inMilliseconds;

      if (notificationParams.atKey.metadata.isEncrypted) {
        builder.atKey.key = await _encryptNotificationValue(
            notificationParams.atKey, notificationParams.atKey.key);
      } else {
        builder.atKey.key = notificationParams.atKey.key;
      }
      return builder;
    } else {
      AtKey ak = notificationParams.atKey;

      if (_isNamespaceAware(notificationParams)) {
        ak = AtKey.fromString(ak.toString());
      }

      return NotifyVerbBuilder()
        ..useAtKeyToString = true
        ..id = notificationParams.id
        ..atKey = ak
        ..operation = notificationParams.operation
        ..messageType = notificationParams.messageType
        ..priority = notificationParams.priority
        ..strategy = notificationParams.strategy
        ..latestN = notificationParams.latestN
        ..notifier = notificationParams.notifier
        ..ttln = notificationParams.notificationExpiry.inMilliseconds;
    }
  }

  bool _isNamespaceAware(NotificationParams notificationParams) =>
      notificationParams.messageType == MessageTypeEnum.key &&
      notificationParams.atKey.metadata.namespaceAware;

  /// Fills in the preference's namespace, and folds a key that already carries
  /// a different one into the app namespace — in place, on the caller's AtKey.
  void _resolveNamespace(NotificationParams notificationParams) {
    if (!_isNamespaceAware(notificationParams)) return;
    final ak = notificationParams.atKey;
    ak.namespace ??= atClientPreference.namespace;
    if (atClientPreference.namespace != null &&
        !'${ak.key}.${ak.namespace}'
            .endsWith('.${atClientPreference.namespace!}')) {
      ak.key = '${ak.key}.${ak.namespace}';
      ak.namespace = atClientPreference.namespace;
    }
  }

  /// Carries the caller's metadata onto the builder, minus the fields the
  /// receiving atServer owns.
  ///
  /// Copying wholesale and then clearing is the deliberate polarity: a field
  /// added to [Metadata] later travels by default, and only the exclusions have
  /// to be maintained.
  void _addMetadataToBuilder(
      NotifyVerbBuilder builder, NotificationParams notificationParams) {
    builder.atKey.metadata = notificationParams.atKey.metadata.copy()
      // Derived by the receiving atServer from ttb/ttl/ttr, and stamped there
      // on write.
      ..availableAt = null
      ..expiresAt = null
      ..refreshAt = null
      ..createdAt = null
      ..updatedAt = null
      // Set by the atServer as it resolves the shared key, not by the sender.
      ..sharedKeyStatus = null
      // Local read-model flags; they mean nothing to the receiver.
      ..isCached = false
      ..isHidden = false
      ..namespaceAware = true;
  }

  Future<String> _encryptNotificationValue(AtKey atKey, String value) async {
    return await CryptoRuntime(_atClient).encryptForNotification(atKey, value);
  }

  bool _shouldRouteThroughProvider(NotificationParams notificationParams) {
    if (!notificationParams.atKey.metadata.isEncrypted) {
      return false;
    }
    if (notificationParams.value.isNotNull) {
      return true;
    }
    // ignore: deprecated_member_use
    return notificationParams.messageType == MessageTypeEnum.text;
  }
}
