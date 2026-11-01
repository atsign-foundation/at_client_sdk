import 'package:at_client/at_client.dart';

/// Whether a share is still live or has been paused by its owner.
///
/// A paused share keeps its `sharedWith` audience (the recipient still sees
/// the last known point) but stops accepting new location updates until
/// resumed.
enum LocationShareStatus { active, paused }

/// A single latitude/longitude reading, with an optional accuracy radius.
class LocationPoint {
  LocationPoint({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
    );
  }

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
  };
}

/// The domain object stored in the `shares.location_sharing` [AtCollection].
///
/// One [LocationShare] represents one owner's live position, shared with a
/// set of recipient atSigns via [AtCollection.create]'s `sharedWith`
/// parameter. Recipients see their own read-only copy of the same record,
/// refreshed in place whenever the owner calls
/// [LocationSharingService.publishCurrentLocation].
class LocationShare {
  LocationShare({
    required this.status,
    required this.latestPoint,
    required this.updatedAt,
  });

  factory LocationShare.fromJson(Map<String, dynamic> json) {
    return LocationShare(
      status: LocationShareStatus.values.byName(
        json['status'] as String? ?? 'active',
      ),
      latestPoint: json['latestPoint'] == null
          ? null
          : LocationPoint.fromJson(
              Map<String, dynamic>.from(json['latestPoint'] as Map),
            ),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  final LocationShareStatus status;
  final LocationPoint? latestPoint;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    if (latestPoint != null) 'latestPoint': latestPoint!.toJson(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// Typed [PathField] accessors for [LocationShare], for use with
/// [Query.wherePath].
abstract class $LocationShare {
  static final status = PathField<LocationShareStatus>(
    path: const ['obj', 'status'],
    extract: (item) => (item.obj as LocationShare).status,
  );

  static final updatedAt = PathField<DateTime>(
    path: const ['obj', 'updatedAt'],
    extract: (item) => (item.obj as LocationShare).updatedAt,
  );
}
