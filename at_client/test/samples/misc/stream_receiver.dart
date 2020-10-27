import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';

void main(List<String> arguments) async {
  var eofMessage = 'stream:done\n';
  var total = 0;
  for (var i = 0; i < 1; i++) {
    var f = await File('${i}.jpeg');

    var socket = await SecureSocket.connect('test.do-sf2.atsign.zone', 7474);
    socket.write('stream:receive ${i} dummy\n');
    socket.listen((data) {
      if ((data.length == 1 && data.first == 64) || data.last == 64) {
        try {
          print('skipping:${utf8.decode(data)}');
          return;
        } on Exception {
          //do nothing
        }
      }
      var eof = ListEquality().equals(data, utf8.encode(eofMessage));
      if (eof) {
        sleep(Duration(seconds: 5));
        socket.write('stream:done ${i} dummy\n');
        print('receiving stream ${i} done');
        print('bytes received:${total}');
        return;
      }
      total += data.length;
      f.writeAsBytesSync(data, mode: FileMode.append);
    }, onError: (error) {
      socket.address.toString();
    });
    print('receiver ${i} connected');
  }
}
