/// The SDK map's generator and gate: reads the curated model in
/// `docs/map/model`, checks it against this checkout and a pinned at_server,
/// and writes the data `docs/map/index.html` loads.
library;

export 'src/commands.dart';
export 'src/engine.dart' show Workspace, Build, StepOut, build, digest;
export 'src/exits.dart' show Exit, ExitWalker, Inventory, negate;
export 'src/model.dart' show Model, loadModel, modelDir;
export 'src/output.dart' show Budgets, allowedHref, canonicalJson;
