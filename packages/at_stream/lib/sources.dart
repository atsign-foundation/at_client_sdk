/// Connect various sources into stream channels
/// - Socket
/// - Stdio (stdin, stdout)
/// - UDS (Unix domain sockets)
library;

export 'src/stream_channel_sources/stream_channel_stdio.dart';
export 'src/stream_channel_sources/stream_channel_socket.dart';
export 'src/stream_channel_sources/stream_channel_uds.dart';
