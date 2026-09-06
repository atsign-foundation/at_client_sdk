/// The HTTP status codes [AtStatus.httpStatus] reports, as plain ints.
///
/// Deliberately not `dart:io`'s `HttpStatus`: naming that type put `dart:io`
/// into at_server_status's import graph for the sake of five integer
/// constants, which is the one thing that kept this package off a web build
/// graph. The values are identical.
const _httpOk = 200;
const _httpFound = 302;
const _httpNotFound = 404;
const _httpInternalServerError = 500;
const _httpServiceUnavailable = 503;

/// The AtStatus model includes five parameters
///   String atSign;
///   String serverLocation;
///   RootStatus rootStatus;
///   ServerStatus serverStatus;
///   AtSignStatus atSignStatus;
///
/// It also provides the following convenience methods
/// status() returns an enumerated AtSignStatus value of the overall status of an @sign
/// httpStatus() returns an integer HttpStatus code of the overall status of an @sign
/// toJson() returns a `Map<String, dynamic>` representation of an AtStatus object
/// fromJson(Map json) returns an AtStatus object from a JSON Map
/// toString() returns a String representation of an AtStatus object
///
/// The AtSignStatus values returned by status() and their meanings are:
///
/// AtSignStatus.notFound
/// The @server has no root location
///
/// AtSignStatus.ready
/// The @server has root location, is running and ready for activation
///
/// AtSignStatus.teapot
/// @server has root location, is running but is not activated
///
/// AtSignStatus.activated
/// @server has root location, is running and is activated
///
/// AtSignStatus.unavailable:
/// Either the @root or @server is not currently available
///
/// AtSignStatus.error
/// There was an error encountered by this library
///
/// The HttpStatus codes returned by httpStatus() and their meanings are:
///
/// static const int notFound = 404
/// Not Found(404) @server has no root location, is not running and is not activated
///
/// static const int serviceUnavailable = 503
/// Service Unavailable(503) @server has root location, is not running and is not activated
///
/// int 418
/// I'm a teapot(418) @server has root location, is running and but not activated
///
/// static const int ok = 200
/// OK (200) @server has root location, is running and is activated
///
/// static const int internalServerError = 500
/// Internal Server Error(500) at_find_api internal error
///
/// static const int badGateway = 502
/// Bad Gateway(502) @root server is down
///

class AtStatus {
  String? atSign;

  String? serverLocation;

  RootStatus? rootStatus;

  ServerStatus? serverStatus;

  AtSignStatus? atSignStatus;

  AtStatus(
      {this.atSign,
      this.serverLocation,
      this.rootStatus,
      this.serverStatus,
      this.atSignStatus}) {
    rootStatus ??= RootStatus.unavailable;
    serverStatus ??= ServerStatus.unavailable;
    atSignStatus ??= AtSignStatus.unavailable;
  }

  AtSignStatus? status() {
    AtSignStatus? status;
    // enum RootStatus { found, notFound, running, stopped, unavailable }
    // @server has no root location
    if (rootStatus == RootStatus.notFound) {
      status = AtSignStatus.notFound;
    } else if (rootStatus == RootStatus.found) {
      // enum ServerStatus { notFound, ready, teapot, activated, stopped, unavailable, error }
      if (serverStatus == ServerStatus.activated) {
        status = AtSignStatus.activated;
      } else if (serverStatus == ServerStatus.ready ||
          serverStatus == ServerStatus.teapot) {
        status = AtSignStatus.teapot;
      }
    }
    // service is not available
    else if (rootStatus == RootStatus.unavailable ||
        rootStatus == RootStatus.stopped ||
        serverStatus == ServerStatus.stopped ||
        serverStatus == ServerStatus.unavailable) {
      status = AtSignStatus.unavailable;
    }
    // @root is stopped

    else if (serverStatus == ServerStatus.unavailable) {}

    return status;
  }

  int httpStatus() {
    int status;
    if (rootStatus == RootStatus.found) {
      status = _serverHttpStatus();
    } else {
      status = _rootHttpStatus();
    }
    return status;
  }

  int _rootHttpStatus() {
    int status;
    if (rootStatus == RootStatus.found) {
      status = _httpFound;
    } else if (rootStatus == RootStatus.notFound) {
      status = _httpNotFound;
    } else if (rootStatus == RootStatus.stopped) {
      status = _httpServiceUnavailable;
    } else if (rootStatus == RootStatus.unavailable) {
      status = _httpServiceUnavailable;
    } else {
      status = _httpInternalServerError;
    }
    return status;
  }

  int _serverHttpStatus() {
    int status;
    if (serverStatus == ServerStatus.teapot) {
      status = 418;
    } else if (serverStatus == ServerStatus.stopped ||
        serverStatus == ServerStatus.unavailable) {
      status = _httpServiceUnavailable;
    } else if (serverStatus == ServerStatus.ready) {
      status = _httpServiceUnavailable;
    } else if (serverStatus == ServerStatus.activated) {
      status = _httpOk;
    } else {
      status = _httpInternalServerError;
    }
    return status;
  }

  Map<String, dynamic> toJson() {
    return {
      'atSign': atSign,
      'rootStatus': rootStatus,
      'serverStatus': serverStatus,
      'serverLocation': serverLocation.toString(),
      'status': status,
    };
  }

  AtStatus.fromJson(Map json) {
    atSign = json['atSign'];
    rootStatus = json['rootStatus'];
    serverStatus = json['serverStatus'];
    serverLocation = json['serverLocation'];
  }

  @override
  String toString() {
    return 'AtStatus{atSign:$atSign, rootStatus:$rootStatus, serverLocation:$serverLocation, serverStatus:$serverStatus}';
  }
}

enum AtSignStatus { notFound, teapot, activated, unavailable, error }

enum RootStatus { found, notFound, stopped, unavailable, error }

enum ServerStatus { ready, teapot, activated, stopped, unavailable, error }
