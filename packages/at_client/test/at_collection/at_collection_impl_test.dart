import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/at_collection_repository.dart';
import 'package:at_client/at_collection/collection_methods_impl.dart';
import 'package:at_client/at_collection/model/default_key_maker.dart';
import 'package:at_client/src/util/at_collection_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class FakeAtKey extends Fake implements AtKey {}

class MockAtCLientManager extends Mock implements AtClientManager {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
  });

  group('A group of saving/sharing/deleting/unsharing an object tests', () {
    var mockAtClient = MockAtClient();

    final testKeyMaker = DefaultKeyMaker();
    MockAtCLientManager mockAtCLientManager = MockAtCLientManager();
    testKeyMaker.atClientManager = mockAtCLientManager;

    AtCollectionRepository atCollectionRepository = AtCollectionRepository(
      keyMaker: testKeyMaker,
    );

    when(() => mockAtCLientManager.atClient).thenAnswer((_) => mockAtClient);

    atCollectionRepository.atClientManager = mockAtCLientManager;
    atCollectionRepository.keyMaker = testKeyMaker;

    AtCollectionModel.atCollectionRepository = atCollectionRepository;

    AtCollectionModel.atCollectionRepository.atClientManager =
        mockAtCLientManager;
    AtCollectionModel.atCollectionRepository.keyMaker = testKeyMaker;
    AtCollectionModel.keyMaker = testKeyMaker;

    final myModelTestObject1 = MyModelTest.from(1, 'Alice', 'alice@atsign.com');
    final myModelTestObject2 = MyModelTest.from(2, 'Bob', 'bob@atsign.com');

    myModelTestObject1.collectionMethodImpl.keyMaker = testKeyMaker;
    myModelTestObject2.collectionMethodImpl.keyMaker = testKeyMaker;
    myModelTestObject1.collectionMethodImpl.atClientManager =
        mockAtCLientManager;
    myModelTestObject2.collectionMethodImpl.atClientManager =
        mockAtCLientManager;

    String collectionName = "MyModelTest".toLowerCase();
    String sharedWithAtsign1 = '@colin';
    String sharedWithAtsign2 = '@kevin';

    myModelTestObject1.atClientManager = mockAtCLientManager;
    myModelTestObject2.atClientManager = mockAtCLientManager;

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

    test('test getting an object by id using AtCollectionModel', () async {
      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object1ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject1.toJson());
        return atValue;
      });

      var result = await AtCollectionModel.getById<MyModelTest>(object1ModelId,
          collectionName: 'mymodeltest',
          collectionModelFactory: MyModelTestFactory());
      expect(result, myModelTestObject1);
    });

    test('test getting an object by id using MyModelTest', () async {
      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object2ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject2.toJson());
        return atValue;
      });

      var result = (await MyModelTest.getById(object2ModelId));
      expect(result, myModelTestObject2);
    });

    test('test getting all objects using AtCollectionModel', () async {
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SelfKey, object2SelfKey]);

      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object1ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject1.toJson());
        return atValue;
      });

      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object2ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject2.toJson());
        return atValue;
      });

      var allData = await AtCollectionModel.getAll<MyModelTest>(
          collectionModelFactory: MyModelTestFactory());

      expect(allData, [myModelTestObject1, myModelTestObject2]);
    });

    test('test getting all objects using MyModelTest', () async {
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SelfKey, object2SelfKey]);

      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object1ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject1.toJson());
        return atValue;
      });

      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object2ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject2.toJson());
        return atValue;
      });

      var allData = await MyModelTest.getAll();

      expect(allData, [myModelTestObject1, myModelTestObject2]);
    });

    test('test successfully saving an object', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSelfKeyMatcher(
                    id: myModelTestObject1.id, collectionName: collectionName)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      var saveRes1 = await myModelTestObject1.save(share: false);
      expect(saveRes1, true);

      // stream
      await myModelTestObject1.streams
          .save(share: false)
          .forEach((AtOperationItemStatus atOperationItemStatus) {
        expect(atOperationItemStatus.complete, true);
        expect(atOperationItemStatus.key,
            '${myModelTestObject1.id}.${myModelTestObject1.getCollectionName()}');
      });
    });

    test('test unsuccessfully saving an object', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSelfKeyMatcher(
                    id: myModelTestObject1.id, collectionName: collectionName)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => false);

      var res = await myModelTestObject1.save(share: false);
      expect(res, false);

      await myModelTestObject1.streams
          .save(share: false)
          .forEach((AtOperationItemStatus atOperationItemStatus) {
        expect(atOperationItemStatus.complete, false);
        expect(atOperationItemStatus.key,
            '${myModelTestObject1.id}.${myModelTestObject1.getCollectionName()}');
      });
    });

    test('test successfully saving and updating an object', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSelfKeyMatcher(
                    id: myModelTestObject1.id, collectionName: collectionName)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign1)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var res = await myModelTestObject1.save();
      expect(res, true);

      await myModelTestObject1.streams
          .save()
          .forEach((AtOperationItemStatus atOperationItemStatus) {
        expect(atOperationItemStatus.complete, true);
        expect(atOperationItemStatus.key,
            '${myModelTestObject1.id}.${myModelTestObject1.getCollectionName()}');
      });
    });

    test('test unsuccessfully saving and updating an object', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSelfKeyMatcher(
                    id: myModelTestObject1.id, collectionName: collectionName)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign1)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => false);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var isAllDataUpdated = await myModelTestObject1.save();
      expect(isAllDataUpdated, false);

      var allData = <AtOperationItemStatus>[];
      bool isAllStreamsDataUpdated = true;
      await myModelTestObject1.streams.save().forEach((result) {
        allData.add(result);
      });

      for (AtOperationItemStatus data in allData) {
        if (data.complete == false) {
          isAllStreamsDataUpdated = false;
        }
      }

      expect(isAllStreamsDataUpdated, false);
    });

    test('test retrieving shared with list of an object', () async {
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var result = await myModelTestObject1.getSharedWith();
      expect(result, [sharedWithAtsign1, sharedWithAtsign2]);
    });

    test('test successfully sharing an object with two atsigns', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign1)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      var isAllShared = await myModelTestObject1
          .share([sharedWithAtsign1, sharedWithAtsign2]);

      expect(isAllShared, true);

      // var allSharedData = <AtOperationItemStatus>[];
      // await myModelTestObject1.streams
      //     .share([sharedWithAtsign1, sharedWithAtsign2]).forEach((e) {
      //   allSharedData.add(e);
      // });

      // bool isAllSharedWithStream = true;

      // for (AtOperationItemStatus data in allSharedData) {
      //   if (allSharedData.length != 2 || data.complete == false) {
      //     isAllSharedWithStream = false;
      //   }
      // }

      // expect(isAllSharedWithStream, true);
    });

    test('test unsuccessfully sharing an object with two atsigns', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign1)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => false);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      var result = await myModelTestObject1
          .share([sharedWithAtsign1, sharedWithAtsign2]);
      expect(result, false);
    });

    test('test successfully deleting an object', () async {
      when(() => mockAtClient.delete(any(
          that: DeleteSelfKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName)))).thenAnswer((_) async => true);
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign1)))).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign2)))).thenAnswer((_) async => true);

      var result = await myModelTestObject1.delete();
      expect(result, true);
    });

    test('test unsuccessfully deleting an object, self key not deleted',
        () async {
      when(() => mockAtClient.delete(any(
          that: DeleteSelfKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName)))).thenAnswer((_) async => false);

      var result = await myModelTestObject1.delete();
      expect(result, false);
    });

    test('test unsuccessfully deleting an object, shared key not deleted',
        () async {
      when(() => mockAtClient.delete(any(
          that: DeleteSelfKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName)))).thenAnswer((_) async => true);
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign1)))).thenAnswer((_) async => false);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign2)))).thenAnswer((_) async => true);

      var result = await myModelTestObject1.delete();
      expect(result, false);
    });

    test('test successfully unsharing an object', () async {
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign1)))).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign2)))).thenAnswer((_) async => true);

      var result = await myModelTestObject1.unshare();
      expect(result, true);
    });

    test('test unsuccessfully unsharing an object', () async {
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign1)))).thenAnswer((_) async => false);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign2)))).thenAnswer((_) async => true);

      var result = await myModelTestObject1.unshare();
      expect(result, false);
    });

    test('testing series of operations on an object 1', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSelfKeyMatcher(
                    id: myModelTestObject1.id, collectionName: collectionName)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign1)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign1)))).thenAnswer((_) async => true);
      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign2)))).thenAnswer((_) async => true);

      var savingTheObject = await myModelTestObject1.save(share: false);
      expect(savingTheObject, true);

      var sharingTheObject = await myModelTestObject1
          .share([sharedWithAtsign1, sharedWithAtsign2]);
      expect(sharingTheObject, true);

      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      var unshareTheObject =
          await myModelTestObject1.unshare(atSigns: [sharedWithAtsign1]);
      expect(unshareTheObject, true);

      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey2]);

      var currentlySharedWith = await myModelTestObject1.getSharedWith();
      expect(currentlySharedWith, [sharedWithAtsign2]);
    });

    test('testing series of operations on an object 2', () async {
      when(() => mockAtClient.put(
            any(
                that: PutSelfKeyMatcher(
                    id: myModelTestObject1.id, collectionName: collectionName)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      /// no shared keys for now
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => []);

      /// it should only save it should not try to update shared keys
      var savingTheObject = await myModelTestObject1.save();
      expect(savingTheObject, true);

      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign1)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => true);

      /// we share the self key with two atsigns
      var sharingTheObject = await myModelTestObject1
          .share([sharedWithAtsign1, sharedWithAtsign2]);
      expect(sharingTheObject, true);

      /// two shared keys for now
      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey1, object1SharedKey2]);

      /// it should save and update shared keys
      var savingAndUpdatingTheObject = await myModelTestObject1.save();
      expect(savingAndUpdatingTheObject, true);

      /// if it fails to update for one of the objects
      when(() => mockAtClient.put(
            any(
                that: PutSharedKeyMatcher(
                    id: myModelTestObject1.id,
                    collectionName: collectionName,
                    sharedWith: sharedWithAtsign2)),
            any(that: PutDataMatcher()),
          )).thenAnswer((_) async => false);

      savingAndUpdatingTheObject = await myModelTestObject1.save();
      expect(savingAndUpdatingTheObject, false);

      /// should return the two atsigns we shared with
      var currentlySharedWith = await myModelTestObject1.getSharedWith();
      expect(currentlySharedWith, [sharedWithAtsign1, sharedWithAtsign2]);

      when(() => mockAtClient.delete(any(
          that: DeleteSharedKeyMatcher(
              id: myModelTestObject1.id,
              collectionName: collectionName,
              sharedWith: sharedWithAtsign1)))).thenAnswer((_) async => true);

      /// we unshare with one atsign
      var unshareTheObject =
          await myModelTestObject1.unshare(atSigns: [sharedWithAtsign1]);
      expect(unshareTheObject, true);

      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SharedKey2]);

      /// should return only one atsign we shared with
      currentlySharedWith = await myModelTestObject1.getSharedWith();
      expect(currentlySharedWith, [sharedWithAtsign2]);

      when(() => mockAtClient.getAtKeys(
              regex: any(
                  named: 'regex',
                  that: GetAtKeysMatcher(collectionName: collectionName))))
          .thenAnswer((_) async => [object1SelfKey]);
      when(() => mockAtClient.get(any(
          that: GetAtKeyMatcher(
              keyId: object1ModelId,
              collectionName: collectionName)))).thenAnswer((_) async {
        var atValue = AtValue();
        atValue.value = jsonEncode(myModelTestObject1.toJson());
        return atValue;
      });

      /// there should only be one shared object
      // var sharedObjects = await AtCollectionModel.getAll<MyModelTest>();
      // expect(sharedObjects, [myModelTestObject1]);
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
    if (atKey is AtKey &&
        atKey.key!.contains(id) &&
        atKey.key!.contains(collectionName)) {
      print("matched atKey: $atKey");
      return true;
    }
    return false;
  }
}

