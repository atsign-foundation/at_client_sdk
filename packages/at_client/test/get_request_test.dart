import 'package:at_client/at_client.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {
  @override
  AtClientPreference getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }
}

void main() {
  AtClient mockAtClient = MockAtClient();
  group('A group of test to validate decoding of public data', () {
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
  });
}
