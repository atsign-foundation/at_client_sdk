import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_client/src/decryption_service/decryption.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {
  @override
  AtClientPreference getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }
}

class MockAtKeyDecryptionManager extends Mock
    implements AtKeyDecryptionManager {}

class MockAtKeyDecryption extends Mock implements AtKeyDecryption {}

void main() {
  group('A group of test for GetResponseTransformer', () {
    late MockAtClient mockAtClient;
    late MockAtKeyDecryptionManager mockDecryptionManager;
    late MockAtKeyDecryption mockDecryptionService;
    late GetResponseTransformer transformer;
    // late Tuple<AtKey, String> mockTuple;
    setUp(() {
      mockAtClient = MockAtClient();
      mockDecryptionManager = MockAtKeyDecryptionManager();
      mockDecryptionService = MockAtKeyDecryption();
      transformer = GetResponseTransformer(mockAtClient)
        ..decryptionManager = mockDecryptionManager;
      when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    });
    test('A test to validate new line character decoding', () async {
      var atKey = AtKey()
        ..key = 'key1'
        ..namespace = 'wavi'
        ..metadata = (Metadata()
          ..isPublic = true
          ..encoding = EncodingType.base64.toString());
      var value =
          'data:{"key":"public:key1.wavi@sitaram","data":"dmFsdWUKMQ==","metaData":{"createdBy":null,"updatedBy":null,"createdAt":"2022-07-26 17:46:50.247Z","updatedAt":"2022-07-26 17:50:12.680Z","availableAt":"2022-07-26 17:50:12.680Z","expiresAt":null,"refreshAt":null,"status":"active","version":0,"ttl":0,"ttb":0,"ttr":0,"ccd":null,"isBinary":false,"isEncrypted":false,"dataSignature":"l7LsM9t68Xd2NNHsMqFzh9aiUQO7NixEMpZ3KjduwnbpnLLesutglvFaabBTiX/BYAjatqC43tkk/ERUvvKP85GfYbsSjrVqMDE5dbwU1i13bWzL0TeUJUT3H7xVARjwrahHjvlw8u35rm/I2sPlqmxTtrFXZM89ByfdGJsrh4opd1cXfLf10W2wx7pIePfmeWCnam2stLVTSx4mWOV8sUdDcN5Mrh2FjVWGGewQOrktxGogn0KkENq/cmm41I5xZaMpVTVL/RvVUEJ8obgpmauN23puedq/HPBRUAoAL8LFnzji5PtVcZoAYvqZrjKKi4ac7ZOEy4xWXIr4ps9zSA==","sharedKeyEnc":null,"pubKeyCS":null,"encoding":"EncodingType.base64"}}';
      var expectedValue = 'value\n1';
      var atValue = await GetResponseTransformer(mockAtClient).transform(Tuple()
        ..one = atKey
        ..two = value);
      expect(atValue.value, expectedValue);
    });
    test('A test to verify response transformer for public key', () async {
      final keyName = 'phone';
      final atKey = AtKey()
        ..metadata = (Metadata()..isPublic = true)
        ..key = keyName;
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two =
            '{"data": "my_public_phone_number", "key": "public:$keyName@alice"}';
      var result = await transformer.transform(tuple);

      expect(result.value, equals('my_public_phone_number'));
    });
    test(
        'A test to verify response transformer for public key with encoding set',
        () async {
      final keyName = 'phone';
      final atKey = AtKey()
        ..metadata = (Metadata()..isPublic = true)
        ..key = keyName;
      var base64EncodedString = AtEncoderImpl()
          .encodeData("my_public_phone_number", EncodingType.base64);
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two =
            '{"data": "$base64EncodedString", "key": "public:$keyName@alice", "metaData": {"encoding": "base64"}}';
      var result = await transformer.transform(tuple);

      expect(result.value, equals('my_public_phone_number'));
    });

    test('A test to verify response transformer for public key binary data',
        () async {
      final keyName = 'phone';
      final atKey = AtKey()
        ..metadata = (Metadata()
          ..isPublic = true
          ..isBinary = true)
        ..key = keyName;
      final dataInBytes = "my_public_phone_number".codeUnits;
      var binaryData = Base2e15.encode(dataInBytes);
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two = '{"data": "$binaryData", "key": "public:$keyName@alice"}';
      var result = await transformer.transform(tuple);

      expect(result.value, equals(dataInBytes));
    });

    test('A test to verify response transformer for cached public key',
        () async {
      final keyName = 'phone';
      final atKey = AtKey()
        ..metadata = (Metadata()..isPublic = true)
        ..key = keyName;
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two =
            '{"data": "my_public_phone_number", "key": "cached:public:$keyName@alice"}';
      var result = await transformer.transform(tuple);

      expect(result.value, equals('my_public_phone_number'));
    });
    test(
        'A test to verify response transformer for encrypted data with isEncrypted set to true',
        () async {
      final keyName = 'phone';
      final atKey = AtKey()
        ..metadata = Metadata()
        ..key = keyName
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two =
            '{"data": "shared_phone_number", "key": "@bob:$keyName@alice","metaData": {"isEncrypted": true}}';
      when(() => mockDecryptionManager.get(atKey, '@alice'))
          .thenReturn(mockDecryptionService);
      when(() => mockDecryptionService.decrypt(atKey, "shared_phone_number"))
          .thenAnswer((_) async => 'decrypted_data');

      var result = await transformer.transform(tuple);

      expect(result.value, equals('decrypted_data'));
    });

    test(
        'A test to verify response transformer for encrypted data with isEncrypted set to false(for old data)',
        () async {
      final keyName = 'phone';
      final atKey = AtKey()
        ..metadata = Metadata()
        ..key = keyName
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two =
            '{"data": "shared_phone_number", "key": "@bob:$keyName@alice","metaData": {"isEncrypted": false}}';
      when(() => mockDecryptionManager.get(atKey, '@alice'))
          .thenReturn(mockDecryptionService);
      when(() => mockDecryptionService.decrypt(atKey, "shared_phone_number"))
          .thenAnswer((_) async => 'decrypted_data');

      var result = await transformer.transform(tuple);

      expect(result.value, equals('decrypted_data'));
    });

    test('A test to verify transform throws AtException on decryption failure',
        () async {
      final atKey = AtKey()
        ..metadata = Metadata()
        ..key = 'phone'
        ..sharedBy = '@alice'
        ..sharedWith = '@bob';
      final tuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two =
            '{"data": "shared_phone_number", "key": "@bob:phone@alice","metaData": {"isEncrypted": true}}';
      when(() => mockDecryptionManager.get(atKey, '@alice'))
          .thenReturn(mockDecryptionService);
      when(() => mockDecryptionService.decrypt(atKey, "shared_phone_number"))
          .thenThrow(AtException('Decryption failed'));

      expect(() async => await transformer.transform(tuple),
          throwsA(isA<AtException>()));
    });
  });
}
