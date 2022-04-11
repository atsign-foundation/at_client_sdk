
import 'dart:io';
import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';
// ignore: prefer_typing_uninitialized_variables
void main() {
  var currentAtSign, sharedWithAtSign;
  AtClientManager? currentAtSignClientManager, sharedWithAtSignClientManager;
  var namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    // Create atClient instance for currentAtSign
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // Set Encryption Keys for currentAtSign
    await TestUtils.setEncryptionKeys(currentAtSign);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    // Create atClient instance for atSign2
    sharedWithAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestUtils.getPreference(sharedWithAtSign));
    // Set Encryption Keys for sharedWithAtSign
    await TestUtils.setEncryptionKeys(sharedWithAtSign);
    isSyncInProgress = true;
    sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });

  
  /// The purpose of this test verify the following:
  /// 1. Put method - public key
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb in the same atsign and different atsign
  /// 4. plookup of a key should create a cached key
  test('Create a public key and lookup from different atSign',
      () async {
    var lastNumber = Random().nextInt(50);
    var phoneKey = AtKey()
      ..key = 'phone_$lastNumber'
      ..metadata = (Metadata()..ttl = 120000
      ..isPublic = true);

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+1 100 200 30$lastNumber';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(phoneKey, value);
    expect(putResult, true);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    /// lookup of a public key
    var metadata = Metadata()
    ..isPublic = true;
    var getResult = await sharedWithAtSignClientManager?.atClient.get(
      AtKey() ..key = 'phone_$lastNumber' 
      ..sharedBy = currentAtSign
      ..metadata = metadata);
    expect(getResult?.value, value);
    // looking up of cached key in the [sharedWith] atsign
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    metadata = Metadata()
    ..isCached = true
    ..isPublic = true;
    var getCachedResult = await sharedWithAtSignClientManager?.atClient.get(AtKey() 
      ..key = 'phone_$lastNumber' 
      ..sharedBy = currentAtSign
      ..metadata = metadata);
    expect(getCachedResult?.value, value);
  }, timeout: Timeout(Duration(minutes: 5)));

  test('Create a private key and lookup from different atSign',
      () async {
    var lastNumber = Random().nextInt(50);
    var authCodeKey = AtKey()
      ..key = 'auth-code_$lastNumber'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata() ..ttr = 864000);

    // Appending a random number as a last number to generate a new auth-code number
    // for each run.
    var value = 'QR345R$lastNumber';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(authCodeKey, value);
    expect(putResult, true);
    var getResultCurrentAtsign = await currentAtSignClientManager?.atClient.get(authCodeKey);
    expect(getResultCurrentAtsign?.value, value);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    await Future.delayed(Duration(seconds: 1));
    var metadata = Metadata()
    ..isCached= true;
    var getResultSharedWithAtsign = await sharedWithAtSignClientManager?.atClient.get(AtKey() 
      ..key = 'auth-code_$lastNumber' 
      ..namespace = 'wavi'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = metadata);
    expect(getResultSharedWithAtsign?.value, value);
    expect(getResultSharedWithAtsign?.metadata!.pubKeyCS, getResultCurrentAtsign?.metadata!.pubKeyCS);
    expect(getResultSharedWithAtsign?.metadata!.sharedKeyEnc, getResultCurrentAtsign?.metadata!.sharedKeyEnc);
    // verifying pubKeyCS and sharedKeyEnc is same in both sender and receiver
    expect(getResultCurrentAtsign?.metadata!.pubKeyCS, equals(getResultSharedWithAtsign?.metadata!.pubKeyCS));
    expect(getResultCurrentAtsign?.metadata!.sharedKeyEnc, equals(getResultSharedWithAtsign?.metadata!.sharedKeyEnc));
  }, timeout: Timeout(Duration(minutes: 2)));

  test('Create a private key with ttl and lookup from different atSign',
      () async {
    var lastNumber = Random().nextInt(50);
    var tempCodeKey = AtKey()
      ..key = 'tempCode$lastNumber'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata() 
      ..ttl = 3000
      ..ttr = 864000);

    // Appending a random number as a last number to generate a new temp-code number
    // for each run.
    var value = 'EEE09$lastNumber';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(tempCodeKey, value);
    expect(putResult, true);
    var getResultCurrentAtsign = await currentAtSignClientManager?.atClient.get(tempCodeKey);
    expect(getResultCurrentAtsign?.value, value);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    /// fetching value before the ttl time 
    var metadata = Metadata()
    ..isCached= true;
    var getKey = AtKey() 
      ..key = 'tempCode$lastNumber' 
      ..namespace = 'wavi'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = metadata;
    var getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
    expect(getResult?.value, value);
    expect(getResult?.metadata!.pubKeyCS, getResultCurrentAtsign?.metadata!.pubKeyCS);
    expect(getResult?.metadata!.sharedKeyEnc, getResultCurrentAtsign?.metadata!.sharedKeyEnc);
    // looking up after ttl time
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
    expect(getResult?.value, null);
  }, timeout: Timeout(Duration(minutes: 2)));
  
  test('Create a private key with ttb and lookup from different atSign',
      () async {
    var lastNumber = Random().nextInt(50);
    var passCodeKey = AtKey()
      ..key = 'passCode$lastNumber'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata() 
      ..ttb = 1000
      ..ttr = 864000);

    // Appending a random number as a last number to generate a new temp-code number
    // for each run.
    var value = '89023$lastNumber';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(passCodeKey, value);
    expect(putResult, true);
  //  wait till the ttb time is reached
    await Future.delayed(Duration(seconds: 1));
    var getResultCurrentAtsign = await currentAtSignClientManager?.atClient.get(passCodeKey);
    expect(getResultCurrentAtsign?.value, value);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    /// fetching value before the ttb time 
    var metadata = Metadata()
    ..isCached= true;
    var getKey = AtKey() 
      ..key = 'passCode$lastNumber' 
      ..namespace = 'wavi'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = metadata;
    var getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
    expect(getResult?.value, null);
    // looking up after ttl time
    isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
    expect(getResult?.value, value);
     expect(getResult?.metadata!.pubKeyCS, getResultCurrentAtsign?.metadata!.pubKeyCS);
    expect(getResult?.metadata!.sharedKeyEnc, getResultCurrentAtsign?.metadata!.sharedKeyEnc);
  }, timeout: Timeout(Duration(minutes: 2)));
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