class PutSharedKeyMatcher extends Matcher {
  String id, collectionName, sharedWith;

  PutSharedKeyMatcher(
      {required this.id,
      required this.collectionName,
      required this.sharedWith});

  @override
  Description describe(Description description) => description
      .add('A custom matcher to match the shared key for put method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey &&
        atKey.key!.contains(id) &&
        atKey.key!.contains(collectionName) &&
        (atKey.sharedWith == sharedWith)) {
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
    if (data is AtKey &&
        data.key!.contains(keyId) &&
        data.key!.contains(collectionName)) {
      return true;
    }
    return false;
  }
}

class DeleteSelfKeyMatcher extends Matcher {
  String id, collectionName;

  DeleteSelfKeyMatcher({required this.id, required this.collectionName});

  @override
  Description describe(Description description) => description
      .add('A custom matcher to match the self key for delete method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey &&
        atKey.key!.contains(id) &&
        atKey.key!.contains(collectionName)) {
      return true;
    }
    return false;
  }
}

class DeleteSharedKeyMatcher extends Matcher {
  String id, collectionName, sharedWith;

  DeleteSharedKeyMatcher(
      {required this.id,
      required this.collectionName,
      required this.sharedWith});

  @override
  Description describe(Description description) => description
      .add('A custom matcher to match the shared key for delete method');

