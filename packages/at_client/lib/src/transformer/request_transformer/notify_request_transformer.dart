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
      final providerId = await CryptoRuntime(_atClient).negotiatedProviderIdFor(
          notificationParams.cryptoProviderId,
          atKey: notificationParams.atKey);
      notificationParams.atKey.metadata.appMetadata ??=
          AppMetadata(providerId: providerId);
      // Same preparation step the put path runs, and for the same reason: a
      // provider that has to write a record of its own — a key conveyance —
      // cannot do it from inside encrypt, which is called part-way through
      // building the verb builder below.
      //
      // Routed remote, unconditionally, where a put passes its own routing
      // through: a notification is remote-only by construction. It leaves for
      // the recipient's atServer the moment this returns, so a conveyance left
      // to reach the atServer by sync is announced before it exists — and the
      // recipient resolves the content key inline, on arrival, with nothing to
      // find.
      await CryptoRuntime(_atClient).prepareForPut(
          notificationParams.atKey, providerId,
          useRemoteAtServer: true);
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
  /// Carries the caller's metadata onto the builder, minus what the sender has
  /// no business asserting.
  ///
  /// Copying wholesale and then clearing is the deliberate polarity: a field
  /// added to [Metadata] later travels by default, and only the exclusions —
  /// which are the atServer's to set, not a client's to claim — have to be
  /// maintained. The hand-rolled inclusion list this replaces dropped
  /// `immutable` and `appMetadata` for exactly as long as nobody noticed.
  void _addMetadataToBuilder(
      NotifyVerbBuilder builder, NotificationParams notificationParams) {
    builder.atKey.metadata = notificationParams.atKey.metadata.copy()
      // Derived on the receiving atServer from ttb/ttl/ttr, and stamped there
      // on write. A sender asserting them would be describing a record it does
      // not own the clock for.
      ..availableAt = null
      ..expiresAt = null
      ..refreshAt = null
      ..createdAt = null
      ..updatedAt = null
      // Set by the atServer as it resolves the shared key, not by the sender.
      ..sharedKeyStatus = null
      // Local read-model flags. They describe how *this* client holds the
      // record, and mean nothing to the receiver.
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
