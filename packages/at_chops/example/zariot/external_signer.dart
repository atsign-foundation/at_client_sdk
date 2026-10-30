import 'dart:io';
import 'package:dart_periphery/dart_periphery.dart';

import 'package:at_utils/at_logger.dart';

class ExternalSigner {
  late Serial _serialPort;
  late String _customLibraryLocation;
  late String _applicationId;
  late String _privateKeyId;
  late AtSignLogger _logger;
  ExternalSigner();

  void init(
      String privateKeyId, String serialPort, String libPeripheryLocation) {
    _customLibraryLocation = libPeripheryLocation;
    setCustomLibrary(_customLibraryLocation);
    _serialPort = Serial(serialPort, Baudrate.b115200);
    _applicationId = 'A0000005590010';
    _privateKeyId = privateKeyId;
    _logger = AtSignLogger('ExternalSigner');
  }

  String getPublicKey(String publicKeyId) {
    String? channelNumber;
    try {
      // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
      channelNumber = _openLogicalChannel();
      // Step 2. Select IOTsafe by application id
      _selectIOTSafeApplication(channelNumber!);
      return _readPublicKey(_serialPort, channelNumber, publicKeyId);
    } on Exception catch (e, trace) {
      _logger.severe('exception during signing ${e.toString()}');
      _logger.severe(trace);
      rethrow;
    } finally {
      if (channelNumber != null &&
          channelNumber.startsWith(RegExp(r'01|02|03'))) {
        _logger.finest('closing channel $channelNumber');
        _closeChannel(_serialPort, channelNumber);
      }
    }
  }

  String? sign(String dataHash) {
    String? channelNumber;
    try {
      // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
      channelNumber = _openLogicalChannel();
      _logger.info('opened logical channel #:$channelNumber');
      // Step 2. Select IOTsafe by application id
      _selectIOTSafeApplication(channelNumber!);

      _logger.info('selected IOTSafe application');

      // Step 3. Compute signature init
      _computeSignatureInit(channelNumber);

      // Step 4. Compute signature update
      _computeSignatureUpdate(channelNumber, dataHash.toUpperCase());
      _logger.info('signature computed. Retrieving the signature');
      // Step 5. Retrieve computed signature
      var signature = _retrieveSignature(channelNumber);
      return signature.toLowerCase();
    } on Exception catch (e, trace) {
      _logger.severe('exception during signing ${e.toString()}');
      _logger.severe(trace);
    } finally {
      if (channelNumber != null &&
          channelNumber.startsWith(RegExp(r'01|02|03'))) {
        _logger.finest('closing channel $channelNumber');
        _closeChannel(_serialPort, channelNumber);
      }
    }
    return null;
  }

  AsymmetricKeyPair? generateKeyPair(String privateKeyId) {
    String? channelNumber;
    try {
      // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
      channelNumber = _openLogicalChannel();
      _logger.info('opened logical channel #:$channelNumber');
      // Step 2. Select IOTsafe by application id
      _selectIOTSafeApplication(channelNumber!);

      _logger.info('selected IOTSafe application');

      // Step 3. Generate key pair
      _logger.info('generating key pair - private key id: $privateKeyId');
      bool isGenerateKeyPairSuccess =
          _generateKeyPair(privateKeyId, channelNumber);

      _logger.finest('isGenerateKeyPairSuccess $isGenerateKeyPairSuccess');
      if (!isGenerateKeyPairSuccess) {
        throw Exception('Generate key pair failure');
      }

      _serialPort.writeString(
          "AT+CSIM=10,\"8${channelNumber.substring(1)}C0000051\"\r\n");
      var generateKeyPairResult = _serialPort.read(256, 1000);
      var csimResult = _parseAtCsimResult(generateKeyPairResult.toString());
      String? newPrivateKeyId = csimResult.result?.substring(4, 10);
      String? newPublicKeyId = csimResult.result?.substring(14, 20);

      // These IDs may or  may not change. As per spec - "Note: This operation(generate key pair) may modify the key ID."
      _logger.finest('privateKeyId :$newPrivateKeyId');
      _logger.finest('publicKeyId :$newPublicKeyId');
      if (newPrivateKeyId == null || newPublicKeyId == null) {
        throw Exception(
            'privateKeyId or publicKeyId cannot be retrieved from generate keypair');
      }
      _privateKeyId = newPrivateKeyId;

      return AsymmetricKeyPair(newPrivateKeyId, newPublicKeyId);
    } on Exception catch (e, trace) {
      _logger.severe('exception during generate key pair ${e.toString()}');
      _logger.severe(trace);
    } finally {
      if (channelNumber != null &&
          channelNumber.startsWith(RegExp(r'01|02|03'))) {
        _logger.finest('closing channel $channelNumber');
        _closeChannel(_serialPort, channelNumber);
      }
    }
    return null;
  }

