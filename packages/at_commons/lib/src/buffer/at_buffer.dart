/// Class holder for message of different data types(int, String etc.,)
abstract class AtBuffer<T> {
  /// Message that is stored in the buffer
  T? message;

  /// maximum data the buffer can hold. If length() of the buffer exceeds this value,
  /// AtBufferOverFlowException will be thrown on calling append(data)
  int? capacity;

  /// Define terminatingChar to indicate end of buffer
  // ignore: prefer_typing_uninitialized_variables
  var terminatingChar;

  /// Returns the message stored in the buffer
  /// @returns message stored
  T? getData() => message;

  /// True - is current capacity is greater than or equal to defined capacity. False - otherwise
  /// @returns - boolean value indicating whether buffer is full or not.
  bool isFull();

  /// True - if message ends with terminatingChar. False - otherwise.
  /// @returns - boolean value indicating end of buffer
  bool isEnd();

  /// Clear the message stored in the buffer
  /// @returns - void
  void clear();

  /// Calculate current length of the message store in the buffer
  /// @returns - length of the buffer
  int length();

  /// Appends data to currently stored message to buffer.
  /// @param incoming data
  /// @returns void
  /// @throws AtBufferOverFlowException if length() + data.length > capacity
  void append(var data);
}

class AtBufferOverFlowException implements Exception {
  String message;
  AtBufferOverFlowException(this.message);
}
