import 'dart:async';
import 'package:at_login_flutter/domain/at_login_model.dart';
import 'package:at_login_flutter/services/at_login_service.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:at_utils/at_logger.dart';

class AtLoginProvider extends ChangeNotifier {
  static final _singleton = AtLoginProvider._internal();
  AtLoginProvider._internal();

  var _logger = AtSignLogger('Connection Provider');

  factory AtLoginProvider() {
    return _singleton;
  }
  List<AtLoginObj>? atLoginList;
  Status? status;
  var error;
  String initialised = '';

  late AtLoginService _atLoginService;
  late bool _disposed;
  late ListStatus atLoginListStatus;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  init(String atsign) {
    if (atsign != initialised) {
      this.atLoginList = [];
      _atLoginService = AtLoginService();
      atLoginListStatus = ListStatus();
      _disposed = false;
      initialised = atsign;
    }
    this.setStatus(null);
  }

  setStatus(Status? value) {
    status = value;
    notifyListeners();
  }

  // setListStatus(bool isFollowing, bool value) {
  //   if (!isFollowing) {
  //     atLoginListStatus.isFollowersPrivate = value;
  //   } else {
  //     atLoginListStatus.isFollowingPrivate = value;
  //   }
  // }

  Future getAtsignsList({bool isFollowing = false}) async {
    Completer c = Completer();
    // bool isInit = status == null;
    try {
      setStatus(Status.loading);
      // await _atLoginService.getAtLoginJSON(isInit: isInit);
      setStatus(Status.done);
      c.complete(true);
    } on Error catch (err) {
      this.error = err;
      setStatus(Status.error);
    } on Exception catch (ex) {
      this.error = ex;
      setStatus(Status.error);
    }
    return c.future;
  }

  // Future changeListStatus(bool isFollowing, bool value) async {
  //   Completer c = Completer();
  //   try {
  //     setStatus(Status.loading);
  //     await _atLoginService.changeListPublicStatus(isFollowing, value);
  //     setListStatus(isFollowing, value);
  //     setStatus(Status.done);
  //     c.complete(true);
  //   } catch (ex) {
  //     this.error = ex;
  //     setStatus(Status.error);
  //   }
  //   return c.future;
  // }

  Future saveLoginResult(AtLoginObj atLoginObj) async {
    Completer c = Completer();
    try {
      setStatus(Status.loading);
      var success = await _atLoginService.putAtLoginObj(atLoginObj);
      if (success) {
        atLoginList!.add(atLoginObj);
      }
      setStatus(Status.done);
      c.complete(true);
    } on Error catch (err) {
      this.error = err;
      setStatus(Status.error);
    } on Exception catch (ex) {
      this.error = ex;
      setStatus(Status.error);
    }

    return c.future;
  }

  ///deletes [atsign] from followers and following list.
  Future delete(String key) async {
    Completer c = Completer();
    try {
      setStatus(Status.loading);
      var result = await _atLoginService.deleteAtLoginObj(key);
      if (result) {
        atLoginList!.removeWhere((element) => element.key == key);
      }
      setStatus(Status.done);
      c.complete(true);
    } catch (e) {
      _logger.severe('deleting $key throws $e');
      this.error = e;

      setStatus(Status.error);
    }
  }

  bool containsFollowing(String? requestorUrl) {
    var index = this
        .atLoginList!
        .indexWhere((data) => data.requestorUrl == requestorUrl);
    return index != -1;
  }

  ///Returns data with the title = [atsign] from either followers/following list based on [isFollowing].
  AtLoginObj? getData(bool allow, String? requestorUrl) {
    return this.atLoginList!.firstWhereOrNull(
          (data) =>
              data.requestorUrl == requestorUrl && data.allowLogin == allow,
        );
  }
}

enum Status { getData, loading, done, error }

class ListStatus {
  bool isFollowersPrivate = false;
  bool isFollowingPrivate = false;
}