  @override
  bool matches(atKey, Map matchState) {
    if (atKey is AtKey &&
        atKey.key!.contains(id) &&
        atKey.key!.contains(collectionName) &&
        (atKey.sharedWith == sharedWith)) {
      return true;
    }
    return false;
  }
}

//// TODO Rules:
/// 1. Have a no parametrs default constructor
/// 2. For variables we can have setters / public /or any way app wants
class MyModelTest extends AtCollectionModel {
  late int number;
  late String name;
  late String email;

  MyModelTest();

  MyModelTest.from(this.number, this.name, this.email);

  factory MyModelTest.create() {
    return MyModelTest();
  }

  static Future<List<MyModelTest>> getAll() async {
    return AtCollectionModel.getAll<MyModelTest>(
        collectionName: 'mymodeltest',
        collectionModelFactory: MyModelTestFactory());
  }

  static Future<MyModelTest> getById(String keyId) async {
    return (await AtCollectionModel.getById<MyModelTest>(keyId,
        collectionName: 'mymodeltest',
        collectionModelFactory: MyModelTestFactory()));
  }

  @override
  fromJson(String jsonEncodedString) {
    var json = jsonDecode(jsonEncodedString);

    number = int.parse(json['number']);
    name = json['name'];
    email = json['email'];
    id = json['id'];
  }

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['id'] = id;
    data['collectionName'] = runtimeType.toString().toLowerCase();
    data['name'] = name;
    data['number'] = number.toString();
    data['email'] = email;
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

  @override
  String getCollectionName() {
    return 'mymodeltest';
  }
}

class MyModelTestFactory extends AtCollectionModelFactory<MyModelTest> {
  @override
  create() {
    return MyModelTest();
  }
}
