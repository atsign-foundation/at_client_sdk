import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/test_crypto_provider.dart';

void main() {
  group('A group of test for GetResponseTransformer', () {
    late MockAtClient mockAtClient;
    late MockAtChops mockAtChops;
    late MockCryptoRegistry mockCryptoRegistry;
    late GetResponseTransformer transformer;
    setUp(() {
      mockAtClient = MockAtClient();
      mockAtChops = MockAtChops();
      mockCryptoRegistry = MockCryptoRegistry(mockAtClient);
      transformer = GetResponseTransformer(mockAtClient);
      when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => mockAtClient.atChops).thenReturn(mockAtChops);
      when(() => mockAtClient.cryptoRegistry).thenReturn(mockCryptoRegistry);
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
            '{"data": "abcshared_phone_number", "key": "@bob:$keyName@alice","metaData": {"isEncrypted": true}}';

      when(() => mockCryptoRegistry.lookup('legacy',
          operation: any(named: 'operation'))).thenReturn(CipherProvider());

      var result = await transformer.transform(tuple);

      expect(result.value, equals('shared_phone_number'));
    });

    test(
        'A test to verify explicit isEncrypted=false returns the raw value without attempting decryption',
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
            '{"data": "abcdecrypted_data", "key": "@bob:$keyName@alice","metaData": {"isEncrypted": false}}';

      // Even if a provider WOULD strip the value, explicit isEncrypted=false
      // means the value was deliberately stored unencrypted: return it as-is.
      when(() => mockCryptoRegistry.lookup('legacy',
          operation: any(named: 'operation'))).thenReturn(CipherProvider());

      var result = await transformer.transform(tuple);

      expect(result.value, equals('abcdecrypted_data'));
    });

    test(
        'A test to verify isEncrypted absent still decrypts via the legacy fallback (for old data)',
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
            '{"data": "abcdecrypted_data", "key": "@bob:$keyName@alice","metaData": {"ttl": 0}}';

      when(() => mockCryptoRegistry.lookup('legacy',
          operation: any(named: 'operation'))).thenReturn(CipherProvider());

      var result = await transformer.transform(tuple);

      expect(result.value, equals('decrypted_data'));
    });

    test(
        'A test to verify isEncrypted absent with plain data falls back to the raw value (for old data)',
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
            '{"data": "plain_phone_number", "key": "@bob:$keyName@alice","metaData": {"ttl": 0}}';

      when(() => mockCryptoRegistry.lookup('legacy',
              operation: any(named: 'operation')))
          .thenReturn(FormatExceptionProvider());

      var result = await transformer.transform(tuple);

      expect(result.value, equals('plain_phone_number'));
    });

    test(
        'A test to verify transform throws AtException on crypto provider lookup failure',
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
      when(() => mockCryptoRegistry.lookup(any(),
              operation: any(named: 'operation')))
          .thenThrow(CryptoProviderNotRegistered('error'));

      expect(() async => await transformer.transform(tuple),
          throwsA(isA<AtException>()));
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

      when(() => mockCryptoRegistry.lookup(any(),
          operation: any(named: 'operation'))).thenReturn(ErrorProvider());
      expect(() async => await transformer.transform(tuple),
          throwsA(isA<AtException>()));
    });
  });
}
