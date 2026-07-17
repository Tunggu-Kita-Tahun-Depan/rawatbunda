import '../models/facility.dart';

/// SYNTHETIC demo data only — no real facilities, capacity, or patients
/// (PRD §26). A real facility directory (FR-008) replaces this later.
const List<Facility> demoFacilities = [
  Facility(
    name: 'Puskesmas Sukamaju',
    distanceKm: 2.1,
    hasPonek: false,
    status: FacilityStatus.available,
    estimatedTravelMinutes: 8,
    statusSource: 'Simulasi admin',
  ),
  Facility(
    name: 'RSUD Kartini',
    distanceKm: 6.4,
    hasPonek: true,
    status: FacilityStatus.available,
    estimatedTravelMinutes: 18,
    statusSource: 'Simulasi admin',
  ),
  Facility(
    name: 'RS Bersalin Harapan Bunda',
    distanceKm: 9.8,
    hasPonek: true,
    status: FacilityStatus.full,
    estimatedTravelMinutes: 26,
    statusSource: 'Simulasi admin',
  ),
  Facility(
    name: 'RSIA Sejahtera',
    distanceKm: 12.6,
    hasPonek: true,
    status: FacilityStatus.available,
    estimatedTravelMinutes: 31,
    statusSource: 'Simulasi admin',
  ),
];
