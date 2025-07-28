import 'dart:async';
import 'dart:io';

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/rpc/at_rpc.dart' show AtRpc, AtRpcCallbacks;
import 'package:at_client/src/rpc/at_rpc_types.dart';
import 'package:at_client/src/util/controlled_stream_mixin.dart'
    show ControlledStream;

class AtRpcHttpServer
    with ControlledStream<HttpRequest>
    implements AtRpcCallbacks {
  late final AtRpc _rpc;

  AtRpcHttpServer({
    required AtClient atClient,
    required String baseNameSpace,
    String rpcsNameSpace = '__rpcs',
    required String domainNameSpace,
    required Set<String> allowList,
    bool allowAll = false,
  }) {
    _rpc = AtRpc(
      atClient: atClient,
      baseNameSpace: baseNameSpace,
      rpcsNameSpace: rpcsNameSpace,
      domainNameSpace: domainNameSpace,
      callbacks: this,
      allowList: allowList,
      allowAll: allowAll,
      isClient: false,
      isServer: true,
    );
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) {
    // TODO: implement handleRequest
    throw UnimplementedError();
  }

  @override
  Future<void> handleResponse(AtRpcResp response) {
    // TODO: implement handleResponse
    throw UnimplementedError();
  }
}

class AtRpcHttpClient implements HttpClient {
  // Http Interface
  @override
  bool autoUncompress;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout;

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  void addCredentials(
      Uri url, String realm, HttpClientCredentials credentials) {
    // TODO: implement addCredentials
  }

  @override
  void addProxyCredentials(
      String host, int port, String realm, HttpClientCredentials credentials) {
    // TODO: implement addProxyCredentials
  }

  @override
  set authenticate(
      Future<bool> Function(Uri url, String scheme, String? realm)? f) {
    // TODO: implement authenticate
  }

  @override
  set authenticateProxy(
      Future<bool> Function(
              String host, int port, String scheme, String? realm)?
          f) {
    // TODO: implement authenticateProxy
  }

  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {
    // TODO: implement badCertificateCallback
  }

  @override
  void close({bool force = false}) {
    // TODO: implement close
  }

  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {
    // TODO: implement connectionFactory
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) {
    // TODO: implement deleteUrl
    throw UnimplementedError();
  }

  @override
  set findProxy(String Function(Uri url)? f) {
    // TODO: implement findProxy
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    // TODO: implement get
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    // TODO: implement getUrl
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    // TODO: implement head
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) {
    // TODO: implement headUrl
    throw UnimplementedError();
  }

  @override
  set keyLog(Function(String line)? callback) {
    // TODO: implement keyLog
  }

  @override
  Future<HttpClientRequest> open(
      String method, String host, int port, String path) {
    // TODO: implement open
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    // TODO: implement openUrl
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    // TODO: implement patch
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) {
    // TODO: implement patchUrl
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    // TODO: implement post
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    // TODO: implement postUrl
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    // TODO: implement put
    throw UnimplementedError();
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) {
    // TODO: implement putUrl
    throw UnimplementedError();
  }
}
