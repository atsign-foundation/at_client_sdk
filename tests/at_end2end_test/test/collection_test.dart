import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/collection_util.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class PreferenceFactory extends AtCollectionModelFactory<Preference> {
  PreferenceFactory();

  @override
  Preference create() {
    return Preference();
  }

  @override
  bool acceptCollection(String collectionName) {
    return collectionName == 'preference' ? true : false;
  }
}

class Preference extends AtCollectionModel {
  Map<String, dynamic>? preference;

  @override
  fromJson(Map<String, dynamic> jsonObject) {
    preference = jsonObject;
  }

  @override
  Map<String, dynamic> toJson() {
    var data = <String, dynamic>{};
    final preference = this.preference;
    if (preference != null) {
      for (String key in preference.keys) {
        data[key] = preference[key];
      }
    }
    return data;
  }
}

class Contact extends AtCollectionModel {
  String? atSign;
  String? nickname;

  @override
  fromJson(Map<String, dynamic> jsonObject) {
    atSign = jsonObject['atSign'];
    nickname = jsonObject['nickname'];
  }

  @override
  Map<String, dynamic> toJson() {
    var data = <String, dynamic>{};
    data['atSign'] = atSign;
    data['nickname'] = nickname;
    return data;
  }
}

class ContactFactory extends AtCollectionModelFactory<Contact> {
  @override
  Contact create() {
    return Contact();
  }

  @override
  bool acceptCollection(String collectionName) {
    return collectionName == 'contact' ? true : false;
  }
}

class Phone extends AtCollectionModel {
  String? phoneNumber;

  @override
  void fromJson(Map<String, dynamic> jsonModel) {
    phoneNumber = jsonModel['phoneNumber'];
  }

  @override
  Map<String, dynamic> toJson() {
    var data = <String, dynamic>{};
    data['phoneNumber'] = phoneNumber;
    return data;
  }
}

class PhoneFactory extends AtCollectionModelFactory<Phone> {
  @override
  Phone create() {
    return Phone();
  }

  @override
  bool acceptCollection(String collectionName) {
    return collectionName == 'phone' ? true : false;
  }
}

class A extends AtCollectionModel {
  String? a;

  A();

  A.from(String id, {this.a}) {
    this.id = id;
    namespace = TestConstants.namespace;
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    a = json['a'];
  }

  @override
  Map<String, dynamic> toJson() {
    var data = <String, dynamic>{};
    data['a'] = a;
    return data;
  }
}

class AFactory extends AtCollectionModelFactory<A> {
  @override
  A create() {
    return A();
  }

  @override
  bool acceptCollection(String collectionName) {
    return collectionName == 'a' ? true : false;
  }
}

class B extends AtCollectionModel {
  String? b;

  B();

  B.from(String id, {this.b}) {
    this.id = id;
    namespace = TestConstants.namespace;
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    b = json['b'];
  }

  @override
  Map<String, dynamic> toJson() {
    var data = <String, dynamic>{};
    data['b'] = b;
    return data;
  }
}

class BFactory extends AtCollectionModelFactory<B> {
  @override
  B create() {
    return B();
  }

  @override
  bool acceptCollection(String collectionName) {
    return collectionName == 'b' ? true : false;
  }
}

