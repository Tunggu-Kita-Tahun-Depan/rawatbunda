import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/facility.dart';
import '../models/referral.dart';
import '../repositories/facility_repository.dart';
import '../repositories/referral_repository.dart';

/// UI-facing referral state. All persistence goes through the repository,
/// so the UI works identically in in-memory and Supabase modes.
class ReferralState extends ChangeNotifier {
  ReferralState({
    required ReferralRepository referralRepository,
    required FacilityRepository facilityRepository,
  }) : _referrals = referralRepository,
       _facilities = facilityRepository {
    // Live updates from other devices (or echoes of our own saves).
    _sub = _referrals.watchActiveReferral().listen((remote) {
      // Ignore updates for a different case than the one we hold locally
      // (e.g. the old case arriving after a reset).
      if (referral.id != null && remote.id != referral.id) return;
      if (remote.contactEvents.isEmpty && referral.contactEvents.isNotEmpty) {
        remote.contactEvents.addAll(referral.contactEvents);
      }
      referral = remote;
      notifyListeners();
    });
  }

  final ReferralRepository _referrals;
  final FacilityRepository _facilities;
  StreamSubscription<ReferralCase>? _sub;

  ReferralCase referral = ReferralCase();

  Future<List<Facility>> getFacilities() => _facilities.getFacilities();

  void updateIntake({
    required String patientName,
    required int? gestationalAgeWeeks,
    required int? systolic,
    required int? diastolic,
    required bool hasSevereHeadache,
    required bool hasVisualDisturbance,
    required Urgency urgency,
  }) {
    referral.patientName = patientName;
    referral.gestationalAgeWeeks = gestationalAgeWeeks;
    referral.systolic = systolic;
    referral.diastolic = diastolic;
    referral.hasSevereHeadache = hasSevereHeadache;
    referral.hasVisualDisturbance = hasVisualDisturbance;
    referral.urgency = urgency;
    notifyListeners();
  }

  Future<void> sendReferral(Facility facility) async {
    referral.selectedFacility = facility;
    referral.step = ReferralStep.sent;
    referral.sentAt = DateTime.now();
    notifyListeners();
    referral = await _referrals.save(referral);
    notifyListeners();
  }

  Future<void> recordFacilityResponse({
    required ReferralResponseStatus status,
    required String contactName,
    required ContactChannel channel,
    required String responseSource,
    required String recordedBy,
    required bool isSimulated,
    String? reason,
  }) async {
    if (referral.step == ReferralStep.accepted ||
        referral.step == ReferralStep.arrived) {
      throw StateError('Respons faskes untuk rujukan ini sudah dicatat.');
    }

    final facility = referral.selectedFacility;
    if (facility == null) {
      throw StateError('Pilih fasilitas sebelum mencatat respons.');
    }
    if (status == ReferralResponseStatus.declinedReported &&
        (reason == null || reason.trim().isEmpty)) {
      throw ArgumentError('Alasan penolakan wajib dicatat.');
    }

    referral.contactEvents.add(
      FacilityContactEvent(
        facilityName: facility.name,
        status: status,
        contactName: contactName.trim(),
        channel: channel,
        responseSource: responseSource.trim(),
        reason: reason?.trim(),
        recordedAt: DateTime.now(),
        recordedBy: recordedBy,
        isSimulated: isSimulated,
      ),
    );

    switch (status) {
      case ReferralResponseStatus.acceptedReported:
        referral.step = ReferralStep.accepted;
      case ReferralResponseStatus.declinedReported:
        referral.step = ReferralStep.declined;
        referral.selectedFacility = null;
      case ReferralResponseStatus.moreInformationRequested:
        referral.step = ReferralStep.sent;
    }
    notifyListeners();
    await _referrals.save(referral);
  }

  Future<void> markArrived() async {
    referral.step = ReferralStep.arrived;
    notifyListeners();
    await _referrals.save(referral);
  }

  /// Start a fresh local draft (the completed case stays in the backend).
  void reset() {
    referral = ReferralCase();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _referrals.dispose();
    super.dispose();
  }
}
