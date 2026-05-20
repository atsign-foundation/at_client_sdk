import 'package:at_client/at_client.dart';

enum LocationShareStatus { active, paused }

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

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
    };
  }
}

class LocationShare {
  LocationShare({
    this.schemaVersion = '1',
    required this.status,
    required this.latestPoint,
    required this.updatedAt,
  });

  factory LocationShare.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'active';
    return LocationShare(
      schemaVersion: json['schemaVersion'] as String? ?? '1',
      status: LocationShareStatus.values.byName(statusName),
      latestPoint: json['latestPoint'] == null
          ? null
          : LocationPoint.fromJson(
              Map<String, dynamic>.from(json['latestPoint'] as Map),
            ),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  final String schemaVersion;
  final LocationShareStatus status;
  final LocationPoint? latestPoint;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'status': status.name,
      if (latestPoint != null) 'latestPoint': latestPoint!.toJson(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class LocationShareFields {
  const LocationShareFields._();

  static final status = PathField<LocationShareStatus>(
    path: const ['status'],
    extract: (item) => (item as CItem<LocationShare>).obj.status,
  );

  static final updatedAt = PathField<DateTime>(
    path: const ['updatedAt'],
    extract: (item) => (item as CItem<LocationShare>).obj.updatedAt,
  );
}
