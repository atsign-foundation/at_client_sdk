import 'package:http/testing.dart';

final class ClosableMockClient extends MockClient {
  bool closed = false;

  ClosableMockClient(super.fn);

  @override
  void close() {
    closed = true;
    super.close();
  }
}