  String? computeActivationKey(String keyId, String simSecret, String labelId) {
    String? channelNumber;
    try {
      // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
      channelNumber = _openLogicalChannel();
      _logger.info('opened logical channel #:$channelNumber');
      // Step 2. Select IOTsafe by application id
      _selectIOTSafeApplication(channelNumber!);

      _logger.info('selected IOTSafe application');
      _computePRF(channelNumber, keyId, simSecret, labelId);
    } on Exception catch (e, trace) {
      _logger.severe('exception during generate key pair ${e.toString()}');
      _logger.severe(trace);
    } finally {
      if (channelNumber != null &&
          channelNumber.startsWith(RegExp(r'01|02|03'))) {
        _logger.finest('closing channel $channelNumber');
        _closeChannel(_serialPort, channelNumber);
      }
    }
    return null;
  }

  String _computePRF(
      String channelNumber, String keyId, String simSecret, String labelId) {
    // 48 - tag for compute PRF
    // 10 - activation key length
    _serialPort.writeString(
        "AT+CSIM=110, \"8${channelNumber.substring(1)}48000032$keyId$simSecret${labelId}D30110\"\r\n");
    var computePRFResult = _serialPort.read(256, 1000);
    _logger.finest('computePRFResult :$computePRFResult');
    bool isComputePRFSuccess =
        _parseResult(computePRFResult.toString(), ATCommand.computePRF);
    _logger.finest('isComputePRFSuccess $isComputePRFSuccess');
    _serialPort.writeString(
        "AT+CSIM=10, \"8${channelNumber.substring(1)}C0000010\"\r\n");
    var prfResult = _serialPort.read(256, 1000);
    _logger.finest('prfResult :$prfResult');
    return prfResult.toString();
  }

  String _readPublicKey(
      Serial serialPort, String channelNumber, String publicKeyId) {
    // INS - CD -read public key
    // P1 - 00
    // P2 - 00
    // 05 - length of command
    // 85 - public key id
    // 03 - data length
    _serialPort.writeString(
        "AT+CSIM=20, \"8${channelNumber.substring(1)}CD0000058503$publicKeyId\"\r\n");
    var readPublicKeyResult = _serialPort.read(256, 1000);
    _logger.finest('readPublicKeyResult :$readPublicKeyResult');
    bool isReadPublicKeyResultSuccess =
        _parseResult(readPublicKeyResult.toString(), ATCommand.readPublicKey);
    _logger
        .finest('isReadPublicKeyResultSuccess $isReadPublicKeyResultSuccess');
    if (!isReadPublicKeyResultSuccess) {
      throw Exception('Read public key failure');
    }
    _serialPort.writeString(
        "AT+CSIM=10, \"8${channelNumber.substring(1)}C0000047\"\r\n");
    var retrievePublicKeyResult = _serialPort.read(256, 1000);
    var csimResult = _parseAtCsimResult(retrievePublicKeyResult.toString());
    final publicKey = _parsePublicKeyResult(csimResult);
    if (publicKey == null) {
      throw Exception('cannot read public key');
    }
    _logger.finest('retrievePublicKeyResult :$publicKey');
    return publicKey;
  }

  String? _parsePublicKeyResult(AtCsimResult csimResult) {
    var commandResult = csimResult.result;
    _logger.finest(commandResult);
    if (commandResult != null && commandResult.startsWith('344549438641')) {
      commandResult = commandResult.substring(12, commandResult.length - 4);
      return commandResult;
    }
    return null;
  }

  String? _openLogicalChannel() {
    final openChannelResult = _getChannelNumber(_openChannel(_serialPort));
    var channelNumber = openChannelResult.channelNumber;
    _logger.finest('channelNumber:$channelNumber');
    if (openChannelResult.success) {
      return channelNumber;
    } else {
      throw Exception('open channel failed');
    }
  }

