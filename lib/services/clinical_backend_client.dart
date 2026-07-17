import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';

class ClinicalBackendException implements Exception {
  ClinicalBackendException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SttDraft {
  const SttDraft({
    required this.id,
    required this.transcript,
    required this.modelInput,
    required this.clinicalContext,
    required this.soapNote,
    required this.warnings,
  });

  final String id;
  final String transcript;
  final Map<String, dynamic> modelInput;
  final Map<String, dynamic> clinicalContext;
  final Map<String, String> soapNote;
  final List<String> warnings;
}

class ClinicalBackendClient {
  ClinicalBackendClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  String get _accessToken {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw ClinicalBackendException('Sesi login sudah berakhir. Silakan login ulang.');
    }
    return token;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (Env.backendUrl.isEmpty) {
      throw ClinicalBackendException('BACKEND_URL belum dikonfigurasi.');
    }
    final base = Uri.parse(Env.backendUrl);
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> _jsonPost(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _http.post(
      _uri(path),
      headers: {
        'authorization': 'Bearer $_accessToken',
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: utf8.encode(jsonEncode(payload)),
    );
    return _decode(response);
  }

  Future<({String patientId, String pregnancyEpisodeId})> createPatient({
    required String displayName,
    required int ageYears,
    required int gestationalAgeWeeks,
    required int gravida,
    required int para,
    required int abortus,
  }) async {
    final body = await _jsonPost('/v1/patients', {
      'schema_version': '1.0',
      'display_name': displayName,
      'age_years': ageYears,
      'gestational_age_weeks': gestationalAgeWeeks,
      'gravida': gravida,
      'para': para,
      'abortus': abortus,
    });
    return (
      patientId: body['patient_id'] as String,
      pregnancyEpisodeId: body['pregnancy_episode_id'] as String,
    );
  }

  Future<SttDraft> createSttDraft({
    required String patientId,
    required String pregnancyEpisodeId,
    required Uint8List wavAudio,
  }) async {
    final response = await _http.post(
      _uri('/v1/stt/drafts', {
        'patient_id': patientId,
        'pregnancy_episode_id': pregnancyEpisodeId,
      }),
      headers: {
        'authorization': 'Bearer $_accessToken',
        'content-type': 'audio/wav',
        'accept': 'application/json',
        'x-audio-filename': 'rawatbunda-recording.wav',
      },
      body: wavAudio,
    );
    final body = _decode(response);
    return SttDraft(
      id: body['draft_id'] as String,
      transcript: body['transcript'] as String? ?? '',
      modelInput: Map<String, dynamic>.from(
        body['model_input'] as Map? ?? const {},
      ),
      clinicalContext: Map<String, dynamic>.from(
        body['clinical_context'] as Map? ?? const {},
      ),
      soapNote: Map<String, String>.from(
        (body['soap_note'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
      ),
      warnings: (body['warnings'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }

  Future<Map<String, dynamic>> confirmAssessment(
    Map<String, dynamic> payload,
  ) => _jsonPost('/v1/assessments/confirm', payload);

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      body = Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      throw ClinicalBackendException(
        'Backend mengembalikan respons yang tidak valid.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = body['errors'] as List?;
      final first = errors?.isNotEmpty == true ? errors!.first as Map? : null;
      throw ClinicalBackendException(
        first?['message']?.toString() ??
            body['message']?.toString() ??
            'Permintaan backend gagal.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  void dispose() => _http.close();
}
