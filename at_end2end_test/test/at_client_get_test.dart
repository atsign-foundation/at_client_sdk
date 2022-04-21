import 'dart:io';
import 'package:uuid/uuid.dart';

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
  test('Create a public key and lookup from different atSign', () async {
    var uuid = Uuid();
    // Generate a v1 (time-based) id
    var randomValue = uuid.v4();
    var usernameKey = AtKey()
      ..key = 'username$randomValue'
      ..metadata = (Metadata()
        ..ttl = 120000
        ..isPublic = true);

    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = 'user123';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(usernameKey, value);
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
    var metadata = Metadata()..isPublic = true;
    var getResult = await sharedWithAtSignClientManager?.atClient.get(AtKey()
      ..key = 'username$randomValue'
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
    var getCachedResult =
        await sharedWithAtSignClientManager?.atClient.get(AtKey()
          ..key = 'username$randomValue'
          ..sharedBy = currentAtSign
          ..metadata = metadata);
    expect(getCachedResult?.value, value);
  }, timeout: Timeout(Duration(minutes: 5)));

  /// The purpose of this test verify the following:
  /// 1. Put method - shared key
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb in the same atsign and different atsign
  /// 4. Verifying the pubkeycs and sharedkeyenc is same in both the atsigns
  test('Create a private key and lookup from different atSign', () async {
    var uuid = Uuid();
    // Generate  uuid
    var randomValue = uuid.v4();
    var authCodeKey = AtKey()
      ..key = 'auth-code$randomValue'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata()..ttr = 864000);

    // Appending a random number as a last number to generate a new auth-code number
    // for each run.
    var value = 'QR345R';
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var putResult =
        await currentAtSignClientManager?.atClient.put(authCodeKey, value);
    expect(putResult, true);
    var getResultCurrentAtsign =
        await currentAtSignClientManager?.atClient.get(authCodeKey);
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
    await Future.delayed(Duration(seconds: 2));
    var metadata = Metadata()..isCached = true;
    var getResultSharedWithAtsign =
        await sharedWithAtSignClientManager?.atClient.get(AtKey()
          ..key = 'auth-code$randomValue'
          ..namespace = 'wavi'
          ..sharedWith = sharedWithAtSign
          ..sharedBy = currentAtSign
          ..metadata = metadata);
    expect(getResultSharedWithAtsign?.value, value);
    expect(getResultSharedWithAtsign?.metadata!.pubKeyCS,
        getResultCurrentAtsign?.metadata!.pubKeyCS);
    expect(getResultSharedWithAtsign?.metadata!.sharedKeyEnc,
        getResultCurrentAtsign?.metadata!.sharedKeyEnc);
    // verifying pubKeyCS and sharedKeyEnc is same in both sender and receiver
    expect(getResultCurrentAtsign?.metadata!.pubKeyCS,
        equals(getResultSharedWithAtsign?.metadata!.pubKeyCS));
    expect(getResultCurrentAtsign?.metadata!.sharedKeyEnc,
        equals(getResultSharedWithAtsign?.metadata!.sharedKeyEnc));
  }, timeout: Timeout(Duration(minutes: 2)));

  ///  Commenting the ttl,ttb tests till the sync bug is fixed
  
  /// The purpose of this test verify the following:
  /// 1. Put method - private key with ttl
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb in the different atsign before the ttl time
  /// 4. Get method - lookup verb in the different atsign after the ttl time

  // test('Create a private key with ttl and lookup from different atSign',
  //     () async {
  //   var uuid = Uuid();
  //   // Generate  uuid
  //   var randomValue = uuid.v4();
  //   var tempCodeKey = AtKey()
  //     ..key = 'tempCode$randomValue'
  //     ..sharedWith = sharedWithAtSign
  //     ..metadata = (Metadata()..ttl = 4000);

  //   // Appending a random number as a last number to generate a new temp-code number
  //   // for each run.
  //   var value = 'EEE09';
  //   // Setting currentAtSign atClient instance to context.
  //   await AtClientManager.getInstance().setCurrentAtSign(
  //       currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
  //   var putResult =
  //       await currentAtSignClientManager?.atClient.put(tempCodeKey, value);
  //   expect(putResult, true);
  //   var getResultCurrentAtsign =
  //       await currentAtSignClientManager?.atClient.get(tempCodeKey);
  //   expect(getResultCurrentAtsign?.value, value);
  //   var isSyncInProgress = true;
  //   currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
  //     isSyncInProgress = false;
  //   });
  //   while (isSyncInProgress) {
  //     await Future.delayed(Duration(milliseconds: 5));
  //   }
  //   // Setting sharedWithAtSign atClient instance to context.
  //   await AtClientManager.getInstance().setCurrentAtSign(
  //       sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
  //   isSyncInProgress = true;
  //   sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
  //     isSyncInProgress = false;
  //   });
  //   while (isSyncInProgress) {
  //     await Future.delayed(Duration(milliseconds: 5));
  //   }

  //   /// fetching value before the ttl time
  //   var getKey = AtKey()
  //     ..key = 'tempCode$randomValue'
  //     ..namespace = 'wavi'
  //     ..sharedWith = sharedWithAtSign
  //     ..sharedBy = currentAtSign;
  //   // Adding Future.delayed for the key to expire
  //   await Future.delayed(Duration(seconds: 3));
  //   // fetching value after the ttl time
  //   isSyncInProgress = true;
  //   sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
  //     isSyncInProgress = false;
  //   });
  //   while (isSyncInProgress) {
  //     await Future.delayed(Duration(milliseconds: 5));
  //   }
  //   var getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
  //   expect(getResult?.value, null);
  // }, timeout: Timeout(Duration(minutes: 2)));

  /// The purpose of this test verify the following:
  /// 1. Put method - private key with ttb
  /// 2. Sync to cloud secondary
  /// 3. Get method - lookup verb in the different atsign before the ttb time
  /// 4. Get method - lookup verb in the different atsign after the ttb time
  // test('Create a private key with ttb and lookup from different atSign',
  //     () async {
  //   var uuid = Uuid();
  //   // Generate  uuid
  //   var randomValue = uuid.v4();
  //   await AtClientManager.getInstance().setCurrentAtSign(
  //       currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
  //   var key1 = AtKey()
  //     ..key = 'key_$randomValue'
  //     ..sharedWith = sharedWithAtSign
  //     ..sharedBy = currentAtSign
  //     ..metadata = (Metadata()..ttb = 6000);
  //   var value = '90192!QR';
  //   var putResult = await currentAtSignClientManager?.atClient.put(key1, value);
  //   print('put result is $putResult');
  //   expect(putResult, true);
  //   var isSyncInProgress = true;
  //   currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
  //     isSyncInProgress = false;
  //   });
  //   while (isSyncInProgress) {
  //     await Future.delayed(Duration(milliseconds: 5));
  //   }
  //   // setting the context to sharedWith Atsign
  //   await AtClientManager.getInstance().setCurrentAtSign(
  //       sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
  //   isSyncInProgress = true;
  //   sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
  //     isSyncInProgress = false;
  //   });
  //   while (isSyncInProgress) {
  //     await Future.delayed(Duration(milliseconds: 5));
  //   }
  //   // lookup for the key before the ttb time
  //   var getKey = AtKey()
  //     ..key = 'key_$randomValue'
  //     ..sharedBy = currentAtSign
  //     ..sharedWith = sharedWithAtSign;
  //   var getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
  //   print('get Result is $getResult');
  //   expect(getResult?.value, null);
  //   //  Wait till the ttb time is reached
  //   await Future.delayed(Duration(seconds: 5));
  //   isSyncInProgress = true;
  //   sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
  //     isSyncInProgress = false;
  //   });
  //   while (isSyncInProgress) {
  //     await Future.delayed(Duration(milliseconds: 5));
  //   }
  //   getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
  //   expect(getResult?.value, value);
  // }, timeout: Timeout(Duration(minutes: 2)));
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
