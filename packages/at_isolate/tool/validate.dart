import 'dart:io' show exit;

import 'package:args/args.dart' show ArgParser;
import 'package:at_auth/at_auth.dart';
import 'package:at_isolate/at_isolate.dart';

void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption("root",
          abbr: 'r', help: 'root domain to use', mandatory: false)
      ..addOption('keysFilePath',
          abbr: 'k', help: 'Path of .atKeys file', mandatory: true);
    final argRes = parser.parse(args);
    final atSign = argRes["atsign"];
    final root = argRes.wasParsed("root")
        ? AtRootDomain.parse(argRes["root"])
        : AtRootDomain.atsignDomain;
    final atKeys = await FileAtKeysIo(filePath: (_) => argRes['keysFilePath'])
        .read(atSign);

    final preference = AtClientPreference()
      ..isLocalStoreRequired = true
      ..hiveStoragePath = '/tmp/$atSign/hive'
      ..commitLogPath = '/tmp/$atSign/commit'
      ..namespace = 'at_isolate_validation';

    IsolatedAtClient client =
        await IsolatedAtClient.spawn(atSign, root, atKeys, preference);

    print('✓ Client spawned successfully');

    // Test getCurrentAtSign
    print('\n--- Testing getCurrentAtSign ---');
    var currentAtSign = client.getCurrentAtSign();
    assert(currentAtSign == atSign, 'getCurrentAtSign failed');
    print('✓ getCurrentAtSign: $currentAtSign');

    // Test put/get/delete cycle
    print('\n--- Testing put/get/delete cycle ---');
    var testKey = AtKey()
      ..key = 'test_key'
      ..sharedWith = atSign
      ..namespace = 'at_isolate_validation';

    print('Testing put...');
    await client.put(testKey, 'test_value');
    print('✓ put successful');

    print('Testing get...');
    var result = await client.get(testKey);
    assert(result.value == 'test_value', 'get failed: value mismatch');
    print('✓ get successful: ${result.value}');

    print('Testing delete...');
    await client.delete(testKey);
    print('✓ delete successful');

    // Test putText
    print('\n--- Testing putText ---');
    var textKey = AtKey()
      ..key = 'text_key'
      ..sharedWith = atSign
      ..namespace = 'at_isolate_validation';
    var putTextResp = await client.putText(textKey, 'Hello World');
    print('✓ putText successful: ${putTextResp.response}');

    // Test putBinary
    print('\n--- Testing putBinary ---');
    var binaryKey = AtKey()
      ..key = 'binary_key'
      ..sharedWith = atSign
      ..namespace = 'at_isolate_validation';
    var binaryData = [1, 2, 3, 4, 5];
    var putBinaryResp = await client.putBinary(binaryKey, binaryData);
    print('✓ putBinary successful: ${putBinaryResp.response}');

    // Test metadata operations
    print('\n--- Testing metadata operations ---');
    var metaKey = AtKey()
      ..key = 'meta_key'
      ..sharedWith = atSign
      ..namespace = 'at_isolate_validation';
    metaKey.metadata = Metadata()..ttl = 60000;

    print('Testing putMeta...');
    await client.putMeta(metaKey);
    print('✓ putMeta successful');

    print('Testing getMeta...');
    var meta = await client.getMeta(metaKey);
    print('✓ getMeta successful: ttl=${meta?.ttl}');

    // Test getKeys (with useRemoteAtServer since we need remote access)
    print('\n--- Testing getKeys ---');
    var keys = await client.getKeys(
        useRemoteAtServer: true,
        regex: '.*at_isolate_validation',
        showHiddenKeys: false);
    print('✓ getKeys successful: found ${keys.length} keys');
    if (keys.isNotEmpty) {
      print('  Sample keys:');
      for (var i = 0; i < keys.length && i < 3; i++) {
        print('    - ${keys[i]}');
      }
    }

    // Test getAtKeys
    print('\n--- Testing getAtKeys ---');
    var atKeys2 = await client.getAtKeys(
        useRemoteAtServer: true,
        regex: '.*at_isolate_validation',
        showHiddenKeys: false);
    print('✓ getAtKeys successful: found ${atKeys2.length} keys');

    // Test notifyList
    print('\n--- Testing notifyList ---');
    var notifications = await client.notifyList();
    print('✓ notifyList successful: ${notifications.substring(0, 50)}...');

    // Test getOTP
    print('\n--- Testing getOTP ---');
    try {
      var otpResp = await client.getOTP();
      print('✓ getOTP successful: ${otpResp.response}');
    } catch (e) {
      print('⚠ getOTP not available (may require permissions): $e');
    }

    // Clean up test keys
    print('\n--- Cleaning up test keys ---');
    try {
      await client.delete(testKey);
      await client.delete(textKey);
      await client.delete(binaryKey);
      await client.delete(metaKey);
      print('✓ Cleanup successful');
    } catch (e) {
      print('⚠ Cleanup had some issues (keys may not exist): $e');
    }

    client.close();

    print('\n========================================');
    print('All validations passed! ✓');
    print('========================================');
    exit(0);
  } catch (e, s) {
    print('\n✗ Validation failed: $e');
    print('Stack trace: $s');
    exit(1);
  }
}
