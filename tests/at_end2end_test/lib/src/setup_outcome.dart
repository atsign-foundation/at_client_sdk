/// The exit code `enrollment_setup.dart` ends its process with: 0 when every
/// atSign in [atSigns] is in [completed], and 1 otherwise, after naming the
/// atSigns that are not on [log].
int setupExitCode(Iterable<String> atSigns, Set<String> completed,
    {void Function(String) log = print}) {
  final incomplete = atSigns.where((a) => !completed.contains(a)).toList();
  if (incomplete.isEmpty) return 0;
  log('Enrollment setup FAILED for $incomplete');
  return 1;
}
