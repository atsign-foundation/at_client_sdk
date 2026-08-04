import 'package:meta/meta.dart';

/// {@template namespace_permission}
/// Model class representing a namespace permission.
/// The string representation of the permission is `namespace: {ns1: rw, ns2: r}`
/// where read is `r` and write is `w` and `ns1`/`ns2` are the namespaces.
/// {@endtemplate}
@immutable
class NamespacePermission {
  /// {@macro namespace_permission}
  const NamespacePermission({
    required this.namespace,
    this.read = false,
    this.write = false,
  });

  /// The namespace that the permission applies to.
  final String namespace;

  /// Whether the app/device has read access to the namespace.
  final bool read;

  /// Whether the app/device has write access to the namespace.
  final bool write;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is NamespacePermission &&
        other.namespace == namespace &&
        other.read == read &&
        other.write == write;
  }

  @override
  int get hashCode => namespace.hashCode ^ read.hashCode ^ write.hashCode;

  @override
  String toString() {
    return '$namespace:${read ? 'r' : ''}${write ? 'w' : ''}';
  }

  static NamespacePermission fromString(String s) {
    final split = s.split(':');
    final namespace = split.first;
    final permissions = split.last;
    final read = permissions == 'rw' || permissions == 'r' ? true : false;
    final write = permissions == 'rw' || permissions == 'w' ? true : false;
    return NamespacePermission(namespace: namespace, read: read, write: write);
  }
}
