import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}
class FakeAtKey extends Fake implements AtKey {}


String collectionName = 'my_collection_test';
String sharedWithAtsign1 = '@colin';
String sharedWithAtsign2 = '@kevin';

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
  });

  group('A group of saving/sharing/deleting/unsharing an object tests', () {
    var mockAtClient = MockAtClient();

    final myModelTestObject1 = MyModelTest(1, 'Alice', 'alice@atsign.com');
    final myModelTestObject2 = MyModelTest(2, 'Bob', 'bob@atsign.com');

    final testKeyMaker = DefaultKeyMaker();
    testKeyMaker.atClient = mockAtClient;
    myModelTestObject1.keyMaker = testKeyMaker;
    myModelTestObject2.keyMaker = testKeyMaker;

    myModelTestObject1.atClient = mockAtClient;
    myModelTestObject2.atClient = mockAtClient;

    AtCollectionModel.atCollectionGetterRepository.atClient = mockAtClient;
    AtCollectionModel.atCollectionGetterRepository.keyMaker = testKeyMaker;

    AtCollectionUtil.atClient = mockAtClient;

    String object1ModelId = myModelTestObject1.id;
    AtKey object1SelfKey = testKeyMaker.createSelfKey(
      keyId: object1ModelId,
      collectionName: collectionName,
    );
    AtKey object1SharedKey1 = testKeyMaker.createSharedKey(
      keyId: object1ModelId,
      collectionName: collectionName,
      sharedWith: sharedWithAtsign1,
    );
    AtKey object1SharedKey2 = testKeyMaker.createSharedKey(
      keyId: object1ModelId,
      collectionName: collectionName,
      sharedWith: sharedWithAtsign2,
    );

    String object2ModelId = myModelTestObject2.id;
    AtKey object2SelfKey = testKeyMaker.createSelfKey(
      keyId: object2ModelId,
      collectionName: collectionName,
    );
    AtKey object2SharedKey1 = testKeyMaker.createSharedKey(
      keyId: object2ModelId,
      collectionName: collectionName,
      sharedWith: sharedWithAtsign1,
    );
    AtKey object2SharedKey2 = testKeyMaker.createSharedKey(
      keyId: object2ModelId,
      collectionName: collectionName,
      sharedWith: sharedWithAtsign2,
    );

    test('test getting an object by id', () async {
      when(() => mockAtClient.get(
          any(that: GetAtKeyMatcher(keyId: object1ModelId, collectionName: collectionName))
        ))
        .thenAnswer((_) async {
          var atValue = AtValue();
          atValue.value = jsonEncode(myModelTestObject1.toJson());
          return atValue;
        });

      var result = (await MyModelTest.getById(object1ModelId));
      expect(result, myModelTestObject1);
    });

    test('test getting all objects of a type', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SelfKey, object2SelfKey]);

      when(() => mockAtClient.get(
          any(that: GetAtKeyMatcher(keyId: object1ModelId, collectionName: collectionName))
        ))
        .thenAnswer((_) async {
          var atValue = AtValue();
          atValue.value = jsonEncode(myModelTestObject1.toJson());
          return atValue;
        });

      when(() => mockAtClient.get(
          any(that: GetAtKeyMatcher(keyId: object2ModelId, collectionName: collectionName))
        ))
        .thenAnswer((_) async {
          var atValue = AtValue();
          atValue.value = jsonEncode(myModelTestObject2.toJson());
          return atValue;
        });

      var result = (await MyModelTest.getAllData());
      expect(result, [myModelTestObject1, myModelTestObject2]);
    });
    
    test('test successfully saving an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      var result = await myModelTestObject1.save(share: false);
      expect(result, true);
    });

    test('test unsuccessfully saving an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => false);

      var result = await myModelTestObject1.save(share: false);
      expect(result, false);
    });

    test('test successfully saving and updating an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var result = await myModelTestObject1.save();
      expect(result, true);
    });

    test('test unsuccessfully saving and updating an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => false);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var result = await myModelTestObject1.save();
      expect(result, false);
    });

    test('test retrieving shared with list of an object', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var result = await myModelTestObject1.getSharedWith();
      expect(result, [sharedWithAtsign1, sharedWithAtsign2]);
    });

    test('test successfully sharing an object with two atsigns', () async {
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      var result = await myModelTestObject1.shareWith([sharedWithAtsign1, sharedWithAtsign2]);
      expect(result, true);
    });

    test('test unsuccessfully sharing an object with two atsigns', () async {
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => false);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      var result = await myModelTestObject1.shareWith([sharedWithAtsign1, sharedWithAtsign2]);
      expect(result, false);
    });

    test('test successfully deleting an object', () async {
      when(() => mockAtClient.delete(
          any(that: DeleteSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName))
        ))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject1.delete();
      expect(result, true);
    });

    test('test unsuccessfully deleting an object, self key not deleted', () async {
      when(() => mockAtClient.delete(
          any(that: DeleteSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName))
        ))
          .thenAnswer((_) async => false);

      var result = await myModelTestObject1.delete();
      expect(result, false);
    });

    test('test unsuccessfully deleting an object, shared key not deleted', () async {
      when(() => mockAtClient.delete(
          any(that: DeleteSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName))
        ))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => false);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject1.delete();
      expect(result, false);
    });

    test('test successfully unsharing an object', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject1.unshare();
      expect(result, true);
    });

    test('test unsuccessfully unsharing an object', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => false);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject1.unshare();
      expect(result, false);
    });

    test('testing series of operations on an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject1.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject1.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var savingTheObject = await myModelTestObject1.save(share: false);
      expect(savingTheObject, true);

      var sharingTheObject = await myModelTestObject1.shareWith([sharedWithAtsign1, sharedWithAtsign2]);
      expect(sharingTheObject, true);

      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var unshareTheObject = await myModelTestObject1.unshare(atSigns: [sharedWithAtsign1]);
      expect(unshareTheObject, true);


      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [object1SharedKey2]);

      var currentlySharedWith = await myModelTestObject1.getSharedWith();
      expect(currentlySharedWith, [sharedWithAtsign2]);

    });
  });
}

