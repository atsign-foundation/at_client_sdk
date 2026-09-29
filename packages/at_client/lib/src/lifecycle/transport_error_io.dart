import 'dart:io' show SocketException, HandshakeException;

bool isTransportError(Object error) =>
    error is SocketException || error is HandshakeException;
