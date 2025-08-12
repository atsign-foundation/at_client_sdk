import 'dart:async';
import 'dart:core';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_location_flutter/common_components/build_marker.dart';
import 'package:at_location_flutter/common_components/custom_toast.dart';
import 'package:at_location_flutter/location_modal/hybrid_model.dart';
import 'package:at_location_flutter/service/master_location_service.dart';
import 'package:at_location_flutter/utils/constants/init_location_service.dart';
import 'package:geolocator/geolocator.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:latlong2/latlong.dart';

import 'at_location_notification_listener.dart';
import 'distance_calculate.dart';
import 'my_location.dart';
import 'package:at_utils/at_logger.dart';

class LocationService {
  LocationService._();

  static final LocationService _instance = LocationService._();

  factory LocationService() => _instance;

  final _logger = AtSignLogger('LocationService');

  List<String?>? atsignsToTrack;

  AtClientImpl? atClientInstance;

  HybridModel? centreMarker;
  HybridModel? myData;
  LatLng? etaFrom;
  String? textForCenter;
  bool? calculateETA, addCurrentUserMarker, isMapInitialized = false;
  Function? showToast;
  StreamSubscription<Position>? myLocationStream;
  DateTime? refreshAt;
  Future<dynamic>? refreshTimer;
  String? uniqueID; // used to differentiate between different calls

  String?
      notificationID; // needed to track details of a specific notification (event/p2p)

  List<HybridModel?> hybridUsersList = [];

  late StreamController _atHybridUsersController =
      StreamController<List<HybridModel?>>.broadcast();

  Stream<List<HybridModel?>> get atHybridUsersStream =>
      _atHybridUsersController.stream as Stream<List<HybridModel?>>;

  StreamSink<List<HybridModel?>> get atHybridUsersSink =>
      _atHybridUsersController.sink as StreamSink<List<HybridModel?>>;

  //// the centre LatLng is getting added more than once
  void init(
    List<String?>? atsignsToTrackFromApp, {
    LatLng? etaFrom,
    bool? calculateETA,
    bool? addCurrentUserMarker,
    String? textForCenter,
    Function? showToast,
    String? notificationID,
    DateTime? refreshAt,
  }) async {
    hybridUsersList = [];
    centreMarker = null;
    _atHybridUsersController = StreamController<List<HybridModel?>>.broadcast();
    atsignsToTrack = atsignsToTrackFromApp;
    this.etaFrom = etaFrom;
    this.calculateETA = calculateETA;
    this.addCurrentUserMarker = addCurrentUserMarker;
    this.textForCenter = textForCenter;
    this.showToast = showToast;
    this.notificationID = notificationID;
    this.refreshAt = refreshAt;

    // ignore: unawaited_futures
    if (myLocationStream != null) myLocationStream!.cancel();

    if (etaFrom != null) addCentreMarker();
    await addMyDetailsToHybridUsersList();

    updateHybridList();

    uniqueID = DateTime.now().millisecondsSinceEpoch.toString();
    refreshUpdateHybridList(uniqueID);
  }

  void dispose() {
    centreMarker = null;
    _atHybridUsersController.close();
    isMapInitialized = false;
    refreshTimer = null;
    uniqueID = null;
  }

  void mapInitialized() {
    isMapInitialized = true;
  }

  /// will call updateHybridList after [refreshAt] time
  refreshUpdateHybridList(String? _uniqueID) async {
    if ((refreshAt != null) && (refreshAt!.isAfter(DateTime.now()))) {
      refreshTimer =
          await Future.delayed(refreshAt!.difference(DateTime.now()));

      if (_uniqueID == uniqueID) {
        /// if disposed, [uniqueID] will be null
        updateHybridList();
      }
    }
  }

