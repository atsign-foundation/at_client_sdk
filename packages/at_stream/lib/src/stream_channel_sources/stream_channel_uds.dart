import 'dart:io' show File, InternetAddress, InternetAddressType, Socket;
import 'dart:typed_data' show Uint8List;

import 'package:stream_channel/stream_channel.dart' show StreamChannel;
import 'stream_channel_socket.dart' show StreamChannelSocket;

extension StreamChannelUds on File {
  Future<StreamChannel<Uint8List>> toStreamChannel() async {
    final addr = InternetAddress(path, type: InternetAddressType.unix);
    final sock = await Socket.connect(addr, 0);
    return sock.toStreamChannel();
  }
}
