import 'dart:io';
import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

late AtSignLogger logger;

void main() {
  AtSignLogger.root_level = 'warning';

  logger = AtSignLogger('at_lookup_race_test.dart');
  logger.level = 'info';

  setUpAll(() async {
  });
  tearDownAll(() async {
    if (await Directory('test/hive').exists()) {
      Directory('test/hive').deleteSync(recursive: true);
    }
  });


  test('race test - repeated gets without awaits', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    var namespace = 'at_lookup_race_test';

    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, namespace, preference);
    var atClient = atClientManager.atClient;

    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);

    Random random = Random();

    bool syncComplete = false;
    void onSyncDone(syncResult) {
      logger.shout("******* HELLO!!!!! ********");
      logger.info("syncResult.syncStatus: ${syncResult.syncStatus}");
      logger.info("syncResult.lastSyncedOn ${syncResult.lastSyncedOn}");
      syncComplete = true;
    }

    // Wait for initial sync to complete
    logger.info("Waiting for initial sync");
    syncComplete = false;
    atClientManager.syncService.sync(onDone: onSyncDone);
    while (! syncComplete) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    logger.info("Initial sync complete");

    // Create three public keys, then repeatedly get them and check they are as expected
    var fooKeyKey = 'foo';
    AtKey fooKey = AtKey()..key = fooKeyKey..metadata = (Metadata()..isPublic = true);
    var fooValue = 'FOO value';

    var barKeyKey = 'bar';
    AtKey barKey = AtKey()..key = barKeyKey..metadata = (Metadata()..isPublic = true);
    var barValue = 'BAR value';

    var bazKeyKey = 'baz';
    AtKey bazKey = AtKey()..key = bazKeyKey..metadata = (Metadata()..isPublic = true);
    var bazValue = 'BAZ value';

    logger.info("putting foo");
    await atClient.put(fooKey, fooValue);
    logger.info("putting bar");
    await atClient.put(barKey, barValue);
    logger.info("putting baz");
    await atClient.put(bazKey, bazValue);

    logger.info("Waiting for post-put sync");
    syncComplete = false;
    // Wait for initial sync to complete
    atClientManager.syncService.sync(onDone: onSyncDone);
    while (! syncComplete) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    logger.info("Post-put sync complete");


    var atLookup = atClient.getRemoteSecondary()!.atLookUp;

    int numRequests = 10;
    List<String> fooGetResponses = [];
    List<String> barGetResponses = [];
    List<String> bazGetResponses = [];
    for (int i = 0; i < numRequests; i++) {
      atLookup.lookup('$fooKeyKey.$namespace', atsign, auth:false)
          .then((value) => fooGetResponses.add(value.toString()));
      await Future.delayed(Duration(milliseconds: random.nextInt(5) + 3));

      atLookup.lookup('$barKeyKey.$namespace', atsign, auth:false)
          .then((value) => barGetResponses.add(value.toString()));
      await Future.delayed(Duration(milliseconds: random.nextInt(5) + 3));

      atLookup.lookup('$bazKeyKey.$namespace', atsign, auth:false)
          .then((value) => bazGetResponses.add(value.toString()));
      await Future.delayed(Duration(milliseconds: random.nextInt(5) + 3));

      // Wait 25..50 milliseconds
      // await Future.delayed(Duration(milliseconds: random.nextInt(26) + 25));
    }

    // Wait for size of all responses to equal 10, or time out
    logger.info ('Waiting for all responses to be received');
    int totalWaitTime = 0;
    int loopWaitTime = 100;
    int timeout = 10000;
    while (fooGetResponses.length < numRequests
        || barGetResponses.length < numRequests
        || bazGetResponses.length < numRequests) {

      await Future.delayed(Duration(milliseconds: loopWaitTime));
      totalWaitTime += loopWaitTime;
      if (totalWaitTime >= timeout) {
        throw TimeoutException("Didn't get all of our responses within timeout");
      }
    }

    logger.info ('All responses received');

    // Check results sanity
    var expectedCounts = {fooKeyKey : numRequests, barKeyKey : numRequests, bazKeyKey: numRequests};
    var actualCounts = {};

    actualCounts[fooKeyKey] = logResponsesAndCountCorrectMatches(fooKeyKey, fooGetResponses, fooValue);
    actualCounts[barKeyKey] = logResponsesAndCountCorrectMatches(barKeyKey, barGetResponses, barValue);
    actualCounts[bazKeyKey] = logResponsesAndCountCorrectMatches(bazKeyKey, bazGetResponses, bazValue);

    expect (actualCounts, equals(expectedCounts));
  });
}

int logResponsesAndCountCorrectMatches(String keyKey, List<String> getResponses, String expectedValue) {
  logger.info ('$keyKey : expected value is $expectedValue');
  int correct = 0;
  for (var r in getResponses) {
    if (r.replaceFirst('data:', '') == expectedValue) {
      logger.info ('          $r');
      correct++;
    } else {
      logger.severe ('\x1B[31m    !!! $r\x1B[0m');
    }
  }
  return correct;
}

AtClientPreference getAlicePreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
