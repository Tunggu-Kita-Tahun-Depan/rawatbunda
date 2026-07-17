import '../core/constants/priority_rules.dart';
import '../models/patient.dart';

/// Integration contract for the ML team (TEAM_PLAN.md; PRD v2.2 §2
/// "Recommendation contract", §8.5).
///
/// Hard boundaries, enforced by the caller:
/// - The proposal is a WORKFLOW band suggestion, never a diagnosis.
/// - The final band is the MAXIMUM of the rules-engine safety floor and
///   this proposal — ML can raise attention, never lower it (PRI-005).
/// - The demo labels every proposal as synthetic/experimental (PRI-014).
class MlProposal {
  final PriorityBand proposedBand;
  final List<String> contributingFactors;
  final List<String> missingInputs;
  final DateTime generatedAt;
  final String modelVersion;

  const MlProposal({
    required this.proposedBand,
    required this.contributingFactors,
    this.missingInputs = const [],
    required this.generatedAt,
    required this.modelVersion,
  });
}

abstract interface class MlRecommendationService {
  /// Returns null when no model is available or the call fails — the app
  /// must always work rules-only (PRD principle 6: no-delay design).
  Future<MlProposal?> propose(Patient patient, Encounter encounter);
}

/// Default until the real model lands: proposes nothing, so the app runs
/// purely on the deterministic rules engine.
class FakeMlRecommendationService implements MlRecommendationService {
  @override
  Future<MlProposal?> propose(Patient patient, Encounter encounter) async =>
      null;
}
