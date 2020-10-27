class AtStreamNotification {
  String streamId;
  String fileName;
  int fileLength;
  String senderAtSign;
  String currentAtSign;

  @override
  String toString() {
    return 'StreamNotification{streamId: $streamId, fileName: $fileName, fileLength: $fileLength, senderAtSign: $senderAtSign, currentAtSign: $currentAtSign}';
  }
}
