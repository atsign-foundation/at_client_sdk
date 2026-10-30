import 'dart:io';

import 'package:dart_periphery/dart_periphery.dart';

// Sample code for checking signing and verify commands on the sim card for a precomputed hash
void main() {
  setCustomLibrary('/usr/lib/arm-linux-gnueabihf/libperiphery_arm.so');
  print('Connecting to serial port');
  var serialPort = Serial('/dev/ttyS0', Baudrate.b115200);
  const String applicationId = 'A0000005590010';
  var privateKeyId = '303036';
  var publicKeyId = '303037';
  // hard code hash of 'hello world' string for testing.
  const String dataHash =
      'B94D27B9934D3E08A52E52D7DA7DABFAC484EFE37A5380EE9088F7ACE2EFCDE9';
  String? channelNumber;
  try {
    print('Serial interface info: ${serialPort.getSerialInfo()}');
    // final openChannelResult = '+CSIM: 6,\"019000\"\nabcd';
    // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
    final openChannelResult = _getChannelNumber(_openChannel(serialPort));
    channelNumber = openChannelResult.channelNumber;
    print('channelNumber:$channelNumber');
    if (openChannelResult.success) {
      print('continue');
    } else {
      print('open channel failed');
      exit(0);
    }
    // Step 2. Select IOTsafe by application id
    serialPort.writeString(
        "AT+CSIM=24, \"${channelNumber}A4040007$applicationId\"\r\n");
    var selectApplicationResult = serialPort.read(256, 1000);
    print('selectApplicationResult :$selectApplicationResult');
    bool isValidApplication =
        _parseSelectApplicationResult(selectApplicationResult.toString());
    print('isValidApplication $isValidApplication');

    // Step 3. Generate random challenge to check whether application id is selected correctly
    serialPort.writeString(
        "AT+CSIM=10,\"8${channelNumber!.substring(1)}84000000\"\r\n");
    final generateChallengeResult = serialPort.read(600, 1000);
    print('generateChallengeResult: ${generateChallengeResult.toString()}');
    bool isChallengeSuccess =
        _parseGenerateChallengeResult(generateChallengeResult.toString());
    print('generate challenge result: $isChallengeSuccess');

    // Step 4. Generate key pair.
    // This step will overcome any manual errors in loading key pair on the sim.
    // Also ensures security since new keypair will be used.
    // This operation may modify key ID.
    serialPort.writeString(
        "AT+CSIM=20,\"8${channelNumber.substring(1)}B90000058403$privateKeyId\"\r\n");
    var generateKeyPairResult = '';
    // Generate key pair commands takes a while to execute. Read until OK is received.
    while (true) {
      final readEvent = serialPort.read(512, 1000);
      generateKeyPairResult += readEvent.toString();
      if (!readEvent.toString().contains('OK')) {
        print('Got result: $generateKeyPairResult');
        sleep(Duration(seconds: 2));
        continue;
      }
      print('generateKeyPairResult_1 $generateKeyPairResult');
      break;
    }
    print('generateKeyPairResult ${generateKeyPairResult.toString()}');
    final isGenerateKeyPairSuccess =
        _parseGenerateKeyPairResult(generateKeyPairResult.toString());
    print('isGenerateKeyPairSuccess $isGenerateKeyPairSuccess');

    // Step 6.1 Parse generate key pair result and check if key id is modified.
    serialPort.writeString(
        "AT+CSIM=10,\"8${channelNumber.substring(1)}C0000051\"\r\n");
    final getKeyPairDataResult = serialPort.read(256, 1000);
    print('getFileDataResult $getKeyPairDataResult');
    final getKeyPairResult =
        _parseGetFileDataResult(getKeyPairDataResult.toString());
    print('getKeyPairResult ${getKeyPairResult.result}');
    privateKeyId = getKeyPairResult.result!.substring(4, 10);
    publicKeyId = getKeyPairResult.result!.substring(14, 20);
    print('generated privateKeyId: $privateKeyId');
    print('generated publicKeyId: $publicKeyId');

    // Step 5. Compute signature init
    // 2A - tag for compute signature init
    // 0F - length of command
    // 84 - private key tag
    // A1 - tag for mode of operation
    // 03 - value for mode of operation - external hash
    // 91 - tag for hash algorithm.
    // 01-  value for hash algorithm. sha256
    // 92 - tag for signature algorithm
    // 04 - value for signature algorithm. ecdsa
    serialPort.writeString(
        "AT+CSIM=40,\"8${channelNumber.substring(1)}2A00010F8403${privateKeyId}A1010391020001920104\"\r\n");
    var computeSignatureInitResult = serialPort.read(256, 1000);
    print('computeSignatureInitResult :$computeSignatureInitResult');
    bool isComputeSignatureInitSuccess =
        _parseComputeSignatureInitResult(computeSignatureInitResult.toString());
    print('generate challenge result: $isComputeSignatureInitSuccess');

    // Step 6. Compute signature update
    // 2B Tag for compute signature update
    // 80 - last incoming data
    // 01 - session number
    // 22 - length of command
    // 9E - tag for hash
    // 20 -length of hash
    serialPort.writeString(
        "AT+CSIM=78,\"8${channelNumber.substring(1)}2B8001229E20$dataHash\"\r\n");
    var computeSignatureUpdateResult = '';
    // command takes a while to execute. Read until OK is received.
    while (true) {
      final readEvent = serialPort.read(512, 1000);
      computeSignatureUpdateResult += readEvent.toString();
      if (!readEvent.toString().contains('OK')) {
        print('Got result: $computeSignatureUpdateResult');
        sleep(Duration(seconds: 2));
        continue;
      }
      // print('computeSignatureUpdateResult $computeSignatureUpdateResult');
      break;
    }
    print(
        'computeSignatureUpdateResult ${computeSignatureUpdateResult.toString()}');
    bool isComputeSignatureSuccess = _parseComputeSignatureUpdateResult(
        computeSignatureUpdateResult.toString());
    print('isComputeSignatureSuccess :$isComputeSignatureSuccess');

    // Step 7. Retrieve the computed signature
    serialPort.writeString(
        "AT+CSIM=10,\"8${channelNumber.substring(1)}C0000043\"\r\n");
    var getSignatureResult = serialPort.read(256, 1000);
    print('getSignatureResult $getSignatureResult');
    final signatureData =
        _parseGetFileDataResult(getSignatureResult.toString());
    print('signature: ${signatureData.result}');
    var signatureStr = '';
    if (signatureData.result != null &&
        signatureData.result!.startsWith('330040')) {
      // remove start tag, length and success code at the end.
      signatureStr =
          signatureData.result!.substring(6, signatureData.result!.length - 4);
    }
    print('signatureStr: $signatureStr');

    // Step 8. Verify signature init
    // 2C - tag for signature init
    // 02 - session number. Use a different session number for verify
    // 85 - tag of public key id
    // A1 - tag for mode of operation
    // 03 - value for mode of operation - external hash
    // 91 - tag for hash algorithm.
    // 01-  value for hash algorithm. sha256
    // 92 - tag for signature algorithm
    // 04 - value for signature algorithm. ecdsa
    serialPort.writeString(
        "AT+CSIM=40,\"8${channelNumber.substring(1)}2C00020F8503${publicKeyId}A1010391020001920104\"\r\n");
    var verifySignatureInitResult = serialPort.read(256, 1000);
    print('verifySignatureInitResult $verifySignatureInitResult');
    bool isVerifyInitSuccess =
        _parseVerifyResult(verifySignatureInitResult.toString());
    print('isVerifyInitSuccess $isVerifyInitSuccess');

    // Step 9. Verify signature update
    // 2D - tag for signature update
    // 02 - session number.
    // 9E - tag for passing hash value
    // 20 - length of hash
    // 33 - tag for signature
    // 0040 - length of signature
    serialPort.writeString(
        "AT+CSIM=212,\"8${channelNumber.substring(1)}2D8002659E20${dataHash}330040$signatureStr\"\r\n");
    var verifySignatureResult = serialPort.read(256, 1000);
    print('verifySignatureResult $verifySignatureResult');
    var verifyResult = '';
    while (true) {
      final readEvent = serialPort.read(256, 1000);
      verifyResult += readEvent.toString();
      if (!readEvent.toString().contains('OK')) {
        print('Got result: $verifyResult');
        sleep(Duration(seconds: 2));
        continue;
      }
      // print('computeSignatureUpdateResult $computeSignatureUpdateResult');
      break;
    }
    print('verifyResult: $verifyResult');
    bool isVerifyUpdateSuccess = _parseVerifyResult(verifyResult);
    print('isVerifyUpdateSuccess $isVerifyUpdateSuccess');
  } finally {
    if (channelNumber != null &&
        channelNumber.startsWith(RegExp(r'01|02|03'))) {
      print('closing compute signature session');
      _closeSession(serialPort, channelNumber.substring(1), '2A', '01');
      print('closing verify session');
      _closeSession(serialPort, channelNumber.substring(1), '2C', '02');
      print('closing channel $channelNumber');
      _closeChannel(serialPort, channelNumber);
    }
    serialPort.setVMIN(0);
    serialPort.dispose();
  }
}

