import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/at_collection/at_json_collection_model.dart';
import 'package:at_client/src/at_collection/collection_util.dart';
import 'package:at_client/src/at_collection/collections.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:at_utils/at_logger.dart';

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
    this.namespace = 'buzz';
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
    this.namespace = 'buzz';
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
  final namespace = 'wavi';

  setUpAll(() async {
    firstAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    secondAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    thirdAtSign = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    fourthAtSign = ConfigUtil.getYaml()['atSign']['fourthAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(firstAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(secondAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(thirdAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(fourthAtSign, namespace);
  });

  test('Model operations - save() test', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    // Save a photo
    var phone = Phone()
      ..id = 'personal phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.save();
    expect(shareRes, true);
  });

  test('Model operations - save() with reshare() as true test', () async {
    AtSignLogger.root_level = 'finest';
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    // Share a phone
    var phone = Phone()
      ..id = 'personal phone'
      ..namespace = 'buzz'
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
              '$secondAtSign:personal-phone.phone.atcollectionmodel.buzz.wavi$firstAtSign');

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
              'cached:$secondAtSign:personal-phone.phone.atcollectionmodel.buzz.wavi$firstAtSign');
    var regex = CollectionUtil.makeRegex(
        formattedId: 'personal-phone',
        collectionName: 'phone',
        namespace: 'buzz');

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
      ..id = 'personal phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.share([secondAtSign]);
    expect(shareRes, true);
    await E2ESyncService.getInstance().syncData(
        currentAtClientManager.atClient.syncService,
        syncOptions: SyncOptions()
          ..key =
              '$secondAtSign:personal-phone.phone.atcollectionmodel.buzz.wavi$firstAtSign');

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
        formattedId: 'personal-phone',
        collectionName: 'phone',
        namespace: 'buzz');
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
      ..id = 'personal phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '4444';
    await fourthPhone.save();
    await fourthPhone.share([secondAtSign]);
    expect(await fourthPhone.sharedWith(), ['@ce2e2']);
    await fourthPhone.share([thirdAtSign]);
    expect(await fourthPhone.sharedWith(), ['@ce2e2', '@ce2e3']);
    await fourthPhone.share([fourthAtSign]);
    expect(await fourthPhone.sharedWith(), ['@ce2e2', '@ce2e3', '@ce2e4']);

    // Unshare now
    await fourthPhone.unshare(atSigns: [thirdAtSign, fourthAtSign]);
    expect(await fourthPhone.sharedWith(), ['@ce2e2']);
    await fourthPhone.unshare(atSigns: [secondAtSign]);
    await fourthPhone.delete();
    expect(await fourthPhone.sharedWith(), []);
    expect(
      () async => await AtCollectionModel.getModel(
          id: 'fourth phone', namespace: 'buzz', collectionName: 'phone'),
      throwsA(isA<Exception>()),
    );
  });

  test('Query method - AtCollectionModel.getModel() test', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    Phone personalPhone = Phone()
      ..id = 'new personal Phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '123456789';
    Phone officePhone = Phone()
      ..id = 'Office Phone'
      ..namespace = 'buzz.bz'
      ..collectionName = 'phone'
      ..phoneNumber = '9999';
    await personalPhone.save();
    await officePhone.save();

    AtCollectionModel.registerFactories([PhoneFactory.getInstance()]);
    var personalPhoneLoaded = await AtCollectionModel.getModel(
        id: 'new personal Phone',
        namespace: 'buzz',
        collectionName: 'phone') as Phone;

    expect(personalPhoneLoaded.phoneNumber, '123456789');
    expect(personalPhoneLoaded.collectionName, 'phone');
    expect(personalPhoneLoaded.namespace, 'buzz');
    expect(personalPhoneLoaded.id, 'new personal Phone');
    var officePhoneLoaded = await AtCollectionModel.getModel(
        id: 'Office Phone',
        namespace: 'buzz.bz',
        collectionName: 'phone') as Phone;

    expect(officePhoneLoaded.phoneNumber, '9999');
    expect(officePhoneLoaded.collectionName, 'phone');
    expect(officePhoneLoaded.namespace, 'buzz.bz');
    expect(officePhoneLoaded.id, 'Office Phone');
    AtCollectionModelFactoryManager.getInstance()
        .unregister(PhoneFactory.getInstance());
  });

  test('Query method - AtCollectionModel.getModelsByCollectionName() test',
      () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    Phone personalPhone = Phone()
      ..id = 'new personal Phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '123456789';
    Phone officePhone = Phone()
      ..id = 'Office Phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '9999';
    await personalPhone.save();
    await officePhone.save();

    AtCollectionModel.registerFactories([PhoneFactory.getInstance()]);
    // Get models with existing collectionName
    var phones = await AtCollectionModel.getModelsByCollectionName('phone');
    expect(phones.length >= 2, true,
        reason: 'Expect phones to be non-empty for an valid collection name');
    // Get models with non-existing id/inv collectionName
    phones =
        await AtCollectionModel.getModelsByCollectionName('phone-dont-exist');
    expect(phones.isEmpty, true,
        reason: 'Expect phones to be empty for an invalid collection name');
    AtCollectionModelFactoryManager.getInstance()
        .unregister(PhoneFactory.getInstance());
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
          ..key = '$secondAtSign:b1.b.atcollectionmodel.buzz.wavi$firstAtSign');

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
      'Query methods - Test retreival of shared models with and without factories',
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
      ..namespace = 'buzz'
      ..collectionName = 'preference'
      ..preference = pizzaPreferences;
    await preference.save();

    await preference.share([secondAtSign]);

    var contact = Contact()
      ..id = 'jagan'
      ..namespace = 'buzz'
      ..collectionName = 'contact'
      ..atSign = '@jagan'
      ..nickname = 'jagan';
    await contact.share([secondAtSign]);

    Phone phone = Phone()
      ..id = 'my another phone'
      ..namespace = 'buzz'
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
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    await p1.save();
    var p2 = Phone()
      ..id = 'p2'
      ..namespace = 'buzz'
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
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '55555';

    await fifthPhone.streams.save(share: false).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel.buzz');
        expect(element.atSign, firstAtSign);
        expect(element.operation, Operation.save);
      },
    );

    await fifthPhone.streams.share([secondAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel.buzz');
      },
    );

    await fifthPhone.streams.share([thirdAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel.buzz');
      },
    );

    await fifthPhone.streams.share([fourthAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel.buzz');
      },
    );

    // Unshare now
    await fifthPhone.streams
        .unshare(atSigns: [thirdAtSign, fourthAtSign]).forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel.buzz');
      },
    );

    await fifthPhone.streams.delete().forEach(
      (AtOperationItemStatus element) {
        expect(element.complete, true);
        expect(element.key, 'fifth-phone.phone.atcollectionmodel.buzz');
      },
    );

    expect(await fifthPhone.sharedWith(), []);
    AtCollectionModelFactoryManager.getInstance()
        .unregister(PhoneFactory.getInstance());
  });
}
