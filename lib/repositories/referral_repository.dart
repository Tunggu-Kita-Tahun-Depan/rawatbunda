import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/referral.dart';

/// Persistence + live updates for referral cases (PRD FR-011/FR-012).
///
/// `watchActiveReferral` is what makes the multi-device demo work: every
/// device listening to it sees the same referral update in near-realtime.
abstract interface class ReferralRepository {
  /// Insert (no id yet) or update (has id) a referral. Returns the saved
  /// case including its database id.
  Future<ReferralCase> save(ReferralCase referral);

  /// Emits the most recent referral whenever it changes on any device.
  Stream<ReferralCase> watchActiveReferral();

  void dispose();
}

/// Default: single in-process case. Same code path as Supabase (stream
/// included) so the UI doesn't care which mode it's in.
class InMemoryReferralRepository implements ReferralRepository {
  final _controller = StreamController<ReferralCase>.broadcast();
  int _nextId = 1;

  @override
  Future<ReferralCase> save(ReferralCase referral) async {
    referral.id ??= 'local-${_nextId++}';
    _controller.add(referral);
    return referral;
  }

  @override
  Stream<ReferralCase> watchActiveReferral() => _controller.stream;

  @override
  void dispose() {
    _controller.close();
  }
}

/// Stores referrals in the `referral_cases` table and streams changes via
/// Supabase realtime (the table must be in the realtime publication — see
/// supabase/migrations/001_init.sql).
class SupabaseReferralRepository implements ReferralRepository {
  SupabaseClient get _client => Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  final _controller = StreamController<ReferralCase>.broadcast();
  bool _includeContactEvents = true;

  @override
  Future<ReferralCase> save(ReferralCase referral) async {
    try {
      return await _save(referral, includeContactEvents: _includeContactEvents);
    } on PostgrestException catch (error) {
      if (!_isMissingContactEventsColumn(error)) rethrow;
      _includeContactEvents = false;
      return _save(referral, includeContactEvents: false);
    }
  }

  Future<ReferralCase> _save(
    ReferralCase referral, {
    required bool includeContactEvents,
  }) async {
    final row = referral.toRow(includeContactEvents: includeContactEvents);
    if (referral.id == null) {
      final saved = await _client
          .from('referral_cases')
          .insert(row)
          .select()
          .single();
      referral.id = saved['id'] as String;
    } else {
      await _client.from('referral_cases').update(row).eq('id', referral.id!);
    }
    return referral;
  }

  bool _isMissingContactEventsColumn(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST204' && message.contains('contact_events');
  }

  @override
  Stream<ReferralCase> watchActiveReferral() {
    _sub ??= _client
        .from('referral_cases')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .limit(1)
        .listen((rows) {
          if (rows.isNotEmpty) {
            _controller.add(ReferralCase.fromRow(rows.first));
          }
        });
    return _controller.stream;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
