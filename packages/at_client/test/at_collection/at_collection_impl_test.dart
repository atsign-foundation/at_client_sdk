import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

String collectionName = 'my_collection_test';

void main() {
  group('A group of saving an object tests', () {
    var atClient = MockAtClient();

    final myModelTestObject = MyModelTest(1, 'Alice', 'alice@atsign.com');

    myModelTestObject.atClient = atClient;
    AtCollectionUtil.atClient = atClient;

    String keyWithCollectionName = '${myModelTestObject.id}.$collectionName';

    AtKey selfKey = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
    );
    AtKey sharedKey1 = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
      sharedWith: '@colin',
    );
    AtKey sharedKey2 = AtCollectionUtil.formAtKey(
      key: keyWithCollectionName,
      sharedWith: '@kevin',
    );
    
    test('test successfully only saving an object', () async {
      when(() => atClient.put(selfKey, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => true);

      var result = await myModelTestObject.save(share: false);
      expect(result, true);
    });

    test('test unsuccessfully only saving an object', () async {
      when(() => atClient.put(selfKey, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => false);

      var result = await myModelTestObject.save(share: false);
      expect(result, false);
    });

    test('test successfully saving and updating an object', () async {
      when(() => atClient.put(selfKey, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => true);
      when(() => atClient.put(sharedKey1, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => true);
      when(() => atClient.put(sharedKey2, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => true);
      when(() => atClient.getAtKeys(regex: keyWithCollectionName))
          .thenAnswer((invocation) async => [sharedKey1, sharedKey2]);

      var result = await myModelTestObject.save();
      expect(result, true);
    });

    test('test unsuccessfully saving and updating an object', () async {
      when(() => atClient.put(selfKey, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => true);
      when(() => atClient.put(sharedKey1, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => false);
      when(() => atClient.put(sharedKey2, jsonEncode(myModelTestObject.toJson())))
          .thenAnswer((invocation) async => true);
      when(() => atClient.getAtKeys(regex: keyWithCollectionName))
          .thenAnswer((invocation) async => [sharedKey1, sharedKey2]);

      var result = await myModelTestObject.save();
      expect(result, false);
    });

  });
}

class MyModelTest extends AtCollectionImpl {
  int number;
  String name;
  String email;

  MyModelTest(this.number, this.name, this.email)
  : super(
          collectionName: collectionName,
        );

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['id'] = id;
    data['name'] = name;
    data['number'] = number.toString();
    data['email'] = email;
    data['collectionName'] = AtCollectionModelSpec.collectionName;
    return data;
  }
}