bool _parseComputeSignatureUpdateResult(String result) {
  final atCsimResult = _parseAtCsimResult(result);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print('unexpected response from compute signature update: $atCsimResult');
    return false;
  }
  if (atCsimResult.result == '6143') {
    return true;
  }
  return false;
}

bool _parseVerifyResult(String result) {
  final atCsimResult = _parseAtCsimResult(result);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print('unexpected response from verify signature : $atCsimResult');
    return false;
  }
  if (atCsimResult.result == '9000') {
    return true;
  } else {
    print('failure code in verify signature: ${atCsimResult.result}');
  }
  return false;
}

bool _parseComputeSignatureInitResult(String result) {
  final atCsimResult = _parseAtCsimResult(result);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print('unexpected response from compute signature init: $atCsimResult');
    return false;
  }
  if (atCsimResult.result == '9000') {
    return true;
  } else {
    print('failure code in compute signature init ${atCsimResult.result}');
  }
  return false;
}

bool _parseGenerateKeyPairResult(String generateKeyPairResult) {
  final atCsimResult = _parseAtCsimResult(generateKeyPairResult);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    return false;
  }
  if (atCsimResult.result == '6151') {
    return true;
  }
  return false;
}

AtCsimResult _parseGetFileDataResult(String getFileDataResult) {
  final atCsimResult = _parseAtCsimResult(getFileDataResult);
  return atCsimResult;
}

