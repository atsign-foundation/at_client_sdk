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
    // If metadata is not set, initialize Metadata instance.
    notificationParams.atKey.metadata ??= Metadata();
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
      ..sharedBy = notificationParams.atKey.sharedBy
      ..sharedWith = notificationParams.atKey.sharedWith
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
      builder.atKey = AtClientUtil.getKeyWithNameSpace(
          notificationParams.atKey, atClientPreference);
    }
    if (notificationParams.messageType == MessageTypeEnum.text) {
      if (notificationParams.atKey.metadata!.isEncrypted!) {
        builder.atKey = await _encryptNotificationValue(
            notificationParams.atKey, notificationParams.atKey.key!);
      } else {
        builder.atKey = notificationParams.atKey.key;
      }
    }
    return builder;
  }

  void _addMetadataToBuilder(
      NotifyVerbBuilder builder, NotificationParams notificationParams) {
    builder.ttl = notificationParams.atKey.metadata?.ttl;
    builder.ttb = notificationParams.atKey.metadata?.ttb;
    builder.ttr = notificationParams.atKey.metadata?.ttr;
    builder.ccd = notificationParams.atKey.metadata?.ccd;
    builder.isPublic = notificationParams.atKey.metadata!.isPublic!;
    if (notificationParams.atKey.metadata!.isEncrypted != null) {
      builder.isTextMessageEncrypted =
          notificationParams.atKey.metadata!.isEncrypted!;
    }
    builder.sharedKeyEncrypted =
        notificationParams.atKey.metadata?.sharedKeyEnc;
    builder.pubKeyChecksum = notificationParams.atKey.metadata?.pubKeyCS;
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
