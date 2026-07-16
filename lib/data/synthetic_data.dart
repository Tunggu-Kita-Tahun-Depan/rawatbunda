import '../models/facility.dart';

/// SYNTHETIC demo data only — no real facilities, capacity, or patients
/// (PRD §26). A real facility directory (FR-008) replaces this later.
const List<Facility> demoFacilities = [
  Facility(
    name: 'Puskesmas Sukamaju',
    distanceKm: 2.1,
    hasPonek: false,
    status: FacilityStatus.available,
  ),
  Facility(
    name: 'RSUD Kartini',
    distanceKm: 6.4,
    hasPonek: true,
    status: FacilityStatus.available,
  ),
  Facility(
    name: 'RS Bersalin Harapan Bunda',
    distanceKm: 9.8,
    hasPonek: true,
    status: FacilityStatus.full,
  ),
];
