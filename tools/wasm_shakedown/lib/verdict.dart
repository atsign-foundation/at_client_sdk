/// What a walk *means*: the decision layer of the wasm gates.
///
/// Judges a [Shakedown] the caller already has — no walking, no processes, no
/// `package:test`. That is what makes the baseline logic testable, and the gap
/// it closes was real: both gated packages baseline an empty allowed offender
/// set over a package owning no offender, so [RatchetVerdict.added] is empty
/// whichever way round the subtraction is written. No live baseline can tell the
/// correct implementation from the reversed one.
library;

import 'wasm_shakedown.dart';

/// What a walk means against one package's one-way baseline.
///
/// One-way: a source outside [allowedOffenders] fails, and so does a blocked
/// count above [maxBlockedPackages], but fixing either passes with no edit to
/// the config. [figure] is what reports a baseline gone loose.
class RatchetVerdict {
  /// The walk being judged. Failure messages print it whole, so widening a
  /// baseline is copying from the output rather than transcribing by hand.
  final Shakedown walk;

  /// The entry point [walk] started from. A label; nothing here re-reads it.
  final String barrel;

  /// The package this baseline speaks for. An offender owned by anything else is
  /// [maxBlockedPackages]' business, not the allow list's.
  final String package;

  /// [package]-relative paths permitted to reach a forbidden library.
  final Set<String> allowedOffenders;

  /// A ceiling on how many packages anywhere in the graph own an offender.
  final int maxBlockedPackages;

  /// The floor under [Shakedown.filesWalked]. Every other check here is about
  /// what the walk did *not* find, and a stalled walk finds nothing either — so
  /// set it near the real figure, not to 1.
  final int minFilesWalked;

  RatchetVerdict(
    this.walk, {
    required this.barrel,
    required this.package,
    required this.allowedOffenders,
    required this.maxBlockedPackages,
    required this.minFilesWalked,
  });

  /// [package]-owned offenders, by package-relative path.
  late final Set<String> owned = walk.offendersIn(package).keys.toSet();

  /// [owned] minus [allowedOffenders], sorted.
  ///
  /// The direction is the whole of what one-way means: found, minus allowed. The
  /// other direction is a baseline gone loose, which [figure] reports and
  /// nothing fails.
  late final List<String> added = owned.difference(allowedOffenders).toList()
    ..sort();

  /// Packages anywhere in the graph owning an offender, sorted.
  late final List<String> blocked = walk.blockedPackages.toList()..sort();

  /// The line printed on every run, pass or fail. `6/7 offenders` means a listed
  /// path no longer reaches anything.
  ///
  /// Counts, not sets — one path fixed and one gained reads as a comfortable
  /// `1/1` while [noNewOffenders] fails. The failure message holds the detail.
  String get figure => '$barrel — ${walk.filesWalked} files walked, '
      '${owned.length}/${allowedOffenders.length} offenders, '
      '${walk.blockedPackages.length}/$maxBlockedPackages blocked';

  bool get noNewOffenders => added.isEmpty;

  bool get underCeiling => walk.blockedPackages.length <= maxBlockedPackages;

  /// [package] is a name the walk's package config knows.
  ///
  /// A misspelt name resolves to no root, so [owned] comes back empty and every
  /// allow-list check passes by speaking for a package that does not exist.
  /// Nothing else catches it: the walk is fine, only the attribution is wrong.
  bool get packageKnown => walk.packageRoots.containsKey(package);

  bool get nothingMissing => walk.missingFiles.isEmpty;

  /// The walk went deep enough for its silence to mean anything.
  bool get deepEnough => walk.filesWalked > minFilesWalked;

  bool get holds =>
      noNewOffenders &&
      underCeiling &&
      packageKnown &&
      nothingMissing &&
      deepEnough;

  String get newOffenderMessage =>
      'These $package sources reach a forbidden platform library '
      'and are not in allowedOffenders:\n'
      '${added.map((p) => '  $p').join('\n')}\n\n'
      'If that is deliberate, add the path. Otherwise this is the '
      'regression the gate exists to catch.\n\n'
      'The full walk (${walk.filesWalked} files):\n'
      '${walk.report()}';

  String get ceilingMessage => 'The graph under $barrel now has offenders in '
      '${walk.blockedPackages.length} packages, over the '
      '$maxBlockedPackages this is baselined at:\n'
      '  ${blocked.join(', ')}';

