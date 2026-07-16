import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/synthetic_data.dart';
import '../models/facility.dart';

/// Where the facility directory comes from (PRD FR-008).
abstract interface class FacilityRepository {
  Future<List<Facility>> getFacilities();
}

/// Default: hardcoded synthetic facilities, no backend needed.
class InMemoryFacilityRepository implements FacilityRepository {
  @override
  Future<List<Facility>> getFacilities() async => demoFacilities;
}

/// Reads the `facilities` table in Supabase.
class SupabaseFacilityRepository implements FacilityRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<Facility>> getFacilities() async {
    final rows = await _client.from('facilities').select();
    return rows.map(Facility.fromRow).toList();
  }
}
