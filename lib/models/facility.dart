enum FacilityStatus { available, full }

class Facility {
  final String? id;
  final String name;
  final double distanceKm;
  final bool hasPonek;
  final FacilityStatus status;
  final int? estimatedTravelMinutes;
  final String statusSource;
  final DateTime? statusUpdatedAt;

  const Facility({
    this.id,
    required this.name,
    required this.distanceKm,
    required this.hasPonek,
    required this.status,
    this.estimatedTravelMinutes,
    this.statusSource = 'Data simulasi',
    this.statusUpdatedAt,
  });

  factory Facility.fromRow(Map<String, dynamic> row) => Facility(
    id: row['id'] as String?,
    name: row['name'] as String,
    distanceKm: (row['distance_km'] as num).toDouble(),
    hasPonek: row['has_ponek'] as bool,
    status: row['status'] == 'full'
        ? FacilityStatus.full
        : FacilityStatus.available,
    estimatedTravelMinutes: row['estimated_travel_minutes'] as int?,
    statusSource: (row['status_source'] as String?) ?? 'Data simulasi',
    statusUpdatedAt: row['status_updated_at'] == null
        ? null
        : DateTime.tryParse(row['status_updated_at'] as String)?.toLocal(),
  );
}
