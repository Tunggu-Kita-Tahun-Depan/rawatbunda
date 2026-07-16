import 'package:flutter/foundation.dart';

import '../models/facility.dart';
import '../models/referral.dart';

/// In-memory app state (hackathon scope — no backend/database yet).
/// When a backend is added later, this class stays the UI-facing API and
/// delegates to a repository layer instead of mutating the case directly.
class ReferralState extends ChangeNotifier {
  final ReferralCase referral = ReferralCase();

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

  void sendReferral(Facility facility) {
    referral.selectedFacility = facility;
    referral.step = ReferralStep.sent;
    referral.sentAt = DateTime.now();
    notifyListeners();
  }

  void acknowledge() {
    if (referral.step == ReferralStep.sent) {
      referral.step = ReferralStep.acknowledged;
      notifyListeners();
    }
  }

  void accept() {
    referral.step = ReferralStep.accepted;
    notifyListeners();
  }

  void decline() {
    referral.step = ReferralStep.sent;
    referral.selectedFacility = null;
    notifyListeners();
  }

  void markArrived() {
    referral.step = ReferralStep.arrived;
    notifyListeners();
  }

  void reset() {
    referral.patientName = '';
    referral.gestationalAgeWeeks = null;
    referral.systolic = null;
    referral.diastolic = null;
    referral.hasSevereHeadache = false;
    referral.hasVisualDisturbance = false;
    referral.urgency = Urgency.routine;
    referral.selectedFacility = null;
    referral.step = ReferralStep.draft;
    referral.sentAt = null;
    notifyListeners();
  }
}