  String _openChannel(Serial serialPort) {
    _logger.finest('Opening a non-default logical channel');
    serialPort.writeString('AT+CSIM=10, "0070000000"\r\n');
    var event = serialPort.read(256, 1000);
    final result = event.toString();
    _logger.finest('openChannelResult: $result');
    return result;
  }

  void _selectIOTSafeApplication(String channelNumber) {
    _serialPort.writeString(
        "AT+CSIM=24, \"${channelNumber}A4040007$_applicationId\"\r\n");
    var selectApplicationResult = _serialPort.read(256, 1000);
    _logger.finest('selectApplicationResult :$selectApplicationResult');
    bool isValidApplication =
        _parseResult(selectApplicationResult.toString(), ATCommand.selectApp);
    _logger.finest('isValidApplication $isValidApplication');
  }

  bool _generateKeyPair(String privateKeyId, String channelNumber) {
    _serialPort.writeString(
        "AT+CSIM=20,\"8${channelNumber.substring(1)}B90000058403$privateKeyId\"\r\n");
    var generateKeyPairResult = '';
    while (true) {
      final readEvent = _serialPort.read(512, 1000);
      generateKeyPairResult += readEvent.toString();
      if (!readEvent.toString().contains('OK')) {
        _logger.finest('Got result: $generateKeyPairResult');
        sleep(Duration(seconds: 2));
        continue;
      }
      break;
    }
    _logger.info('generateKeyPair result :${generateKeyPairResult.toString()}');
    bool isGenerateKeyPairSuccess = _parseResult(
        generateKeyPairResult.toString(), ATCommand.generateKeyPair);
    return isGenerateKeyPairSuccess;
  }

  void _computeSignatureInit(String channelNumber) {
    // 2A - tag for compute signature init
    // 0F - length of command
    // 84 - private key tag
    // A1 - tag for mode of operation
    // 03 - value for mode of operation - external hash
    // 91 - tag for hash algorithm.
    // 01-  value for hash algorithm. sha256
    // 92 - tag for signature algorithm
    // 04 - value for signature algorithm. ecdsa
    _serialPort.writeString(
        "AT+CSIM=40,\"8${channelNumber.substring(1)}2A00010F8403${_privateKeyId}A1010391020001920104\"\r\n");
    var computeSignatureInitResult = _serialPort.read(256, 1000);
    _logger.info('computeSignatureInitResult :$computeSignatureInitResult');
    bool isComputeSignatureInitSuccess = _parseResult(
        computeSignatureInitResult.toString(), ATCommand.computeSignatureInit);
    _logger.finest(
        'isComputeSignatureInitSuccess: $isComputeSignatureInitSuccess');
  }

  void _computeSignatureUpdate(String channelNumber, String dataHash) {
    // 2B Tag for compute signature update
    // 80 - last incoming data_
    // 01 - session number
    // 22 - length of command
    // 9E - tag for hash
    // 20 -length of hash
    _logger.finest('computing signature from external hash');
    _serialPort.writeString(
        "AT+CSIM=78,\"8${channelNumber.substring(1)}2B8001229E20$dataHash\"\r\n");
    var computeSignatureUpdateResult = '';
    // command takes a while to execute. Read until OK is received.
    while (true) {
      final readEvent = _serialPort.read(512, 1000);
      computeSignatureUpdateResult += readEvent.toString();
      if (!readEvent.toString().contains('OK')) {
        _logger.finest('Got result: $computeSignatureUpdateResult');
        sleep(Duration(seconds: 2));
        continue;
      }
      break;
    }
    _logger.finest(
        'computeSignatureUpdateResult ${computeSignatureUpdateResult.toString()}');
    bool isComputeSignatureSuccess = _parseComputeSignatureUpdateResult(
        computeSignatureUpdateResult.toString());
    _logger.finest('isComputeSignatureSuccess :$isComputeSignatureSuccess');
  }

  String _retrieveSignature(String channelNumber) {
    _serialPort.writeString(
        "AT+CSIM=10,\"8${channelNumber.substring(1)}C0000043\"\r\n");
    var getSignatureResult = _serialPort.read(256, 1000);
    _logger.finest('getSignatureResult $getSignatureResult');
    final signatureData = _parseAtCsimResult(getSignatureResult.toString());
    _logger.info('signature: ${signatureData.result}');
    var signatureStr = '';
    if (signatureData.result != null &&
        signatureData.result!.startsWith('330040')) {
      // remove start tag, length and success code at the end.
      signatureStr =
          signatureData.result!.substring(6, signatureData.result!.length - 4);
    }
    return signatureStr.toLowerCase();
  }

