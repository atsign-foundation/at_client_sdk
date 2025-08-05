import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/src/buffer/at_buffer.dart';

class StringBuffer extends AtBuffer<String> {
  StringBuffer({var terminatingChar = '\n', int capacity = 4096}) {
    this.terminatingChar = terminatingChar;
    this.capacity = capacity;
    message = '';
  }

  @override
  void append(var data) {
    if (!canAppend(data)) {
      throw AtBufferOverFlowException('String Buffer Overflow');
    } else {
      message = message! + data;
    }
  }

  bool canAppend(data) => length() + data.length <= capacity!;

  @override
  bool isEnd() => message!.endsWith(terminatingChar);

  @override
  bool isFull() => message != null && (message!.length >= capacity!);

  @override
  void clear() => message = '';

  @override
  int length() => message!.length;
}

class ByteBuffer extends AtBuffer<List<int>> {
  late BytesBuilder _bytesBuilder;

  ByteBuffer({var terminatingChar = '\n', int capacity = 4096}) {
    this.terminatingChar = utf8.encode(terminatingChar)[0];
    this.capacity = capacity;
    _bytesBuilder = BytesBuilder(copy: false);
  }

  @override
  List<int> getData() {
    return _bytesBuilder.toBytes();
  }

  @override
  void append(var data) {
    if (isOverFlow(data)) {
      throw AtBufferOverFlowException('Byte Buffer Overflow');
    } else {
      _bytesBuilder.add(data);
    }
  }

  bool isOverFlow(data) => length() + data.length > capacity!;

  @override
  bool isEnd() => _bytesBuilder.toBytes().last == terminatingChar;

  @override
  bool isFull() => _bytesBuilder.length >= capacity!;

  @override
  void clear() => _bytesBuilder.clear();

  @override
  int length() => _bytesBuilder.length;

  void addByte(int byte) {
    _bytesBuilder.addByte(byte);
  }
}
