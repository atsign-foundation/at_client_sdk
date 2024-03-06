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
    // await TestSuiteInitializer.getInstance()
    //     .testInitializer(thirdAtSign, namespace);
    // await TestSuiteInitializer.getInstance()
    //     .testInitializer(fourthAtSign, namespace);
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


}
