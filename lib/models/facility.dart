enum FacilityStatus { available, full }

class Facility {
  final String? id;
  final String name;
  final double distanceKm;
  final bool hasPonek;
  final FacilityStatus status;

  const Facility({
    this.id,
    required this.name,
    required this.distanceKm,
    required this.hasPonek,
    required this.status,
  });

  factory Facility.fromRow(Map<String, dynamic> row) => Facility(
        id: row['id'] as String?,
        name: row['name'] as String,
        distanceKm: (row['distance_km'] as num).toDouble(),
        hasPonek: row['has_ponek'] as bool,
        status: row['status'] == 'full' ? FacilityStatus.full : FacilityStatus.available,
      );
}
