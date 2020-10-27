import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> arguments) async {
  for (var i = 0; i < 1; i++) {
    var socket = await SecureSocket.connect('test.do-sf2.atsign.zone', 7474);
    socket.write('stream:send ${i} dummy\n');
    socket.listen((data) {
      var decoded = utf8.decode(data);
      decoded = decoded.trim();
      print(decoded);
      if (decoded == 'stream:ack') {
        var file = File('<path_to_file>');
        var data = file.readAsBytesSync();
        print('sent bytes: ${data.length}');
        socket.add(data);
        socket.write('stream:done\n');
      }
    }, onError: (error) {
      socket.address.toString();
    });
  }
//  socket.write('hello\n');
}