class PutSelfKeyMatcher extends Matcher {
  String id, collectionName;

  PutSelfKeyMatcher({required this.id, required this.collectionName});

  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the self key for put method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey && atKey.key!.contains(id) && atKey.key!.contains(collectionName)) {
      print("matched atKey: $atKey");
      return true;
    }
    return false;
  }
}

class PutSharedKeyMatcher extends Matcher {
  String id, collectionName, sharedWith;

  PutSharedKeyMatcher({required this.id, required this.collectionName, required this.sharedWith});

  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the shared key for put method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey && atKey.key!.contains(id) && atKey.key!.contains(collectionName)
        && (atKey.sharedWith == sharedWith)) {
      return true;
    }
    return false;
  }
}

class PutDataMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the data for put method');

  @override
  bool matches(data, Map matchState) {
    if (data is String) {
      return true;
    }
    return false;
  }
}

class GetAtKeysMatcher extends Matcher {
  String collectionName;

  GetAtKeysMatcher({required this.collectionName});

  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the regex for get method');

  @override
  bool matches(data, Map matchState) {
    if (data is String && data.contains(collectionName)) {
      return true;
    }
    return false;
  }
}

class GetAtKeyMatcher extends Matcher {
  String keyId, collectionName;

  GetAtKeyMatcher({required this.keyId, required this.collectionName});

  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the regex for get method');

  @override
  bool matches(data, Map matchState) {
    if (data is AtKey && data.key!.contains(keyId) && data.key!.contains(collectionName)) {
      return true;
    }
    return false;
  }
}

class DeleteSelfKeyMatcher extends Matcher {
  String id, collectionName;

  DeleteSelfKeyMatcher({required this.id, required this.collectionName});

  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the self key for delete method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey && atKey.key!.contains(id) && atKey.key!.contains(collectionName)) {
      return true;
    }
    return false;
  }
}

class DeleteSharedKeyMatcher extends Matcher {
  String id, collectionName, sharedWith;

  DeleteSharedKeyMatcher({required this.id, required this.collectionName, required this.sharedWith});

  @override
  Description describe(Description description) =>
      description.add('A custom matcher to match the shared key for delete method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey && atKey.key!.contains(id) && atKey.key!.contains(collectionName)
        && (atKey.sharedWith == sharedWith)) {
      return true;
    }
    return false;
  }
}

class MyModelTest extends AtCollectionModel {
  int number;
  String name;
  String email;

  MyModelTest(this.number, this.name, this.email)
  : super(
          collectionName: collectionName,
        );

  static Future<List<MyModelTest>> getAllData() async {
    return (await AtCollectionModel.getAll<MyModelTest>());
  }

  static Future<MyModelTest> getById(String keyId) async {
    return (await AtCollectionModel.load<MyModelTest>(keyId));
  }

  @override
  MyModelTest fromJson(String jsonEncodedString)
  { 
    var json = jsonDecode(jsonEncodedString);
    var newMyModel = MyModelTest(int.parse(json['number']), json['name'], json['email']);
    newMyModel.id = json['id'];
    return newMyModel;
  }

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyModelTest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          number == other.number &&
          email == other.email;
          
  @override
  int get hashCode => super.hashCode;

  @override
  String toString() {
    return 'id: $id, name: $name, number: $number, email: $email';
  }
}
