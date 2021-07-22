class AtStreamNotification {
  late String streamId;
  late String fileName;
  late int fileLength;
  String? namespace;
  late String senderAtSign;
  late String currentAtSign;
  int? startByte;

  @override
  String toString() {
    return 'StreamNotification{streamId: $streamId, namespace:$namespace, fileName: $fileName, fileLength: $fileLength, senderAtSign: $senderAtSign, currentAtSign: $currentAtSign, startByte: $startByte}';
  }
}