  String get unknownPackageMessage =>
      'This gate names $package, but the walk resolved no root for it out of '
      '${walk.packageRoots.length} packages — check the spelling. Every '
      'allow-list check here is scoped to that name, so a name the package '
      'config does not know reads as a clean result.';

  String get missingFilesMessage =>
      'Imported but not found. A renamed or deleted file makes this '
      'gate report less than it should:\n'
      '${walk.missingFiles.map((f) => '  $f').join('\n')}';

  String get shallowWalkMessage =>
      'The walk visited only ${walk.filesWalked} files, and this baseline '
      'requires more than $minFilesWalked. Package resolution is probably '
      'broken — in which case the checks above passed by finding nothing.';

  /// Every failed check's message. Empty exactly when [holds], so a check that
  /// fails without prose here is a check that fails silently.
  List<String> get failures => [
        if (!noNewOffenders) newOffenderMessage,
        if (!underCeiling) ceilingMessage,
        if (!packageKnown) unknownPackageMessage,
        if (!nothingMissing) missingFilesMessage,
        if (!deepEnough) shallowWalkMessage,
      ];
}

/// What a walk means as the positive control for a baseline.
///
/// A ratchet's checks are all about what a walk did *not* find, so a walk that
/// found nothing satisfies every one of them. A control walks the other side of
/// the seam — the platform island, or the branch a conditional export takes —
/// and asserts the walk still *reaches* something known to be there. Without
/// one, an island could be emptied and the gate would still read green.
///
/// Two axes, each weak alone: [reachesLibrary] pins that a forbidden library is
/// still reached from somewhere in [package] but not where; [reachesFile] pins
/// one source but not what it imports.
///
/// No minimum file count, unlike [RatchetVerdict.deepEnough]: these checks are
/// positive, so a stalled walk fails them on its own.
class ControlVerdict {
  final Shakedown walk;
  final String barrel;
  final String package;

  /// A [package]-relative path that must be among the offenders found.
  ///
  /// The walk records offenders, not every file it visited, so this names a
  /// source that itself imports a forbidden library — not one on the way to one.
  final String? reachesFile;

  /// A forbidden library that some [package] source must reach.
  final String? reachesLibrary;

  /// What this control keeps reachable, in prose, for the message.
  final String because;

  ControlVerdict(
    this.walk, {
    required this.barrel,
    required this.package,
    required this.because,
    this.reachesFile,
    this.reachesLibrary,
  }) {
    if (reachesFile == null && reachesLibrary == null) {
      throw ArgumentError('a control asserting nothing passes on a walk that '
          'found nothing, which is the failure it exists to catch — name '
          'reachesFile, reachesLibrary, or both');
    }
  }

  /// [package]-owned offenders, by package-relative path.
  late final Map<String, List<String>> owned = walk.offendersIn(package);

  /// Every forbidden library any [package] source reaches.
  late final Set<String> libraries =
      owned.values.expand((libs) => libs).toSet();

  /// Null when the axis was not named, so an axis left out is absent rather
  /// than passing.
  bool? get fileReached =>
      reachesFile == null ? null : owned.containsKey(reachesFile);

  bool? get libraryReached =>
      reachesLibrary == null ? null : libraries.contains(reachesLibrary);

  bool get holds => fileReached != false && libraryReached != false;

  /// What this control asserts, for a one-line report.
  String get target => [
        if (reachesFile != null) reachesFile,
        if (reachesLibrary != null) reachesLibrary,
      ].join(' and ');

  /// The failed check's message, or empty when the control holds.
  List<String> get failures => holds
      ? const []
      : [
          '$barrel no longer reaches $because.\n\n'
              'This is the positive control for $package\'s baseline: an empty '
              'offender set reads the same whether the platform code is still '
              'quarantined behind this seam or simply gone. Either it moved — '
              'retarget this control — or the seam collapsed and the baseline '
              'now proves nothing.\n\n'
              '${_missed()}\n\n'
              'The walk visited ${walk.filesWalked} files and found these '
              '$package offenders:\n${_ownedListing()}\n\n'
              'The full walk:\n${walk.report()}',
        ];

  String _missed() => [
        if (fileReached == false) 'Expected the source $reachesFile.',
        if (libraryReached == false)
          'Expected some source to reach $reachesLibrary.',
      ].join('\n');

  String _ownedListing() => owned.isEmpty
      ? '  (none — a walk that reached nothing fails a control on its own, '
          'which is why there is no minimum file count here)'
      : (owned.keys.toList()..sort())
          .map((p) => '  $p -> ${owned[p]!.join(', ')}')
          .join('\n');
}
