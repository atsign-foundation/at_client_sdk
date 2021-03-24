class AtStreamNotification {
  String streamId;
  String fileName;
  int fileLength;
  String namespace;
  String senderAtSign;
  String currentAtSign;

  @override
  String toString() {
    return 'StreamNotification{streamId: $streamId, namespace:$namespace, fileName: $fileName, fileLength: $fileLength, senderAtSign: $senderAtSign, currentAtSign: $currentAtSign}';
  }
}
