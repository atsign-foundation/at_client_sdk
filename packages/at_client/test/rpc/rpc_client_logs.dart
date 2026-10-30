import 'package:at_client/at_client.dart';

/// Logs one line through the RPC client's logger with every logging default
/// untouched, so the test running this can see which stream it reaches.
void main() {
  AtRpcClient.logger.info('rpc-client-log-probe');
}
