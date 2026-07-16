enum FacilityStatus { available, full }

class Facility {
  final String name;
  final double distanceKm;
  final bool hasPonek;
  final FacilityStatus status;

  const Facility({
    required this.name,
    required this.distanceKm,
    required this.hasPonek,
    required this.status,
  });
}
