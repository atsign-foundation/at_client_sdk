class AtStreamResponse {
  AtStreamStatus? status;
  String? errorCode;

  @override
  String toString() {
    return 'AtStreamResponse{status: $status, errorCode: $errorCode, errorMessage: $errorMessage}';
  }

  String? errorMessage;
}

enum AtStreamStatus { ack, noAck, complete, error }
