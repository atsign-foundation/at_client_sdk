import 'dart:io';

import 'package:args/args.dart';

import '../external_signer.dart';

import 'package:at_utils/at_logger.dart';

Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'FINEST';
  var parser = ArgParser();
  parser.addOption('privateKeyId',
      abbr: 'p',
      mandatory: true,
      help: 'Private key id from sim card used to sign pkam challenge');
  parser.addOption('serialPort',
      abbr: 's',
      mandatory: false,
      defaultsTo: '/dev/ttyS0',
      help: 'serial port on which sim card is mounted');
  parser.addOption('libPeripheryLocation',
      abbr: 'l',
      mandatory: false,
      defaultsTo: '/usr/lib/arm-linux-gnueabihf/libperiphery_arm.so',
      help: 'location of native library libperiphery_arm.so');
  parser.addOption('keyId',
      abbr: 'k', mandatory: true, help: 'key id from sim used to compute PRF');
  parser.addOption('simSecret',
      abbr: 't', mandatory: true, help: 'secret from sim');
  parser.addOption('labelId',
      abbr: 'i', mandatory: true, help: 'label id from sim');
  dynamic results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print(parser.usage);
    print(e);
    exit(1);
  }
  final externalSigner = ExternalSigner();
  externalSigner.init(results['privateKeyId'], results['serialPort'],
      results['libPeripheryLocation']);
  String? activationKeyResult = externalSigner.computeActivationKey(
      results['keyId'], results['simSecret'], results['labelId']);
  print('activationKeyResult: $activationKeyResult');
}
