import 'dart:io'
    show
        HttpRequest,
        X509Certificate,
        HttpConnectionInfo,
        Cookie,
        HttpHeaders,
        HttpResponse,
        HttpSession;
import 'dart:typed_data' show Uint8List;

import 'package:at_client/src/util/controlled_stream_mixin.dart';

class AtRpcHttpRequest with ControlledStream<Uint8List> implements HttpRequest {
  @override
  // TODO: implement certificate
  X509Certificate? get certificate => throw UnimplementedError();

  @override
  // TODO: implement connectionInfo
  HttpConnectionInfo? get connectionInfo => throw UnimplementedError();

  @override
  // TODO: implement contentLength
  int get contentLength => throw UnimplementedError();

  @override
  // TODO: implement cookies
  List<Cookie> get cookies => throw UnimplementedError();

  @override
  // TODO: implement headers
  HttpHeaders get headers => throw UnimplementedError();

  @override
  // TODO: implement method
  String get method => throw UnimplementedError();

  @override
  // TODO: implement persistentConnection
  bool get persistentConnection => throw UnimplementedError();

  @override
  // TODO: implement protocolVersion
  String get protocolVersion => throw UnimplementedError();

  @override
  // TODO: implement requestedUri
  Uri get requestedUri => throw UnimplementedError();

  @override
  // TODO: implement response
  HttpResponse get response => throw UnimplementedError();

  @override
  // TODO: implement session
  HttpSession get session => throw UnimplementedError();

  @override
  // TODO: implement uri
  Uri get uri => throw UnimplementedError();
}
