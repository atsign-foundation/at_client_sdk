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

    final myModelTestObject = MyModelTest(1, 'Alice', 'alice@atsign.com');
    final testKeyMaker = DefaultKeyMaker();
    testKeyMaker.atClient = mockAtClient;
    myModelTestObject.keyMaker = testKeyMaker;

    myModelTestObject.atClient = mockAtClient;
    AtCollectionUtil.atClient = mockAtClient;

    String modelId = myModelTestObject.id;
    
    AtKey sharedKey1 = testKeyMaker.createSharedKey(
      keyId: modelId,
      collectionName: collectionName,
      sharedWith: sharedWithAtsign1,
    );
    AtKey sharedKey2 = testKeyMaker.createSharedKey(
      keyId: modelId,
      collectionName: collectionName,
      sharedWith: sharedWithAtsign2,
    );
    
    test('test successfully saving an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      var result = await myModelTestObject.save(share: false);
      expect(result, true);
    });

    test('test unsuccessfully saving an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => false);

      var result = await myModelTestObject.save(share: false);
      expect(result, false);
    });

    test('test successfully saving and updating an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);

      var result = await myModelTestObject.save();
      expect(result, true);
    });

    test('test unsuccessfully saving and updating an object', () async {
      when(() => mockAtClient.put(
        any(that: PutSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => false);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);

      var result = await myModelTestObject.save();
      expect(result, false);
    });

    test('test retrieving shared with list of an object', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);

      var result = await myModelTestObject.getSharedWith();
      expect(result, [sharedWithAtsign1, sharedWithAtsign2]);
    });

    test('test successfully sharing an object with two atsigns', () async {
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      var result = await myModelTestObject.shareWith([sharedWithAtsign1, sharedWithAtsign2]);
      expect(result, true);
    });

    test('test unsuccessfully sharing an object with two atsigns', () async {
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign1)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => false);
      when(() => mockAtClient.put(
        any(that: PutSharedKeyMatcher(id: myModelTestObject.id, collectionName: collectionName,
            sharedWith: sharedWithAtsign2)), 
        any(that: PutDataMatcher()),))
          .thenAnswer((_) async => true);

      var result = await myModelTestObject.shareWith([sharedWithAtsign1, sharedWithAtsign2]);
      expect(result, false);
    });

    test('test successfully deleting an object', () async {
      when(() => mockAtClient.delete(
          any(that: DeleteSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName))
        ))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject.delete();
      expect(result, true);
    });

    test('test unsuccessfully deleting an object, self key not deleted', () async {
      when(() => mockAtClient.delete(
          any(that: DeleteSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName))
        ))
          .thenAnswer((_) async => false);

      var result = await myModelTestObject.delete();
      expect(result, false);
    });

    test('test unsuccessfully deleting an object, shared key not deleted', () async {
      when(() => mockAtClient.delete(
          any(that: DeleteSelfKeyMatcher(id: myModelTestObject.id, collectionName: collectionName))
        ))
          .thenAnswer((_) async => true);
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => false);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject.delete();
      expect(result, false);
    });

    test('test successfully unsharing an object', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject.unshare();
      expect(result, true);
    });

    test('test unsuccessfully unsharing an object', () async {
      when(() => mockAtClient.getAtKeys(
          regex: any(named: 'regex', that: GetAtKeysMatcher(collectionName: collectionName))
        ))
          .thenAnswer((_) async => [sharedKey1, sharedKey2]);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign1
          ))
        )).thenAnswer((_) async => false);
      when(() => mockAtClient.delete(
          any(that: DeleteSharedKeyMatcher(
            id: myModelTestObject.id, collectionName: collectionName, sharedWith: sharedWithAtsign2
          ))
        )).thenAnswer((_) async => true);

      var result = await myModelTestObject.unshare();
      expect(result, false);
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
