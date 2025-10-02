import 'dart:convert';

import 'package:http/http.dart' as http;

abstract class SecondaryAddressFinder {
  Future<SecondaryAddress> findSecondary(String atSign);
}

class SecondaryAddress {
  final String host;
  final int port;

  SecondaryAddress(this.host, this.port);

  @override
  String toString() {
    return '$host:$port';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecondaryAddress &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port;

  @override
  int get hashCode => Object.hash(host, port);
}

class Proxies {
  static Proxies fromJson(Map<String, dynamic> json) {
    List<SecondaryAddress> addresses = [];
    final l = json['proxies'] as List;
    for (final m in l) {
      addresses.add(SecondaryAddress(m['host'], m['port']));
    }
    return Proxies(addresses);
  }

  static Future<Proxies> fetchFromUri(Uri uri) async {
    final client = http.Client();
    final p = fromJson(jsonDecode(await client.read(uri)));
    client.close();
    return p;
  }

  final List<SecondaryAddress> addresses;

  Proxies(this.addresses) {
    if (addresses.isEmpty) {
      throw ArgumentError('Need at least one proxy');
    }
  }

  int _ix = 0;

  /// round robin
  SecondaryAddress next() {
    final sa = addresses[_ix];
    _ix = (_ix + 1) % addresses.length;
    return sa;
  }

  @override
  String toString() {
    return 'Proxies{addresses: $addresses}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Proxies &&
          runtimeType == other.runtimeType &&
          addresses == other.addresses;

  @override
  int get hashCode => addresses.hashCode;
}
