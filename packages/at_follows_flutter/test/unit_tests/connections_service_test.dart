// ignoring this for the entire file to make it easier to detect real issues when doing review for publishing
// ignore_for_file: unused_local_variable

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client_mobile/at_client_mobile.dart' hide Atsign;
import 'package:at_follows_flutter/domain/atsign.dart';
import 'package:at_follows_flutter/domain/connection_model.dart';
import 'package:at_follows_flutter/services/connections_service.dart';
import 'package:at_follows_flutter/services/sdk_service.dart';
import 'package:at_follows_flutter/utils/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

import '../at_demo_credentials.dart' as demo_data;

SDKService _sdkService = SDKService();
ConnectionsService _connectionsService = ConnectionsService();

void main() {
  String senderAtsign = '@alice🛠';

  setUp(() async {
    _sdkService.setClientService = await setUpFunc(senderAtsign);
    final atClientManager = AtClientManager.getInstance();
    _connectionsService.init(senderAtsign);
    ConnectionProvider().init(senderAtsign);
    atClientManager.atClient.notificationService
        .subscribe()
        .listen((notification) {
      monitorCallBack(notification);
    });
  });

  group('test follow functionality', () {
    test('with valid @sign', () async {
      String receiverAtsign = '@bob🛠';

      await setUpFunc(receiverAtsign);
      AtClientManager.getInstance()
          .atClient
          .notificationService
          .subscribe()
          .listen((notification) {
        monitorCallBack(notification);
      });
      Atsign atsign = await (_connectionsService.follow(receiverAtsign)
          as FutureOr<Atsign>);
      expect(atsign.title, receiverAtsign);
      expect(
          _connectionsService.following.list!.contains(receiverAtsign), isTrue);
    });

    test('with same @sign', () async {
      Atsign? atsign = await _connectionsService.follow(senderAtsign);
      expect(atsign, null);
      expect(
          _connectionsService.following.list!.contains(senderAtsign), isFalse);
    });

    test('with existing @sign', () async {
      String receiverAtsign = '@bob🛠';
      Atsign atsign = await (_connectionsService.follow(receiverAtsign)
          as FutureOr<Atsign>);
      expect(atsign.title, receiverAtsign);
      expect(
          _connectionsService.following.list!.contains(receiverAtsign), isTrue);
      Atsign? atsign1 = await _connectionsService.follow(receiverAtsign);
      expect(atsign1, null);
    });

    test('to support wavi and persona namespace', () async {
      var firstAtSign = '@bob🛠';
      await setUpFunc(firstAtSign);
      var metadata = Metadata()
        ..isPublic = true
        ..namespaceAware = false;
      var bobFirstname = AtKey()
        ..key = 'firstname.persona'
        ..metadata = metadata;
      var bobLastname = AtKey()
        ..key = 'lastname.persona'
        ..metadata = metadata;

      await AtClientManager.getInstance().atClient.put(bobFirstname, 'Bob');
      await AtClientManager.getInstance().atClient.put(bobLastname, 'Geller');

      var secondAtSign = '@colin🛠';
      await setUpFunc(secondAtSign);
      var metadata1 = Metadata()..isPublic = true;
      var colinFirstname = AtKey()
        ..key = 'firstname'
        ..metadata = metadata1;
      var colinLastname = AtKey()
        ..key = 'lastname'
        ..metadata = metadata1;

      await AtClientManager.getInstance().atClient.put(colinFirstname, 'Colin');
      await AtClientManager.getInstance().atClient.put(colinLastname, 'Felton');

      Atsign atsign =
          await (_connectionsService.follow(firstAtSign) as FutureOr<Atsign>);
      expect(atsign.subtitle, 'Bob Geller');
      expect(_connectionsService.following.list!.contains(firstAtSign), isTrue);

      Atsign atsign1 =
          await (_connectionsService.follow(secondAtSign) as FutureOr<Atsign>);
      expect(atsign1.subtitle, 'Colin Felton');
      expect(
          _connectionsService.following.list!.contains(secondAtSign), isTrue);
    });
  });

  group('test unfollow functionality', () {
    test('with existing @sign', () async {
      String receiverAtsign = '@bob🛠';
      _connectionsService.following.add(receiverAtsign);
      bool result = await _connectionsService.unfollow(receiverAtsign);
      expect(result, true);
      expect(_connectionsService.following.list!.contains(receiverAtsign),
          isFalse);
    });

    test('with same @sign', () async {
      bool result = await _connectionsService.unfollow(senderAtsign);
      expect(result, false);
      expect(
          _connectionsService.following.list!.contains(senderAtsign), isFalse);
    });

    test('with non existing @sign', () async {
      String receiverAtsign = '@bob🛠';
      bool result = await _connectionsService.unfollow(receiverAtsign);
      expect(result, false);
      expect(_connectionsService.following.list!.contains(receiverAtsign),
          isFalse);
    });
  });

  group('test atsign list status change', () {
    test('change from public to private', () async {
      var connectionProvider = ConnectionProvider();
      await _connectionsService.getAtsignsList();
      String receiverAtsign = '@bob🛠';
      Atsign atsign = await (_connectionsService.follow(receiverAtsign)
          as FutureOr<Atsign>);
      expect(atsign.title, receiverAtsign);
      expect(
          _connectionsService.following.list!.contains(receiverAtsign), isTrue);
      expect(
          connectionProvider.connectionslistStatus.isFollowingPrivate, false);
      var result = await _connectionsService.changeListPublicStatus(true, true);
      expect(result, true);
      expect(
          _connectionsService.following.getKey!.atKey.metadata.isPublic, false);
    });
    test('change from private to public', () async {
      await _connectionsService.getAtsignsList();
      var connectionProvider = ConnectionProvider();
      String receiverAtsign = '@kevin🛠';
      Atsign atsign = await (_connectionsService.follow(receiverAtsign)
          as FutureOr<Atsign>);
      expect(atsign.title, receiverAtsign);
      expect(
          _connectionsService.following.list!.contains(receiverAtsign), isTrue);
      connectionProvider.connectionslistStatus.isFollowingPrivate = true;
      var result =
          await _connectionsService.changeListPublicStatus(true, false);
      expect(result, true);
      expect(
          _connectionsService.following.getKey!.atKey.metadata.isPublic, true);
    });
  });

  group('test namespace migration for wavi and persona', () {
    test('follow functioanlity with wavi and persona namespace support',
        () async {
      var firstAtSign = '@bob🛠';
      await setUpFunc(firstAtSign);
      var metadata = Metadata()
        ..isPublic = true
        ..namespaceAware = false;
      var bobFirstname = AtKey()
        ..key = 'firstname.persona'
        ..metadata = metadata;
      var bobLastname = AtKey()
        ..key = 'lastname.persona'
        ..metadata = metadata;

      await AtClientManager.getInstance().atClient.put(bobFirstname, 'Bob');
      await AtClientManager.getInstance().atClient.put(bobLastname, 'Geller');

      var secondAtSign = '@colin🛠';
      await setUpFunc(secondAtSign);
      var metadata1 = Metadata()..isPublic = true;
      var colinFirstname = AtKey()
        ..key = 'firstname'
        ..metadata = metadata1;
      var colinLastname = AtKey()
        ..key = 'lastname'
        ..metadata = metadata1;

      await AtClientManager.getInstance().atClient.put(colinFirstname, 'Colin');
      await AtClientManager.getInstance().atClient.put(colinLastname, 'Felton');

      var atMetadata = Metadata()..isPublic = true;
      var atKey1 = AtKey()
        ..key = AppConstants.following
        ..metadata = atMetadata;
      await _sdkService.put(atKey1, '@sameeraja🛠,@sitaram🛠');

      var followingValue =
          await _sdkService.scanAndGet('${AppConstants.following}');
      expect(followingValue.value.isNotEmpty, true);

      Atsign atsign =
          await (_connectionsService.follow(firstAtSign) as FutureOr<Atsign>);
      expect(atsign.subtitle, 'Bob Geller');
      expect(_connectionsService.following.list!.contains(firstAtSign), isTrue);

      Atsign atsign1 =
          await (_connectionsService.follow(secondAtSign) as FutureOr<Atsign>);
      expect(atsign1.subtitle, 'Colin Felton');
      expect(
          _connectionsService.following.list!.contains(secondAtSign), isTrue);
    });

    test('unfollow functionality', () async {
      var atMetadata = Metadata()..isPublic = true;

      var atKey1 = AtKey()
        ..key = AppConstants.following
        ..metadata = atMetadata;
      await _sdkService.put(atKey1, '@sameeraja🛠,@sitaram🛠');

      var followingValue =
          await _sdkService.scanAndGet('${AppConstants.following}');
      expect(followingValue.value.isNotEmpty, true);
      _connectionsService.following.add('@sameeraja🛠');
      _connectionsService.following.add('@sitaram🛠');

      bool result = await _connectionsService.unfollow('@sameeraja🛠');
      expect(result, true);
      expect(_connectionsService.following.list!.contains('@sameeraja🛠'),
          isFalse);
    });

    test('change liststatus from public to private', () async {
      var atMetadata = Metadata()..isPublic = true;

      var atKey1 = AtKey()
        ..key = AppConstants.following
        ..metadata = atMetadata;
      await _sdkService.put(atKey1, '@sameeraja🛠,@sitaram🛠');
      await _connectionsService.getAtsignsList();
      expect(
          _connectionsService.following.getKey!.atKey.metadata.isPublic, true);
      var result = await _connectionsService.changeListPublicStatus(true, true);
      expect(result, true);
      expect(
          _connectionsService.following.getKey!.atKey.metadata.isPublic, false);
    });

    test('change liststatus from private to public', () async {
      var atMetadata = Metadata()..isPublic = false;

      var atKey1 = AtKey()
        ..key = AppConstants.following
        ..sharedWith = senderAtsign
        ..metadata = atMetadata;
      await _sdkService.put(atKey1, '@sameeraja🛠,@sitaram🛠');
      await _connectionsService.getAtsignsList();
      expect(
          _connectionsService.following.getKey!.atKey.metadata.isPublic, false);

      var result =
          await _connectionsService.changeListPublicStatus(true, false);
      expect(result, true);
    });
  });
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

Future<AtAuthService> setUpFunc(String atsign) async {
  final atClientManager = AtClientManager.getInstance();
  AtAuthService atClientService =
      AtClientMobile.authService(atsign, getAtSignPreference(atsign));
  final atClient = atClientManager.atClient;
  atClientManager.atClient.syncService.sync();
  await setEncryptionKeys(atClient, atsign);
  return atClientService;
}

monitorCallBack(var response) {
  if (response == null) {
    return;
  }
  response = response.toString().replaceAll('notification:', '').trim();
  var notification = AtNotification.fromJson(jsonDecode(response));
  print(
      'Received notification:: id:${notification.id} key:${notification.key} operation:${notification.operation} from:${notification.from} to:${notification.to}');
}

AtClientPreference getAtSignPreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_data.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

setEncryptionKeys(AtClient atClient, String atsign) async {
  try {
    var metadata = Metadata();
    metadata.namespaceAware = false;
    var result;
    // set pkam private key
    result = await atClient.getLocalSecondary()!.putValue(
          AtConstants.atPkamPrivateKey,
          demo_data.pkamPrivateKeyMap[atsign]!,
        ); // set pkam public key
    result = await atClient.getLocalSecondary()!.putValue(
          AtConstants.atPkamPublicKey,
          demo_data.pkamPublicKeyMap[atsign]!,
        );
    // set encryption private key
    result = await atClient.getLocalSecondary()!.putValue(
          AtConstants.atEncryptionPrivateKey,
          demo_data.encryptionPrivateKeyMap[atsign]!,
        );
    //set aesKey
    result = await atClient.getLocalSecondary()!.putValue(
          AtConstants.atEncryptionSelfKey,
          demo_data.aesKeyMap[atsign]!,
        );

    // set encryption public key. should be synced
    metadata.isPublic = true;
    var atKey = AtKey()
      ..key = 'publickey'
      ..metadata = metadata;
    result =
        await atClient.put(atKey, demo_data.encryptionPublicKeyMap[atsign]);
    print(result);
  } catch (e) {
    print('setting localKeys throws $e');
  }
}