  OpenChannelResult _getChannelNumber(String openChannelResult) {
    final atCsimResult = _parseAtCsimResult(openChannelResult);
    if (atCsimResult.result == null ||
        atCsimResult.result!.isEmpty ||
        atCsimResult.success == false) {
      _logger
          .finest('unexpected response from open channel: $openChannelResult');
      return OpenChannelResult(false, null);
    }
    if (atCsimResult.result!.startsWith(RegExp(r'01|02|03'))) {
      if (atCsimResult.result!.substring(2, 6) == '9000') {
        final channelNumber = atCsimResult.result!.substring(0, 2);
        _logger.finest('open channel successful');
        return OpenChannelResult(true, channelNumber);
      } else {
        _logger.finest(
            'open channel failed with non-success code: ${atCsimResult.result!.substring(2, 6)}');
      }
    } else {
      _logger.finest(
          'open channel failed.Returned channel number : ${atCsimResult.result!.substring(0, 2)}');
      return OpenChannelResult(false, atCsimResult.result!.substring(0, 2));
    }
    return OpenChannelResult(false, null);
  }

  bool _parseResult(String result, ATCommand atCommand) {
    final atCsimResult = _parseAtCsimResult(result);
    if (atCsimResult.result == null ||
        atCsimResult.result!.isEmpty ||
        atCsimResult.success == false) {
      _logger.finest(
          'unexpected response from ${atCommand.toString()}: $atCsimResult');
      return false;
    }
    if (atCommand == ATCommand.readPublicKey && atCsimResult.result == '6147') {
      return true;
    } else if (atCsimResult.result == '9000') {
      return true;
    } else if (atCommand == ATCommand.generateKeyPair &&
        atCsimResult.result == '6151') {
      return true;
    } else if (atCommand == ATCommand.computePRF &&
        atCsimResult.result == '6110') {
      return true;
    } else {
      _logger.finest(
          'failure code in ${atCommand.toString()} ${atCsimResult.result}');
    }
    return false;
  }

  bool _parseComputeSignatureUpdateResult(String result) {
    final atCsimResult = _parseAtCsimResult(result);
    if (atCsimResult.result == null ||
        atCsimResult.result!.isEmpty ||
        atCsimResult.success == false) {
      _logger.finest(
          'unexpected response from compute signature update: $atCsimResult');
      return false;
    }
    if (atCsimResult.result == '6143') {
      return true;
    }
    return false;
  }

  AtCsimResult _parseAtCsimResult(String result) {
    final atCsimResult = AtCsimResult();
    if (result.isEmpty || !result.contains(AtCsimResult.pattern)) {
      _logger.finest('unexpected response : $result');
      return atCsimResult;
    }
    int startIndex = result.indexOf(AtCsimResult.pattern);
    int bytesStartIndex = startIndex + AtCsimResult.pattern.length;
    int bytesEndindex = startIndex + result.substring(startIndex).indexOf(',"');
    String bytesToRead = result.substring(bytesStartIndex, bytesEndindex);
    atCsimResult.bytesToRead = int.parse(bytesToRead);
    atCsimResult.result = result.substring(
        bytesEndindex + 2, bytesEndindex + 2 + atCsimResult.bytesToRead);
    _logger.finest('atCsimResult.result ${atCsimResult.result}');
    atCsimResult.success = true;
    return atCsimResult;
  }

  void _closeChannel(Serial port, String channelNumber) {
    _logger.finest('closing channel : $channelNumber');
    final channelCloseCommand = 'AT+CSIM=10, "007080${channelNumber}00"\r\n';
    _logger.finest('channelCloseCommand: $channelCloseCommand');
    port.writeString(channelCloseCommand);
    final result = port.read(256, 1000);
    _logger.finest('close channel result: ${result.toString()}');
  }

  void clear() {
    _serialPort.setVMIN(0);
    _serialPort.dispose();
  }
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

enum ATCommand {
  openChannel,
  selectApp,
  computeSignatureInit,
  computeSignatureUpdate,
  readPublicKey,
  generateKeyPair,
  computePRF
}

class AsymmetricKeyPair {
  String privateKeyId;
  String publicKeyId;

  AsymmetricKeyPair(this.privateKeyId, this.publicKeyId);
}
