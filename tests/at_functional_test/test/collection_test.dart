import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

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

void main() {
  late AtClientManager atClientManager;
  late String currentAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(currentAtSign, namespace);
    atClientManager.atClient.syncService.sync();
  });

  test('Model operations - save() test', () async {
    // Setting firstAtSign atClient instance to context.

    // Save a photo
    var phone = Phone()
      ..id = 'personal phone'
      ..namespace = 'buzz'
      ..collectionName = 'phone'
      ..phoneNumber = '12345';
    var shareRes = await phone.save();
    expect(shareRes, true);
  });

  test('Query method - AtCollectionModel.getModel() test', () async {
    // Setting firstAtSign atClient instance to context.
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
}

