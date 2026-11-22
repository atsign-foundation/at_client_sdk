import 'package:flutter/widgets.dart';

/// Whether the dialog [state] builds is there to report to and to close:
/// mounted, with its route not yet popped, by the dialog or by the user.
bool dialogShowing(State state) =>
    state.mounted && (ModalRoute.of(state.context)?.isActive ?? true);