bool _parseGenerateChallengeResult(String generateChallengeResult) {
  final atCsimResult = _parseAtCsimResult(generateChallengeResult);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    return false;
  }
  if (atCsimResult.result!.length == atCsimResult.bytesToRead) {
    return true;
  }
  return false;
}

bool _parseSelectApplicationResult(String selectApplicationResult) {
  final atCsimResult = _parseAtCsimResult(selectApplicationResult);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print(
        'unexpected response from select application: $selectApplicationResult');
    return false;
  }
  if (atCsimResult.result == '9000') {
    return true;
  } else {
    print('failure code in select application ${atCsimResult.result}');
  }
  return false;
}

String _openChannel(Serial serialPort) {
  print('Opening a non-default logical channel');
  serialPort.writeString('AT+CSIM=10, "0070000000"\r\n');
  var event = serialPort.read(256, 1000);
  final result = event.toString();
  print('openChannelResult: $result');
  return result;
}

void _closeSession(
    Serial port, String channelNumber, String tag, String sessionNumber) {
  print('closing session');
  final sessionCloseCommand =
      'AT+CSIM=10, "8$channelNumber${tag}01${sessionNumber}00"\r\n';
  print('close session command: $sessionCloseCommand');
  port.writeString(sessionCloseCommand);
  final result = port.read(256, 1000);
  print('close session result: ${result.toString()}');
}

void _closeChannel(Serial port, String channelNumber) {
  print('closing channel : $channelNumber');
  final channelCloseCommand = 'AT+CSIM=10, "007080${channelNumber}00"\r\n';
  print('channelCloseCommand: $channelCloseCommand');
  port.writeString(channelCloseCommand);
  final result = port.read(256, 1000);
  print('close channel result: ${result.toString()}');
}

OpenChannelResult _getChannelNumber(String openChannelResult) {
  final atCsimResult = _parseAtCsimResult(openChannelResult);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print('unexpected response from open channel: $openChannelResult');
    return OpenChannelResult(false, null);
  }
  if (atCsimResult.result!.startsWith(RegExp(r'01|02|03'))) {
    if (atCsimResult.result!.substring(2, 6) == '9000') {
      final channelNumber = atCsimResult.result!.substring(0, 2);
      print('open channel successful');
      return OpenChannelResult(true, channelNumber);
    } else {
      print(
          'open channel failed with non-success code: ${atCsimResult.result!.substring(2, 6)}');
    }
  } else {
    print(
        'open channel failed.Returned channel number : ${atCsimResult.result!.substring(0, 2)}');
    return OpenChannelResult(false, atCsimResult.result!.substring(0, 2));
  }
  return OpenChannelResult(false, null);
}

AtCsimResult _parseAtCsimResult(String result) {
  final atCsimResult = AtCsimResult();
  if (result.isEmpty || !result.contains(AtCsimResult.pattern)) {
    print('unexpected response : $result');
    return atCsimResult;
  }
  int startIndex = result.indexOf(AtCsimResult.pattern);
  int bytesStartIndex = startIndex + AtCsimResult.pattern.length;
  int bytesEndindex = startIndex + result.substring(startIndex).indexOf(',"');
  String bytesToRead = result.substring(bytesStartIndex, bytesEndindex);
  atCsimResult.bytesToRead = int.parse(bytesToRead);
  atCsimResult.result = result.substring(
      bytesEndindex + 2, bytesEndindex + 2 + atCsimResult.bytesToRead);
  print('atCsimResult.result ${atCsimResult.result}');
  atCsimResult.success = true;
  return atCsimResult;
}

class OpenChannelResult {
  bool success;
  String? channelNumber;

  OpenChannelResult(this.success, this.channelNumber);
}

class AtCsimResult {
  String? result;
  late int bytesToRead;
  bool success = false;
  static const String pattern = '+CSIM: ';

  @override
  String toString() {
    return 'AtCsimResult{result: $result, bytesToRead: $bytesToRead, success: $success}';
  }
}
