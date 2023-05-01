import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_collection/collection_util.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

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

class Preference extends AtCollectionModel{
  Map<String, dynamic>? preference;

  Preference();

  Preference.from(String id, this.preference) {
    this.id = id;
    namespace = 'pref';
  }

  @override
  fromJson(String jsonObject) {
    var json = jsonDecode(jsonObject);
    preference = json;
  }

  @override
  Map<String, dynamic> toJson() {
    var data = <String, dynamic>{};
    final preference = this.preference;
    if(preference != null) {
      for(String key in preference.keys) {
        data[key] = preference[key];
      }
    }


    return data;
  }
}

class Contact extends AtCollectionModel{
  String? atSign;
  String? nickname;

  Contact();

  Contact.from(String id, this.atSign, this.nickname) {
    this.id = id;
    namespace = 'contact';
  }

  @override
  fromJson(String jsonObject) {
    var json = jsonDecode(jsonObject);
    atSign = json['atSign'];
    nickname = json['nickname'];
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

  Phone();

  Phone.from(String id, {this.phoneNumber}) {
    this.id = id;
    namespace = 'buzz';
  }

  @override
  void fromJson(String jsonEncoded) {
    var json = jsonDecode(jsonEncoded);
    phoneNumber = json['phoneNumber'];
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

  A.from(String id, {String? a}) {
    this.id = id;
    a = a;
    namespace = 'buzz';
  }

  @override
  void fromJson(String jsonEncoded) {
    var json = jsonDecode(jsonEncoded);
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

  B.from(String id, {String? b}) {
    this.id = id;
    b = b;
    namespace = 'buzz';
  }

  @override
  void fromJson(String jsonEncoded) {
    var json = jsonDecode(jsonEncoded);
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
  // AtSignLogger.root_level = 'FINER';

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

  test('Share a key to sharedWith atSign and lookup from sharedWith atSign',
      () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var phone = Phone.from('personal phone', phoneNumber: '12345');
    var shareRes = await phone.share([secondAtSign]);

    expect(shareRes, true);

    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

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

    var regex = CollectionUtil.makeRegex(
        formattedId: 'personal-phone', collectionName: 'phone', namespace: 'buzz');

    var getResult =
        await sharedWithAtClientManager.atClient.getKeys(regex: regex);
    expect(getResult.length, 1);
  }, timeout: Timeout(Duration(minutes: 5)));

  test('fetching self key using getById and getAll static methods', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    await Phone.from('new personal Phone', phoneNumber: '123456789').save();
    await Phone.from('Office Phone', phoneNumber: '9999').save();

    //AtCollectionModelFactoryManager.getInstance().register(PhoneFactory());

    var personalPhoneLoaded = await AtCollectionModel.getModelById<Phone>(
      'new personal Phone',
      'buzz'
    );

   // expect(personalPhoneLoaded.phoneNumber, '123456789');

   // var officePhoneLoaded = await AtCollectionModel.getModelById<Phone>(
      //'Office Phone',
    //);
    //expect(officePhoneLoaded.phoneNumber, '9999');

    //var phones = await AtCollectionModel.getModelsByCollectionName<Phone>();

    //print('phones.length : ${phones.length}');
    //expect(phones.length, 3);
    // for (var phone in phones) {
    //   print(
    //       'phone : ${phone.phoneNumber}, id : ${phone.id}, collectionName : ${phone.collectionName}');
    // }
  }, timeout: Timeout(Duration(minutes: 5)));

  test('save and incremental share', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var fourthPhone = Phone.from('fourth phone', phoneNumber: '4444');
    AtCollectionModelFactoryManager.getInstance().register(PhoneFactory());

    await fourthPhone.save();
    await fourthPhone.share([secondAtSign]);
    expect(await fourthPhone.getSharedWith(), ['@ce2e2']);
    await fourthPhone.share([thirdAtSign]);
    expect(await fourthPhone.getSharedWith(), ['@ce2e2', '@ce2e3']);
    await fourthPhone.share([fourthAtSign]);
    expect(await fourthPhone.getSharedWith(), ['@ce2e2', '@ce2e3', '@ce2e4']);

    // Unshare now
    await fourthPhone.unshare(atSigns: [thirdAtSign, fourthAtSign]);
    expect(await fourthPhone.getSharedWith(), ['@ce2e2']);

    await fourthPhone.unshare(atSigns: [secondAtSign]);
    await fourthPhone.delete();
    expect(await fourthPhone.getSharedWith(), []);
    expect(
      () async => await AtCollectionModel.getModelById<Phone>(
        'fourth phone',
         'buzz'
      ),
      throwsA(isA<Exception>()),
    );
  }, timeout: Timeout(Duration(minutes: 5)));

  test(
    'save and incremental share with stream',
    () async {
      // Setting firstAtSign atClient instance to context.
      currentAtClientManager =
          await AtClientManager.getInstance().setCurrentAtSign(
        firstAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(firstAtSign),
      );

      AtCollectionModelFactoryManager.getInstance().register(PhoneFactory());

      var fifthPhone = Phone.from('fifth phone', phoneNumber: '55555');
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

      expect(await fifthPhone.getSharedWith(), []);

      expect(
        () async => await AtCollectionModel.getModelById<Phone>(
          'fifth phone',
          'buzz'
        ),
        throwsA(isA<Exception>()),
      );
    },
    timeout: Timeout(Duration(minutes: 5)),
  );

  test('test getModelsSharedWith method', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var a = A.from('a1', a: 'a1 value');
    var shareRes = await a.share([secondAtSign]);

    var b = B.from('b1', b: 'b1 value');
    await b.share([secondAtSign]);

    AtCollectionModelFactoryManager.getInstance().register(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance().register(BFactory.getInstance());


    expect(shareRes, true);

    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    var res = await AtCollectionModel.getModelsSharedWith(secondAtSign);
    print(res);

    for (var model in res) {
      print(model.toJson());
    }

    expect(res.isEmpty, false);
  }, timeout: Timeout(Duration(minutes: 10)));

  test('test getModelsSharedBy method', () async {
    // Setting firstAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
    );

    var a = A.from('a1', a: 'a1 value');
    var shareRes = await a.share([secondAtSign]);

    var b = B.from('b1', b: 'b1 value');
    await b.share([secondAtSign]);

    expect(shareRes, true);

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

    AtCollectionModelFactoryManager.getInstance().register(AFactory.getInstance());
    AtCollectionModelFactoryManager.getInstance().register(BFactory.getInstance());

    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    var res = await AtCollectionModel.getModelsSharedBy(firstAtSign);
    for (var model in res) {
      print(model.toJson());
    }

    expect(res.isEmpty, false);
  }, timeout: Timeout(Duration(minutes: 10)));

  test('Test retreival of shared models with factories', () async {
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
    var preference = Preference.from('pizza preference', pizzaPreferences);
    var shareRes = await preference.share([secondAtSign]);

    var contact = Contact.from('jagan', '@jagan', 'jagan');
    shareRes = await contact.share([secondAtSign]);

    var phone = Phone.from('my another phone', phoneNumber:'1122');
    shareRes = await phone.share([secondAtSign]);



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

    //AtCollectionModelFactoryManager.getInstance().register(PreferenceFactory.getInstance());
   // AtCollectionModelFactoryManager.getInstance().register(ContactFactory.getInstance());
    //AtCollectionModelFactoryManager.getInstance().register(PhoneFactory());

    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    var res = await AtCollectionModel.getModelsSharedBy(firstAtSign);

    for (var model in res) {
      print(model.runtimeType);
      print(model.toJson());
    }

    expect(res.isEmpty, false);
  }, timeout: Timeout(Duration(minutes: 10)));
}
