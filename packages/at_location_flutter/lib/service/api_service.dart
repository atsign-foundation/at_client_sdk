import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  /// Sends a GET request to the specified URL and returns the response
  Future<dynamic> getRequest(String url, [Map<String, String>? header]) async {
    var val = await ConnectivityService().checkConnectivity();
    if (val) {
      return http
          .get(Uri.parse(url), headers: header)
          .then((http.Response response) {
        final statusCode = response.statusCode;
        if (statusCode == 200) {
          return {
            'status': true,
            'body': utf8.decode(response.bodyBytes),
            'message': 'success',
            'header': response.headers,
            'code': statusCode,
          };
        } else {
          return {
            'status': false,
            'body': response.body,
            'message': (response.statusCode == 404)
                ? 'Page not Found'
                : (response.statusCode == 401)
                    ? 'Unauthorized'
                    : 'Error occured while Fetching Data',
            'header': response.headers,
            'code': statusCode,
          };
        }
      });
    } else {
      return {
        'status': false,
        'message': 'No Internet',
      };
    }
  }

  /// Sends a POST request to the specified URL and returns the response
  Future<dynamic> postRequest(String url,
      {Map<String, String>? headers, body, encoding}) async {
    var val = await ConnectivityService().checkConnectivity();
    if (val) {
      return http
          .post(Uri.parse(url),
              body: json.encode(body), headers: headers, encoding: encoding)
          .then((http.Response response) {
        final statusCode = response.statusCode;
        if (statusCode == 200) {
          return {
            'status': true,
            'body': utf8.decode(response.bodyBytes),
            'message': 'success',
            'header': response.headers,
            'code': statusCode,
          };
        } else if (statusCode == 201) {
          return {
            'status': true,
            'body': response.body,
            'message': 'created',
            'header': response.headers,
            'code': statusCode,
          };
        } else {
          return {
            'status': false,
            'body': response.body,
            'message': (response.statusCode == 404)
                ? 'Page not Found'
                : (response.statusCode == 401)
                    ? 'Unauthorized'
                    : 'Error occured while Fetching Data',
            'header': response.headers,
            'code': statusCode,
          };
        }
      });
    } else {
      return {
        'status': false,
        'message': 'No Internet',
      };
    }
  }
}

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService _instance = ConnectivityService._();

  factory ConnectivityService() => _instance;

  /// Checks the internet connectivity by attempting to establish a connection to a specified host
  Future<bool> checkConnectivity() async {
    Socket? socket;
    bool connectivity;
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      socket = await Socket.connect('google.com', 80,
          timeout: const Duration(seconds: 4));
      connectivity = true;
    } catch (e) {
      checkInternetConnection();
      connectivity = false;
    } finally {
      try {
        await socket?.close();
      } catch (e) {
        // ignore: avoid_print
        print(e);
      }
    }
    return connectivity;
  }

  void checkInternetConnection() {}
}
