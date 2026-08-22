import 'package:at_auth/src/keys/io/at_keys_io.dart';

/// Runs [action] serialised against anything else retrofitting the same
/// keyfile, for whatever notion of "same keyfile" [keysIo] implies.
typedef RetrofitSerializer = Future<T> Function<T>(
    AtKeysIo keysIo, String atSign, Future<T> Function() action);

/// How a retrofit's read-mutate-write sequence is serialised, or null to run
/// it unserialised.
///
/// A retrofit reads a keyfile, decides what to change from what it finds, and
/// writes the result. Two of them racing on one keyfile can each read the
/// pre-retrofit state and each write a different enrollment into it, leaving a
/// keyfile with no unique answer to which enrollment it authenticates as.
/// Whether that race is possible depends entirely on where the keys live: a
/// file on disk can be opened by another process, an in-memory store cannot.
///
/// So the core does not decide. Left null — the default — the sequence runs
/// directly, which is correct for any store that is process-local by
/// construction. A caller whose store is shared assigns the serialiser that
/// knows how to lock it; for the `.atKeys` file that is
/// `fileRetrofitSerializer` in `package:at_auth/at_auth_io.dart`, which takes a
/// cross-process lock beside the keyfile.
///
/// Set once at startup rather than per call: it describes the process's
/// storage, not any one enrollment.
RetrofitSerializer? retrofitSerializer;
