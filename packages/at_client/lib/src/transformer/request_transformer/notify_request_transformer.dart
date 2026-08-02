// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
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
    // Before anything looks at the key, give it its namespace. Provider
    // selection is namespace-sensitive — the nskey path is (owner, namespace)
    // scoped and declines a key without one — so choosing a provider first
    // would silently pick legacy for every key that relies on the preference
    // default, and the put path (which resolves the namespace first) would
    // then encrypt the very same key differently.
    _resolveNamespace(notificationParams);

    if (_shouldRouteThroughProvider(notificationParams)) {
      final providerId = CryptoRuntime.providerIdFor(
          _atClient, notificationParams.cryptoProviderId,
          atKey: notificationParams.atKey);
      notificationParams.atKey.metadata.appMetadata ??=
          AppMetadata(providerId: providerId);
      // Same preparation step the put path runs, and for the same reason: a
      // provider that has to write a record of its own — a key conveyance —
      // cannot do it from inside encrypt, which is called part-way through
      // building the verb builder below.
      await CryptoRuntime(_atClient)
          .prepareForPut(notificationParams.atKey, providerId);
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

      // The namespace was resolved in transform(); this only re-parses the key
      // so the builder gets a normalised copy.
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

  /// Fill in the preference's namespace, and fold a key that already carries a
  /// different one into the app namespace — in place, on the caller's AtKey.
  ///
  /// This ran inside the builder step until provider selection moved ahead of
  /// it. Both need the namespace, and the builder needs it *after* whatever
  /// encryption chose, so it has to happen before either.
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

  /// Copy the record's own metadata onto the builder.
  ///
  /// Everything a *reader* needs to interpret the value has to travel: the
  /// crypto routing, and the fields that decide how the payload is decoded.
  /// `isBinary`, `encoding` and `dataSignature` were missing, which is the same
  /// silent-drop shape as the sync push that dropped `appMetadata` — a
  /// provider branches on `isBinary` to choose its wire format, so losing it
  /// makes a binary notification decode as text.
  ///
  /// The timestamps and `sharedKeyStatus` are deliberately *not* copied: the
  /// atServer derives those on receipt, exactly as the sync push leaves them
  /// out. Sending a client's idea of `createdAt` would be the client asserting
  /// something the server owns.
  void _addMetadataToBuilder(
      NotifyVerbBuilder builder, NotificationParams notificationParams) {
    builder.atKey.metadata.isBinary =
        notificationParams.atKey.metadata.isBinary;
    builder.atKey.metadata.immutable =
        notificationParams.atKey.metadata.immutable;
    builder.atKey.metadata.encoding =
        notificationParams.atKey.metadata.encoding;
    builder.atKey.metadata.dataSignature =
        notificationParams.atKey.metadata.dataSignature;
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
