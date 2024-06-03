import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/at_json_collection_model.dart';
import 'package:at_client/src/at_collection/collection_util.dart';
import 'package:at_client/src/at_collection/collections.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class PreferenceFactory extends AtCollectionModelFactory<Preference> {
  static final PreferenceFactory _singleton = PreferenceFactory._internal();

  PreferenceFactory._internal();

  factory PreferenceFactory.getInstance() {
    return _singleton;
  }

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
  static final ContactFactory _singleton = ContactFactory._internal();

  ContactFactory._internal();

  factory ContactFactory.getInstance() {
    return _singleton;
  }

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
  static final PhoneFactory _singleton = PhoneFactory._internal();

  PhoneFactory._internal();

  factory PhoneFactory.getInstance() {
    return _singleton;
  }

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
  static final AFactory _singleton = AFactory._internal();

  AFactory._internal();

  factory AFactory.getInstance() {
    return _singleton;
  }

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
  static final BFactory _singleton = BFactory._internal();

  BFactory._internal();

  factory BFactory.getInstance() {
    return _singleton;
  }

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
  late AtClientManager currentAtClientManager;
  late AtClientManager sharedWithAtClientManager;
  late String firstAtSign;
  late String secondAtSign, thirdAtSign, fourthAtSign;
  final namespace = TestConstants.namespace;
  int randomId = Uuid().v4().hashCode;

  setUpAll(() async {
    firstAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    secondAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    thirdAtSign = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    fourthAtSign = ConfigUtil.getYaml()['atSign']['fourthAtSign'];

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
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    // Share a phone
    var phone = Phone()
      ..id = 'personal phone-$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.share([secondAtSign]);
    expect(shareRes, true);

    // Have the phone number changed
    phone.phoneNumber = '12345-9999';
    // Now call a save with reshare as true
    var saveStatus = await phone.save(autoReshare: true);
    expect(saveStatus, true);

    await E2ESyncService.getInstance().syncData(
        currentAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()
          ..key =
              '$secondAtSign:personal-phone-$randomId.phone.atcollectionmodel.${TestConstants.namespace}$firstAtSign');

    // Receiver's end - Verify that the phone has been shared
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      secondAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(secondAtSign),
    );
    await E2ESyncService.getInstance().syncData(
        sharedWithAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()
          ..key =
              'cached:$secondAtSign:personal-phone-$randomId.phone.atcollectionmodel.${TestConstants.namespace}$firstAtSign');
    var regex = CollectionUtil.makeRegex(
        formattedId: 'personal-phone-$randomId',
        collectionName: 'phone',
        namespace: TestConstants.namespace);

    List<String> keys =
        await sharedWithAtClientManager.atClient.getKeys(regex: regex);
    print('Keys sync to $secondAtSign: $keys');
    expect(keys.length, 1,
        reason:
            'On the recipient side expecting a single keys with the regex supplied');

    AtValue atValue =
        await sharedWithAtClientManager.atClient.get(AtKey.fromString(keys[0]));
    expect(jsonDecode(atValue.value)['phoneNumber'], '12345-9999',
        reason:
            'Since the value is re-shared the phone number should be the new modified one');
  });

  test('Model operations - share() test', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );
    // Share a phone
    var phone = Phone()
      ..id = 'personal phone-$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.share([secondAtSign]);
    expect(shareRes, true);
    await E2ESyncService.getInstance().syncData(
        currentAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()
          ..key =
              '$secondAtSign:personal-phone-$randomId.phone.atcollectionmodel.${TestConstants.namespace}$firstAtSign');

    // Receiver's end - Verify that the phone has been shared
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      secondAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(secondAtSign),
    );
    await E2ESyncService.getInstance().syncData(
      sharedWithAtClientManager.atClient.syncService,
    );
    var regex = CollectionUtil.makeRegex(
        formattedId: 'personal-phone-$randomId',
        collectionName: 'phone',
        namespace: TestConstants.namespace);
    var getResult =
        await sharedWithAtClientManager.atClient.getKeys(regex: regex);
    expect(getResult.length, 1);
  });

  test('Model operations - unshare() and delete() test', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var fourthPhone = Phone()
      ..id = 'personal phone-$randomId'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '4444';
    await fourthPhone.save();
    await fourthPhone.share([secondAtSign]);
    expect(await fourthPhone.sharedWith(),
        [ConfigUtil.getYaml()['atSign']['secondAtSign']]);

    var shareResponse = await fourthPhone.share([thirdAtSign]);
    expect(shareResponse, true);
    List<String> atSignsList = await fourthPhone.sharedWith();
    expect(atSignsList.length, 2);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['secondAtSign']),
        true);
    expect(atSignsList.contains(ConfigUtil.getYaml()['atSign']['thirdAtSign']),
        true);
    atSignsList.clear();

    shareResponse = await fourthPhone.share([fourthAtSign]);
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

    // Unshare now
    await fourthPhone.unshare(atSigns: [thirdAtSign, fourthAtSign]);
    expect(await fourthPhone.sharedWith(),
        [ConfigUtil.getYaml()['atSign']['secondAtSign']]);
    await fourthPhone.unshare(atSigns: [secondAtSign]);
    await fourthPhone.delete();
    expect(await fourthPhone.sharedWith(), []);
    expect(
      () async => await AtCollectionModel.getModel(
          id: 'fourth phone',
          namespace: TestConstants.namespace,
          collectionName: 'phone'),
      throwsA(isA<Exception>()),
    );
  });

  test('Query method - AtCollectionModel.getModelsSharedWith() test', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var a = A.from('a1', a: 'a1 value');
    var shareRes = await a.share([secondAtSign]);
    expect(shareRes, true);
    var b = B.from('b1', b: 'b1 value');
    await b.share([secondAtSign]);

    AtCollectionModelFactoryManager.getInstance()
        .register(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .register(BFactory.getInstance());

    await E2ESyncService.getInstance().syncData(
        currentAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()
          ..key =
              '$secondAtSign:b1.b.atcollectionmodel.${TestConstants.namespace}$firstAtSign');

    var res = await AtCollectionModel.getModelsSharedWith(secondAtSign);
    expect(res.isEmpty, false,
        reason: 'Expect the models shared to be non-empty');
    AtCollectionModelFactoryManager.getInstance()
        .unregister(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(BFactory.getInstance());
  });

  test('Query method - AtCollectionModel.getModelsSharedBy() test', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var a = A.from('a1', a: 'a1 value');
    var shareRes = await a.share([secondAtSign]);
    expect(shareRes, true);
    var b = B.from('b1', b: 'b1 value');
    shareRes = await b.share([secondAtSign]);
    expect(shareRes, true);

    // Receiver's end
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      secondAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(secondAtSign),
    );

    await E2ESyncService.getInstance().syncData(
      sharedWithAtClientManager.atClient.syncService,
    );
    AtCollectionModel.registerFactories(
        [AFactory.getInstance(), BFactory.getInstance()]);
    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);
    var res = await AtCollectionModel.getModelsSharedBy(firstAtSign);
    expect(res.isEmpty, false,
        reason: 'Expect the models shared by to be non-empty');
    AtCollectionModelFactoryManager.getInstance()
        .unregister(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(BFactory.getInstance());
  });

  test('Query method - AtCollectionModel.getModelsSharedByAnyAtSign() test',
      () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );
    // Share at Collections models from first atSign to second atSign
    var a = A.from('a11', a: 'a11 value');
    await a.share([secondAtSign]);
    var b = B.from('b11', b: 'b11 value');
    await b.share([secondAtSign]);
    // Share at Collections models from third atSign to second atSign
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      thirdAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(thirdAtSign),
    );
    await E2ESyncService.getInstance().syncData(
      sharedWithAtClientManager.atClient.syncService,
    );
    a = A.from('a22', a: 'a22 value');
    await a.share([secondAtSign]);
    b = B.from('b22', b: 'b22 value');
    await b.share([secondAtSign]);
    // Switch to second atSign and get AtCollectionModels shared by any atSign
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      secondAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(secondAtSign),
    );
    await E2ESyncService.getInstance().syncData(
      sharedWithAtClientManager.atClient.syncService,
    );
    AtCollectionModel.registerFactories(
        [AFactory.getInstance(), BFactory.getInstance()]);
    var res = await AtCollectionModel.getModelsSharedByAnyAtSign();
    expect(res.isEmpty, false,
        reason: 'Expect the models shared by to be non-empty');
    expect(res.length >= 4, true,
        reason: 'Expect a minimum of 4 shared models');
    AtCollectionModelFactoryManager.getInstance()
        .unregister(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(BFactory.getInstance());
  });

  test(
      'Query methods - Test retrieval of shared models with and without factories',
      () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    Map<String, String> pizzaPreferences = <String, String>{};
    pizzaPreferences['bread'] = 'X';
    pizzaPreferences['cheeze'] = 'Y';
    pizzaPreferences['topping'] = 'Z';

    Preference preference = Preference()
      ..id = 'pizza preference'
      ..namespace = TestConstants.namespace
      ..collectionName = 'preference'
      ..preference = pizzaPreferences;
    await preference.save();

    await preference.share([secondAtSign]);

    var contact = Contact()
      ..id = 'jagan'
      ..namespace = TestConstants.namespace
      ..collectionName = 'contact'
      ..atSign = '@jagan'
      ..nickname = 'jagan';
    await contact.share([secondAtSign]);

    Phone phone = Phone()
      ..id = 'my another phone'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '1122';
    await phone.share([secondAtSign]);

    /// receiver's end
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      secondAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(secondAtSign),
    );

    await E2ESyncService.getInstance().syncData(
      sharedWithAtClientManager.atClient.syncService,
    );

    // Get models without registering the factories
    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    var res = await AtCollectionModel.getModelsSharedBy(firstAtSign);

    for (var model in res) {
      expect(model is AtJsonCollectionModel, true,
          reason:
              'Without factories AtCollectionsModels should be of type AtJsonCollectionModel');
    }

    expect(res.isEmpty, false);

    // Get models with registering the factories
    AtCollectionModel.registerFactories([
      PreferenceFactory.getInstance(),
      ContactFactory.getInstance(),
      PhoneFactory.getInstance()
    ]);
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
    AtCollectionModelFactoryManager.getInstance()
        .unregister(PhoneFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(ContactFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(PreferenceFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance()
        .unregister(BFactory.getInstance());
  });

  test('Query methods - Test retrieval of sharedWithAnyAtSign', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    // Share a phone
    var p1 = Phone()
      ..id = 'p1'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    await p1.save();
    var p2 = Phone()
      ..id = 'p2'
      ..namespace = TestConstants.namespace
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    await p2.save();
    await p2.share([secondAtSign]);

    var a = A.from('aId', a: 'aId');
    await a.save();
    await a.share([secondAtSign, thirdAtSign]);

    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    var atCollectionModelList =
        await AtCollectionModel.getModelsSharedWithAnyAtSign();
    expect(atCollectionModelList.length, greaterThanOrEqualTo(1));

    for (AtCollectionModel atCollection in atCollectionModelList) {
      List sharedWithAtSigns = await atCollection.sharedWith();
      if (atCollection.id == 'aId') {
        expect(sharedWithAtSigns.contains(secondAtSign), true);
        expect(sharedWithAtSigns.contains(thirdAtSign), true);
      }
      if (atCollection.id == 'p2') {
        expect(sharedWithAtSigns.contains(secondAtSign), true);
      }
    }
  });

  test('Model operations - save and incremental share with stream', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    AtCollectionModel.registerFactories([PhoneFactory.getInstance()]);

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
    AtCollectionModelFactoryManager.getInstance()
        .unregister(PhoneFactory.getInstance());
  });
}
