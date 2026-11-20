/// The longest stretch of text from outside the process that an exception
/// message carries.
const maxMessageTextLength = 180;

/// [text] as it may appear in an exception message: unchanged when it is at
/// most [maxMessageTextLength] characters, otherwise cut to that length and
/// followed by an ellipsis.
String clipForMessage(String text) => text.length <= maxMessageTextLength
    ? text
    : '${text.substring(0, maxMessageTextLength)}...';
