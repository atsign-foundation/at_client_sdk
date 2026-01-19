/// Callback type for handling file collisions on the target path.
///
/// Called after keys are successfully written to a temp file, but before moving to the target.
/// If the target path already exists, this handler decides whether to:
/// - Use an alternative path
/// - Abort (default for safety)
typedef AtKeysFileCollisionHandler = AtKeysFileCollisionResult Function(
    AtKeysFileCollisionContext context);


/// Context passed to collision handlers when a target file already exists.
class AtKeysFileCollisionContext {
  /// The final target file path that already exists
  final String targetFilePath;

  /// The content of the keys file to be written
  final String keysContent;

  AtKeysFileCollisionContext({
    required this.targetFilePath,
    required this.keysContent,
  });
}

/// Result returned by a collision handler to decide the next action.
abstract class AtKeysFileCollisionResult {
  const AtKeysFileCollisionResult();
}

/// Use an alternative path instead of the target.
class AtKeysFileCollisionUseAlternative extends AtKeysFileCollisionResult {
  /// The alternative file path to be used
  final String alternativePath;

  const AtKeysFileCollisionUseAlternative(this.alternativePath);

  @override
  String toString() => 'AtKeysFileCollisionUseAlternative('
      'alternativePath: $alternativePath)';
}

/// Abort the operation.
class AtKeysFileCollisionAbort extends AtKeysFileCollisionResult {
  final String? customMessage;

  const AtKeysFileCollisionAbort({this.customMessage});

  @override
  String toString() => 'AtKeysFileCollisionAbort('
      'customMessage: ${customMessage ?? "user aborted"})';
}