import 'package:at_contact/at_contact.dart';
import 'package:at_location_flutter/location_modal/hybrid_model.dart';
import 'package:at_location_flutter/location_modal/key_location_model.dart';
import 'package:at_location_flutter/location_modal/location_notification.dart';
import 'package:at_location_flutter/service/at_location_notification_listener.dart';
import 'package:at_location_flutter/service/contact_service.dart';
import 'package:at_location_flutter/service/home_screen_service.dart';
import 'package:at_location_flutter/service/key_stream_service.dart';
import 'package:at_location_flutter/service/location_service.dart';
import 'package:at_location_flutter/service/my_location.dart';
import 'package:at_location_flutter/service/request_location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

Position get mockPosition => Position(
      latitude: 52.561270,
      longitude: 5.639382,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        500,
        isUtc: true,
      ),
      altitude: 3000.0,
      accuracy: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );

class MockAtContactImpl extends Mock implements AtContactsImpl {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GeolocatorPlatform.instance = MockGeolocatorPlatform();
  });

  test("get_my_location", () async {
    var res = await getMyLocation();
    expect(res, isA<LatLng>());
  });

  test("is_location_enabled", () async {
    var res = await isLocationServiceEnabled();
    expect(res, true);
  });

  test("update_my_latlng", () async {
    LocationService().hybridUsersList = [];
    var pos = await getMyLocation();
    LocationService().addCurrentUserMarker = true;
    var _myData = HybridModel(displayName: "45expected", latLng: pos, eta: '?');
    LocationService().updateMyLatLng(_myData);
    expect(LocationService().hybridUsersList.length, 1);
  });

  test("add_my_details_to_hybrid_users_list", () async {
    LocationService().hybridUsersList = [];
    LocationService().addCurrentUserMarker = true;
    when((() => GeolocatorPlatform.instance.getPositionStream(
            locationSettings: const LocationSettings(distanceFilter: 10))))
        .thenAnswer((invocation) => Stream.value(mockPosition));
    await LocationService().addMyDetailsToHybridUsersList();
    expect(LocationService().hybridUsersList.length, 1);
  });

  test("add_center_marker", () async {
    LocationService().hybridUsersList = [];
    LocationService().textForCenter = "";
    var pos = await getMyLocation();
    LocationService().etaFrom = pos;
    LocationService().addCentreMarker();
    expect(LocationService().hybridUsersList.length, 1);
  });

  test("add_details", () async {
    var pos = await getMyLocation();
    var hybridModel =
        HybridModel(displayName: "45expected", latLng: pos, eta: '?');
    var hybridModel2 =
        HybridModel(displayName: "83apedistinct", latLng: pos, eta: '?');
    LocationService().hybridUsersList = [hybridModel2];
    await LocationService().addDetails(hybridModel);
    expect(LocationService().hybridUsersList.length, 1);
  });

  test("get_cached_contact_detail", () async {
    var atSign = "@83apedistinct";
    KeyStreamService().contactList = [AtContact(atSign: atSign)];
    var res = getCachedContactDetail(atSign);
    expect(res?.atSign, atSign);
  });

  test("get_key_type", () async {
    var res = AtLocationNotificationListener().getKeyType("sharelocation");
    expect(res, "Share location");
  });

  test("get_subtitle", () async {
    LocationNotificationModel locationModel = LocationNotificationModel(
      to: DateTime(2023, 1, 12),
      key: "sharelocation",
      atsignCreator: "@83apedistinct",
      isAccepted: true,
    );
    AtLocationNotificationListener().currentAtSign = "@83apedistinct";
    var res = getSubTitle(locationModel);
    expect(res, "Can see my location until 0: 00 today");
  });

  test("get_semititle", () async {
    LocationNotificationModel locationModel = LocationNotificationModel(
        to: DateTime(2023, 1, 12),
        key: "sharelocation",
        atsignCreator: "@83apedistinct",
        isAccepted: false,
        isExited: false);
    AtLocationNotificationListener().currentAtSign = "@83apedistinct";
    var res = getSemiTitle(locationModel, true);
    expect(res, "Awaiting response");
  });

  test("get_title", () async {
    LocationNotificationModel locationModel = LocationNotificationModel(
        to: DateTime(2023, 1, 12),
        key: "sharelocation",
        atsignCreator: "@83apedistinct",
        isAccepted: false,
        isExited: false,
        receiver: "@45expected");
    AtLocationNotificationListener().currentAtSign = "@83apedistinct";

    var res = getTitle(locationModel);
    expect(res, "@45expected");
  });

  test("calculate_show_retry", () async {
    LocationNotificationModel locationModel = LocationNotificationModel(
      to: DateTime(2023, 1, 12),
      key: "sharelocation",
      atsignCreator: "@83apedistinct",
      isAccepted: false,
      isExited: false,
      receiver: "@45expected",
    );

    KeyLocationModel keyLocationModel = KeyLocationModel(
      locationNotificationModel: locationModel,
      haveResponded: true,
    );
    AtLocationNotificationListener().currentAtSign = "@45expected";

    var res = calculateShowRetry(keyLocationModel);
    expect(res, true);
  });

  test("time_of_day_to_string", () async {
    TimeOfDay time = const TimeOfDay(hour: 12, minute: 30);
    var res = timeOfDayToString(time);
    expect(res, "12: 30");
  });

  test("check_for_already_existing", () async {
    LocationNotificationModel locationModel = LocationNotificationModel(
      to: DateTime(2023, 1, 12),
      key: "requestlocation",
      atsignCreator: "@83apedistinct",
      isAccepted: false,
      isExited: false,
      receiver: "@45expected",
    );

    KeyLocationModel keyLocationModel = KeyLocationModel(
      locationNotificationModel: locationModel,
      haveResponded: true,
    );

    KeyStreamService().allLocationNotifications = [keyLocationModel];

    var res =
        RequestLocationService().checkForAlreadyExisting("@83apedistinct");
    expect(res[0], true);
  });

  test("check_for_already_existing_share_location", () async {
    LocationNotificationModel locationModel = LocationNotificationModel(
      to: DateTime(2023, 1, 12),
      key: "sharelocation",
      atsignCreator: "@83apedistinct",
      isAccepted: false,
      isExited: false,
      receiver: "@45expected",
    );

    KeyLocationModel keyLocationModel = KeyLocationModel(
      locationNotificationModel: locationModel,
      haveResponded: true,
    );

    KeyStreamService().allLocationNotifications = [keyLocationModel];

    var res = RequestLocationService()
        .checkForAlreadyExistingShareLocation("@83apedistinct");
    expect(res[0], true);
  });
}

class MockGeolocatorPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() =>
      Future.value(LocationPermission.whileInUse);

  @override
  Future<bool> isLocationServiceEnabled() => Future.value(true);

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) =>
      Future.value(mockPosition);

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    return super.noSuchMethod(
      Invocation.method(
        #getPositionStream,
        null,
        <Symbol, Object?>{
          #desiredAccuracy: locationSettings?.accuracy ?? LocationAccuracy.best,
          #distanceFilter: locationSettings?.distanceFilter ?? 0,
          #timeLimit: locationSettings?.timeLimit ?? 0,
        },
      ),
      // returnValue: Stream.value(mockPosition),
    );
  }
}
