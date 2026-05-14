// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

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

      if (notificationParams.messageType == MessageTypeEnum.key &&
          ak.metadata.namespaceAware) {
        ak.namespace ??= atClientPreference.namespace;
        if (atClientPreference.namespace != null &&
            !'${ak.key}.${ak.namespace}'
                .endsWith('.${atClientPreference.namespace!}')) {
          ak.key = '${ak.key}.${ak.namespace}';
          ak.namespace = atClientPreference.namespace;
        }
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

  void _addMetadataToBuilder(
      NotifyVerbBuilder builder, NotificationParams notificationParams) {
    builder.atKey.metadata.ttl = notificationParams.atKey.metadata.ttl;
    builder.atKey.metadata.ttb = notificationParams.atKey.metadata.ttb;
    builder.atKey.metadata.ttr = notificationParams.atKey.metadata.ttr;
    builder.atKey.metadata.ccd = notificationParams.atKey.metadata.ccd;
    builder.atKey.metadata.isPublic =
        notificationParams.atKey.metadata.isPublic;
    builder.atKey.metadata.isEncrypted =
        notificationParams.atKey.metadata.isEncrypted;
    builder.atKey.metadata.sharedKeyEnc =
        notificationParams.atKey.metadata.sharedKeyEnc;
    builder.atKey.metadata.pubKeyCS =
        notificationParams.atKey.metadata.pubKeyCS;
    builder.atKey.metadata.encKeyName =
        notificationParams.atKey.metadata.encKeyName;
    builder.atKey.metadata.encAlgo = notificationParams.atKey.metadata.encAlgo;
    builder.atKey.metadata.ivNonce = notificationParams.atKey.metadata.ivNonce;
    builder.atKey.metadata.skeEncKeyName =
        notificationParams.atKey.metadata.skeEncKeyName;
    builder.atKey.metadata.skeEncAlgo =
        notificationParams.atKey.metadata.skeEncAlgo;
    builder.atKey.metadata.pubKeyHash =
        notificationParams.atKey.metadata.pubKeyHash;
    builder.atKey.metadata.appMetadata =
        notificationParams.atKey.metadata.appMetadata;
  }

  Future<String> _encryptNotificationValue(AtKey atKey, String value) async {
    // Fetch encryption scheme
    CryptoScheme scheme;
    if (atKey.metadata.appMetadata != null) {
      try {
        var schemeName = atKey.metadata.appMetadata!.encryptionScheme;
        scheme = _atClient.atChops!.schemes.lookup(schemeName);
      } on AtException catch (e) {
        e.stack(AtChainedException(
            Intent.fetchCryptoScheme,
            ExceptionScenario.decryptionFailed,
            'Failed to fetch crypto scheme'));
        rethrow;
      }
    } else {
      scheme = _atClient.atChops!.schemes.lookup('legacy');
    }
    try {
      return await scheme.encrypt(atKey, value);
    } on AtException catch (e) {
      e.stack(AtChainedException(
          Intent.notifyData, ExceptionScenario.encryptionFailed, e.message));
      rethrow;
    }
  }
}
