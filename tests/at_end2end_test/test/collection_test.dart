import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

class Phone extends AtCollectionModel {
  String? phoneNumber;

  Phone();

  Phone.from(String id, {String? phoneNumber}) {
    this.id = id;
    this.phoneNumber = phoneNumber;
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
}

void main() async {
  late AtClientManager currentAtClientManager;
  late AtClientManager sharedWithAtClientManager;
  late String currentAtSign;
  late String sharedWithAtSign, thirdAtSign, fourthAtSign;
  final namespace = 'wavi';
  // AtSignLogger.root_level = 'FINER';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    thirdAtSign = ConfigUtil.getYaml()['atSign']['thirdAtSign'];
    fourthAtSign = ConfigUtil.getYaml()['atSign']['fourthAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(thirdAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(fourthAtSign, namespace);
  });

  test('Share a key to sharedWith atSign and lookup from sharedWith atSign',
      () async {
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(currentAtSign),
    );

    var phone = Phone.from('personal phone', phoneNumber: '12345');
    var shareRes = await phone.share([sharedWithAtSign]);

    expect(shareRes, true);

    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    /// receiver's end
    sharedWithAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      sharedWithAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(sharedWithAtSign),
    );

    await E2ESyncService.getInstance().syncData(
      sharedWithAtClientManager.atClient.syncService,
    );

    var getResult = await sharedWithAtClientManager.atClient
        .getKeys(regex: 'personal-phone.phone');
    expect(getResult.length, 1);
  }, timeout: Timeout(Duration(minutes: 5)));

  test('fetching self key using getById and getAll static methods', () async {
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(currentAtSign),
    );

    await Phone.from('new personal Phone', phoneNumber: '123456789').save();
    await Phone.from('Office Phone', phoneNumber: '9999').save();

    var personalPhoneLoaded = await AtCollectionModel.getById<Phone>(
        'new personal Phone',
        collectionModelFactory: PhoneFactory());

    expect(personalPhoneLoaded.phoneNumber, '123456789');

    var officePhoneLoaded = await AtCollectionModel.getById<Phone>(
        'Office Phone',
        collectionModelFactory: PhoneFactory());
    expect(officePhoneLoaded.phoneNumber, '9999');

    var phones = await AtCollectionModel.getAll<Phone>(
        collectionModelFactory: PhoneFactory());

    print('phones.length : ${phones.length}');
    expect(phones.length, 3);
    // for (var phone in phones) {
    //   print(
    //       'phone : ${phone.phoneNumber}, id : ${phone.id}, collectionName : ${phone.collectionName}');
    // }
  }, timeout: Timeout(Duration(minutes: 5)));

  test('save and incremental share', () async {
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(currentAtSign),
    );

    var fourthPhone = Phone.from('fourth phone', phoneNumber: '4444');
    await fourthPhone.save();
    await fourthPhone.share([sharedWithAtSign]);
    expect(await fourthPhone.getSharedWith(), ['@0living']);
    await fourthPhone.share([thirdAtSign]);
    expect(await fourthPhone.getSharedWith(),
        ['@0living', '@significantredpanda']);
    await fourthPhone.share([fourthAtSign]);
    expect(await fourthPhone.getSharedWith(),
        ['@0living', '@51alooant55', '@significantredpanda']);

    // Unshare now
    await fourthPhone.unshare(atSigns: [thirdAtSign, fourthAtSign]);
    expect(await fourthPhone.getSharedWith(), ['@0living']);

    await fourthPhone.delete();
    expect(await fourthPhone.getSharedWith(), []);
    expect(
      () async => await AtCollectionModel.getById<Phone>('fourth phone',
          collectionModelFactory: PhoneFactory()),
      throwsA(isA<Exception>()),
    );
  }, timeout: Timeout(Duration(minutes: 5)));

  test(
    'save and incremental share with stream',
    () async {
      // Setting currentAtSign atClient instance to context.
      currentAtClientManager =
          await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(currentAtSign),
      );

      var fifthPhone = Phone.from('fifth phone', phoneNumber: '55555');
      await fifthPhone.streams.save().forEach(
        (AtOperationItemStatus element) {
          expect(element.complete, true);
          expect(element.key, 'fifth-phone.phone');
          expect(element.atSign, currentAtSign);
          expect(element.operation, Operation.save);
        },
      );

      await fifthPhone.streams.share([sharedWithAtSign]).forEach(
        (AtOperationItemStatus element) {
          expect(element.complete, true);
          expect(element.key, 'fifth-phone.phone');
        },
      );

      print(await fifthPhone.getSharedWith());

      await fifthPhone.streams.share([thirdAtSign]).forEach(
        (AtOperationItemStatus element) {
          expect(element.complete, true);
          expect(element.key, 'fifth-phone.phone');
        },
      );

      print(await fifthPhone.getSharedWith());

      await fifthPhone.streams.share([fourthAtSign]).forEach(
        (AtOperationItemStatus element) {
          expect(element.complete, true);
          expect(element.key, 'fifth-phone.phone');
        },
      );

      print(await fifthPhone.getSharedWith());

      // Unshare now
      await fifthPhone.streams
          .unshare(atSigns: [thirdAtSign, fourthAtSign]).forEach(
        (AtOperationItemStatus element) {
          expect(element.complete, true);
          expect(element.key, 'fifth-phone.phone');
        },
      );

      await fifthPhone.streams.delete().forEach(
        (AtOperationItemStatus element) {
          expect(element.complete, true);
          expect(element.key, 'fifth-phone.phone');
        },
      );

      expect(await fifthPhone.getSharedWith(), []);

      expect(
        () async => await AtCollectionModel.getById<Phone>('fifth phone',
            collectionModelFactory: PhoneFactory()),
        throwsA(isA<Exception>()),
      );
    },
    timeout: Timeout(Duration(minutes: 5)),
  );
}
