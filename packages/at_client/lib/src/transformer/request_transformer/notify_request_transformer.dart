// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/encryption_service/encryption.dart';

/// Class is responsible for taking the [NotificationParams] and converting into [NotifyVerbBuilder]
class NotificationRequestTransformer
    implements Transformer<NotificationParams, VerbBuilder> {
  late String currentAtSign;
  late AtClientPreference atClientPreference;
  late AtKeyEncryption atKeyEncryption;

  NotificationRequestTransformer(
      this.currentAtSign, this.atClientPreference, this.atKeyEncryption);

  @override
  Future<NotifyVerbBuilder> transform(
      NotificationParams notificationParams) async {
    // prepares notification builder
    NotifyVerbBuilder builder = await _prepareNotificationBuilder(
        notificationParams, atClientPreference);
    // If notification value is not null, encrypt the value
    if (notificationParams.value.isNotNull) {
      builder.value = await _encryptNotificationValue(
          notificationParams.atKey, notificationParams.value!);
    }
    // add metadata to notify verb builder.
    // Encrypt the data and then call addMetadataToBuilder method inorder to
    // populate the sharedKeyEnc and publicKey checksum that are set during encryption process.
    _addMetadataToBuilder(builder, notificationParams);
    return builder;
  }

  Future<NotifyVerbBuilder> _prepareNotificationBuilder(
      NotificationParams notificationParams,
      AtClientPreference atClientPreference) async {
    var builder = NotifyVerbBuilder()
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
    // Append namespace only to message type key. For message type text do not
    // append namespaces.
    if (notificationParams.messageType == MessageTypeEnum.key) {
      builder.atKey.key = AtClientUtil.getKeyWithNameSpace(
          notificationParams.atKey, atClientPreference);
    }
    // ignore: deprecated_member_use
    if (notificationParams.messageType == MessageTypeEnum.text) {
      if (notificationParams.atKey.metadata.isEncrypted) {
        builder.atKey.key = await _encryptNotificationValue(
            notificationParams.atKey, notificationParams.atKey.key);
      } else {
        builder.atKey.key = notificationParams.atKey.key;
      }
    }
    return builder;
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
  }

  Future<String> _encryptNotificationValue(AtKey atKey, String value) async {
    try {
      return await atKeyEncryption.encrypt(atKey, value);
    } on AtException catch (e) {
      e.stack(AtChainedException(Intent.notifyData,
          ExceptionScenario.encryptionFailed, 'Failed to encrypt the data'));
      rethrow;
    }
  }
}