void main() async {
  AtClientManager acm = AtClientManager.getInstance();
  AtCollectionModelFactoryManager atCollectionModelFactoryManager =
      AtCollectionModelFactoryManager.getInstance();
  late Atsign firstAtSign, secondAtSign, thirdAtSign, fourthAtSign;
  final namespace = TestConstants.namespace;
  int randomId = Uuid().v4().hashCode;

  /// - If there is currently an atClient, sync it
  /// - Then switch to the required atSign
  /// - And sync it
  Future<AtClient> switchTo(Atsign atSign) async {
    try {
      AtClient existing = acm.atClient;
      await E2ESyncService.getInstance().syncData(existing.syncService);
    } on StateError catch (_) {}

    AtClient latest = (await acm.setCurrentAtSign(
      atSign,
      namespace,
      TestPreferences.getInstance().getPreference(atSign),
    ))
        .atClient;

    await E2ESyncService.getInstance().syncData(latest.syncService);

    return latest;
  }

  setUpAll(() async {
    firstAtSign =
        ConfigUtil.getYaml()['atSign']['firstAtSign'].toString().toAtsign();
    secondAtSign =
        ConfigUtil.getYaml()['atSign']['secondAtSign'].toString().toAtsign();
    thirdAtSign =
        ConfigUtil.getYaml()['atSign']['thirdAtSign'].toString().toAtsign();
    fourthAtSign =
        ConfigUtil.getYaml()['atSign']['fourthAtSign'].toString().toAtsign();

    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(firstAtSign, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(secondAtSign, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(thirdAtSign, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(fourthAtSign, namespace, authType);
  });

  test('Model operations - save() with reshare() as true test', () async {
    // Setting firstAtSign atClient instance to context.
    await switchTo(firstAtSign);

    // Share a phone
    var phone = Phone()
      ..id = 'personal phone-$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareRes, true);

    // Have the phone number changed
    phone.phoneNumber = '12345-9999';
    // Now call a save with reshare as true
    var saveStatus = await phone.save(
      autoReshare: true,
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(saveStatus, true);

    // Receiver's end - Verify that the phone has been shared
    AtClient secondAtClient = await switchTo(secondAtSign);

    var regex = CollectionUtil.makeRegex(
        formattedId: 'personal-phone-$randomId',
        collectionName: 'phone',
        namespace: TestConstants.namespace);

    List<String> keys = await secondAtClient.getKeys(regex: regex);
    expect(keys.length, 1,
        reason: 'Should only be one key matching this regex: $regex');

    AtValue atValue = await secondAtClient.get(AtKey.fromString(keys[0]));
    expect(jsonDecode(atValue.value)['phoneNumber'], '12345-9999',
        reason:
            'Since the value is re-shared the phone number should be the new modified one');
  });

  test('Model operations - share() test', () async {
    // Setting firstAtSign atClient instance to context.
    await switchTo(firstAtSign);
    // Share a phone
    var phone = Phone()
      ..id = 'personal phone-$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareRes, true);

    // Receiver's end - Verify that the phone has been shared
    AtClient secondAtClient = await switchTo(secondAtSign);

    var regex = CollectionUtil.makeRegex(
        formattedId: 'personal-phone-$randomId',
        collectionName: 'phone',
        namespace: TestConstants.namespace);
    var getResult = await secondAtClient.getKeys(regex: regex);
    expect(getResult.length, 1);
  });

  test('Model operations - unshare() and delete() test', () async {
    // Setting firstAtSign atClient instance to context.
    AtClient firstAtClient = await switchTo(firstAtSign);

    var fourthPhone = Phone()
      ..id = 'personal phone-$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '4444';
    await fourthPhone.save(options: TestConstants.optionsTtlOneMinute);
    await fourthPhone.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(await fourthPhone.sharedWith(),
        [ConfigUtil.getYaml()['atSign']['secondAtSign']]);

    var shareResponse = await fourthPhone.share(
      [thirdAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareResponse, true);
    List<String> atSignsList = await fourthPhone.sharedWith();
    expect(atSignsList.length, 2);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['secondAtSign']),
        true);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['thirdAtSign']),
        true);
    atSignsList.clear();

    shareResponse = await fourthPhone.share(
      [fourthAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareResponse, true);
    atSignsList = await fourthPhone.sharedWith();
    expect(atSignsList.length, 3);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['secondAtSign']),
        true);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['thirdAtSign']),
        true);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['fourthAtSign']),
        true);
    atSignsList.clear();

    // Let's wait for a sync, and then unshare
    await E2ESyncService.getInstance().syncData(firstAtClient.syncService);

    // Unshare now
    await fourthPhone.unshare(atSigns: [thirdAtSign, fourthAtSign]);
    expect(await fourthPhone.sharedWith(),
        [ConfigUtil.getYaml()['atSign']['secondAtSign']]);
    await fourthPhone.unshare(atSigns: [secondAtSign]);
    await fourthPhone.delete();
    expect(await fourthPhone.sharedWith(), []);
    await expectLater(
      AtCollectionModel.getModel(
          id: 'fourth phone',
          namespace: TestConstants.namespace,
          collectionName: 'phone'),
      throwsA(isA<AtKeyNotFoundException>()),
    );
  });

  test('Query method - AtCollectionModel.getModelsSharedWith() test', () async {
    // Setting firstAtSign atClient instance to context.
    AtClient firstAtClient = await switchTo(firstAtSign);

    var a = A.from('a1', a: 'a1 value');
    var shareRes = await a.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareRes, true);
    var b = B.from('b1', b: 'b1 value');
    await b.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );

    final aFactory = AFactory();
    final bFactory = BFactory();
    atCollectionModelFactoryManager.register(aFactory);
    atCollectionModelFactoryManager.register(bFactory);

    await E2ESyncService.getInstance().syncData(firstAtClient.syncService);

    var res = await AtCollectionModel.getModelsSharedWith(secondAtSign);
    expect(res.isEmpty, false,
        reason: 'Expect the models shared to be non-empty');
    atCollectionModelFactoryManager.unregister(aFactory);
    atCollectionModelFactoryManager.unregister(bFactory);
  });

  test('Query method - AtCollectionModel.getModelsSharedBy() test', () async {
    // Setting firstAtSign atClient instance to context.
    await switchTo(firstAtSign);

    var a = A.from('a1', a: 'a1 value');
    var shareRes = await a.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareRes, true);
    var b = B.from('b1', b: 'b1 value');
    shareRes = await b.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    expect(shareRes, true);

    // Receiver's end
    await switchTo(secondAtSign);

    final aFactory = AFactory();
    final bFactory = BFactory();
    atCollectionModelFactoryManager.registerFactories([aFactory, bFactory]);
    var res = await AtCollectionModel.getModelsSharedBy(firstAtSign);
    expect(res.isEmpty, false,
        reason: 'Expect the models shared by to be non-empty');
    atCollectionModelFactoryManager.unregisterFactories([aFactory, bFactory]);
  });

  test('Query method - AtCollectionModel.getModelsSharedByAnyAtSign() test',
      () async {
    // Setting firstAtSign atClient instance to context.
    await switchTo(firstAtSign);

    // Share at Collections models from first atSign to second atSign
    var a = A.from('a11', a: 'a11 value');
    await a.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    var b = B.from('b11', b: 'b11 value');
    await b.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    // Share at Collections models from third atSign to second atSign
    await switchTo(thirdAtSign);

    a = A.from('a22', a: 'a22 value');
    await a.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    b = B.from('b22', b: 'b22 value');
    await b.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );
    // Switch to second atSign and get AtCollectionModels shared by any atSign
    await switchTo(secondAtSign);
    final aFactory = AFactory();
    final bFactory = BFactory();
    atCollectionModelFactoryManager.registerFactories([aFactory, bFactory]);
    var res = await AtCollectionModel.getModelsSharedByAnyAtSign();
    expect(res.isEmpty, false,
        reason: 'Expect the models shared by to be non-empty');
    expect(res.length >= 4, true,
        reason: 'Expect a minimum of 4 shared models');
    atCollectionModelFactoryManager.unregister(aFactory);
    atCollectionModelFactoryManager.unregister(bFactory);
  });

  test(
      'Query methods - Test retrieval of shared models with and without factories',
      () async {
    // Setting firstAtSign atClient instance to context.
    await switchTo(firstAtSign);

    Map<String, String> pizzaPreferences = <String, String>{};
    pizzaPreferences['bread'] = 'X';
    pizzaPreferences['cheeze'] = 'Y';
    pizzaPreferences['topping'] = 'Z';

    Preference preference = Preference()
      ..id = 'pizza preference'
      ..namespace = TestConstants.namespace
      ..collectionName = 'preference'
      ..preference = pizzaPreferences;
    await preference.save(
      options: TestConstants.optionsTtlOneMinute,
    );

    await preference.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );

    var contact = Contact()
      ..id = 'jagan'
      ..namespace = TestConstants.namespace
      ..collectionName = 'contact'
      ..atSign = '@jagan'
      ..nickname = 'jagan';
    await contact.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );

    Phone phone = Phone()
      ..id = 'my another phone'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '1122';
    await phone.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );

    /// receiver's end
    await switchTo(secondAtSign);

    // Get models without registering the factories
    var res = await AtCollectionModel.getModelsSharedBy(firstAtSign);

    for (var model in res) {
      expect(model is AtJsonCollectionModel, true,
          reason:
              'Without factories AtCollectionsModels should be of type AtJsonCollectionModel');
    }

    expect(res.isEmpty, false);

    // Get models with registering the factories
    List<AtCollectionModelFactory> factories = [
      PreferenceFactory(),
      ContactFactory(),
      PhoneFactory(),
    ];
    atCollectionModelFactoryManager.registerFactories(factories);
    res = await AtCollectionModel.getModelsSharedBy(firstAtSign);
    for (var model in res) {
      switch (model.collectionName) {
        case 'phone':
          expect(model is Phone, true,
              reason:
                  'For collection name phone, model should be of type Phone');
          break;
        case 'contact':
          expect(model is Contact, true,
              reason:
                  'For collection name contact, model should be of type Contact');
          break;
        case 'preference':
          expect(model is Preference, true,
              reason:
                  'For collection name preference, model should be of type Preference');
          break;
      }
    }
    atCollectionModelFactoryManager.unregisterFactories(factories);
  });

  test('Query methods - Test retrieval of sharedWithAnyAtSign', () async {
    // Setting firstAtSign atClient instance to context.
    AtClient firstAtClient = await switchTo(firstAtSign);

    // Share a phone
    var p1 = Phone()
      ..id = 'p1$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    await p1.save(
      options: TestConstants.optionsTtlOneMinute,
    );
    var p2 = Phone()
      ..id = 'p2$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    await p2.save(
      options: TestConstants.optionsTtlOneMinute,
    );
    await p2.share(
      [secondAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );

    var a = A.from('aId$randomId', a: 'aId$randomId');
    await a.save(
      options: TestConstants.optionsTtlOneMinute,
    );
    await a.share(
      [secondAtSign, thirdAtSign],
      options: TestConstants.optionsTtlOneMinute,
    );

    await E2ESyncService.getInstance().syncData(firstAtClient.syncService);

    var atCollectionModelList =
        await AtCollectionModel.getModelsSharedWithAnyAtSign();
    expect(atCollectionModelList.length, greaterThanOrEqualTo(1));

    for (AtCollectionModel atCollection in atCollectionModelList) {
      List sharedWithAtSigns = await atCollection.sharedWith();
      if (atCollection.id == 'aId$randomId') {
        expect(sharedWithAtSigns.contains(secondAtSign), true);
        expect(sharedWithAtSigns.contains(thirdAtSign), true);
      }
      if (atCollection.id == 'p2$randomId') {
        expect(sharedWithAtSigns.contains(secondAtSign), true);
      }
    }
  });

  test('Model operations - save and incremental share with stream', () async {
    // Setting firstAtSign atClient instance to context.
    await switchTo(firstAtSign);

    List<AtCollectionModelFactory> factories = [PhoneFactory()];
    atCollectionModelFactoryManager.registerFactories(factories);

    Phone fifthPhone = Phone()
      ..id = 'fifth phone'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '55555';

    await fifthPhone.streams.save(share: false).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel');
        expect(element.atSign, firstAtSign);
        expect(element.operation, Operation.save);
      },
    );

    await fifthPhone.streams.share([secondAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel');
      },
    );

    await fifthPhone.streams.share([thirdAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel');
      },
    );

    await fifthPhone.streams.share([fourthAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel');
      },
    );

    // Unshare now
    await fifthPhone.streams
        .unshare(atSigns: [thirdAtSign, fourthAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel');
      },
    );

    await fifthPhone.streams.delete().forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel');
      },
    );

    expect(await fifthPhone.sharedWith(), []);
    atCollectionModelFactoryManager.unregisterFactories(factories);
  });
}