  /// Adds the current user's details to the hybridUsersList
  Future addMyDetailsToHybridUsersList() async {
    var permission = await Geolocator.checkPermission();
    if (((permission == LocationPermission.always) ||
        (permission == LocationPermission.whileInUse))) {
      var _atsign = AtLocationNotificationListener().currentAtSign;
      var mylatlng = await getMyLocation();
      var _image = await MasterLocationService().getImageOfAtsignNew(_atsign);

      var _myData = HybridModel(
          displayName: _atsign, latLng: mylatlng, eta: '?', image: _image);

      updateMyLatLng(_myData);

      myLocationStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(distanceFilter: 10))
          .listen((myLocation) async {
        var mylatlng = LatLng(myLocation.latitude, myLocation.longitude);

        _myData = HybridModel(
            displayName: _atsign, latLng: mylatlng, eta: '?', image: _image);

        updateMyLatLng(_myData);
      });
    } else {
      // ignore: unnecessary_null_comparison
      if (AtLocationNotificationListener().navKey != null) {
        CustomToast().show('Location permission not granted',
            AtLocationNotificationListener().navKey.currentContext!,
            isError: true);
      }
    }
  }

  /// Updates the current user's latitude and longitude
  void updateMyLatLng(HybridModel _myData) async {
    if (etaFrom != null) {
      _myData.eta = await _calculateEta(_myData);
    }

    _myData.marker = buildMarker(_myData, singleMarker: true);

    myData = _myData;

    var _index = hybridUsersList.indexWhere((element) =>
        element!.displayName == AtLocationNotificationListener().currentAtSign);

    if (_index < 0) {
      if (addCurrentUserMarker!) {
        hybridUsersList.add(myData);
      }
    } else {
      hybridUsersList[_index] = myData;
    }

    if (!_atHybridUsersController.isClosed) {
      _atHybridUsersController.add(hybridUsersList);
    }
  }

  /// Adds a centre marker to the hybridUsersList
  void addCentreMarker() {
    centreMarker = HybridModel(
        displayName: textForCenter, latLng: etaFrom, eta: '', image: null);
    centreMarker!.marker = buildMarker(centreMarker!);
    hybridUsersList.add(centreMarker);

    if (hybridUsersList.isNotEmpty) {
      if (!_atHybridUsersController.isClosed) {
        _atHybridUsersController.add(hybridUsersList);
      }
    }
  }

  /// called for the first time pckage is entered from main app
  void updateHybridList() async {
    await Future.forEach(atsignsToTrack ?? [], (dynamic _atsign) async {
      var _user =
          MasterLocationService().getHybridModel(_atsign, id: notificationID);
      if (_user != null) {
        await updateDetails(_user);
      }
    });

    if (hybridUsersList.isNotEmpty) {
      if (!_atHybridUsersController.isClosed) {
        _atHybridUsersController.add(hybridUsersList);
      }
    }
  }

  /// called when any new/updated data is received in the main app
  void newList(String _updatedAtsign) async {
    if ((atsignsToTrack != null) &&
        ((atsignsToTrack ?? []).contains(_updatedAtsign))) {
      var _user = MasterLocationService()
          .getHybridModel(_updatedAtsign, id: notificationID);
      if (_user != null) {
        await updateDetails(_user);
      } else {
        removeUser(_updatedAtsign);
      }

      if (!_atHybridUsersController.isClosed) {
        _atHybridUsersController.add(hybridUsersList);
      }
    }
  }

  /// called when a user stops sharing his location
  void removeUser(String? atsign) {
    if ((atsignsToTrack != null) && (hybridUsersList.isNotEmpty)) {
      hybridUsersList.removeWhere(
          (element) => compareAtSign(element!.displayName!, atsign!));
      if (!_atHybridUsersController.isClosed) {
        _atHybridUsersController.add(hybridUsersList);
      }
    }
  }

  /// called to get the new details marker & eta
  Future<void> updateDetails(HybridModel user) async {
    var contains = false;
    int? index;
    for (var hybridUser in hybridUsersList) {
      if (hybridUser!.displayName == user.displayName) {
        contains = true;
        index = hybridUsersList.indexOf(hybridUser);
      }
    }
    if (user.latLng == null) {
      _logger.finer('${user.displayName} user.latLng = null');
      return;
    }

    if (contains) {
      await addDetails(user, index: index);
    } else {
      await addDetails(user);
    }
  }

  /// returns new marker and eta
  Future<void> addDetails(HybridModel user, {int? index}) async {
    try {
      user.marker = buildMarker(user);
      var _eta = await _calculateEta(user);
      user.eta = _eta;
      if ((index != null)) {
        if ((index < hybridUsersList.length)) hybridUsersList[index] = user;
      } else {
        var _continue = true;
        for (var hybridUser in hybridUsersList) {
          if (hybridUser!.displayName == user.displayName) {
            hybridUser = user;
            _continue = false;
            return;
          }
        }
        if (_continue) {
          hybridUsersList.add(user);
        }
      }
    } catch (e) {
      _logger.severe(e);
      if (showToast != null) showToast!('Something went wrong', isError: true);
    }
  }

  Future<String> _calculateEta(HybridModel user) async {
    if (calculateETA!) {
      try {
        // ignore: prefer_typing_uninitialized_variables
        var _res;
        if (etaFrom != null) {
          _res = await DistanceCalculate().calculateETA(etaFrom!, user.latLng!);
        } else {
          LatLng? mylatlng;
          if (myData != null) {
            mylatlng = myData!.latLng;
          } else {
            mylatlng = await getMyLocation();
          }
          _res =
              await DistanceCalculate().calculateETA(mylatlng!, user.latLng!);
        }

        return _res;
      } catch (e) {
        _logger.severe('Error in _calculateEta $e');
        return '?';
      }
    } else {
      return '?';
    }
  }

  void notifyListeners() {
    if (hybridUsersList.isNotEmpty) {
      _atHybridUsersController.add(hybridUsersList);
    }
  }
}
