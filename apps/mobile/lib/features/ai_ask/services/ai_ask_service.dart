import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AiAskException implements Exception {
  const AiAskException(this.code, this.message, {this.retryable = false});
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class AiAskCitation {
  const AiAskCitation(
      {required this.title,
      this.chapter,
      this.topic,
      this.pageNumber,
      this.section});
  final String title;
  final String? chapter;
  final String? topic;
  final int? pageNumber;
  final String? section;

  factory AiAskCitation.fromJson(Map<String, dynamic> json) => AiAskCitation(
        title: json['source_title'] as String? ?? 'Approved learning material',
        chapter: json['chapter'] as String?,
        topic: json['topic'] as String?,
        pageNumber: (json['page_number'] as num?)?.toInt(),
        section: json['section'] as String?,
      );

  String get label {
    final details = <String>[
      if (chapter != null && chapter!.isNotEmpty) chapter!,
      if (topic != null && topic!.isNotEmpty) topic!,
      if (pageNumber != null) 'p. $pageNumber',
      if (section != null && section!.isNotEmpty) section!,
    ];
    return details.isEmpty ? title : '$title · ${details.join(' · ')}';
  }
}

class AiAskResponse {
  const AiAskResponse(
      {required this.answer,
      required this.isUncertain,
      required this.citations,
      required this.remaining,
      required this.resetPeriod,
      required this.cached});
  final String answer;
  final bool isUncertain;
  final List<AiAskCitation> citations;
  final int? remaining;
  final String? resetPeriod;
  final bool cached;

  factory AiAskResponse.fromJson(Map<String, dynamic> json) => AiAskResponse(
        answer: json['answer'] as String? ?? '',
        isUncertain: json['uncertain'] == true,
        citations: (json['citations'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) =>
                AiAskCitation.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        remaining: (json['remaining'] as num?)?.toInt(),
        resetPeriod: json['reset_period'] as String?,
        cached: json['cached'] == true,
      );
}

class AiAskContext {
  const AiAskContext({required this.grade, required this.subjects});
  final int grade;
  final List<String> subjects;

  factory AiAskContext.fromJson(Map<String, dynamic> json) => AiAskContext(
        grade: (json['class_grade'] as num?)?.toInt() ?? 0,
        subjects: (json['subjects'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => item['name'] as String?)
            .whereType<String>()
            .toList(growable: false),
      );
}

/// A typed client for the server-owned curriculum assistant contract. The
/// Edge Function, not this client, authorizes the caller and enforces quotas.
class AiAskService {
  AiAskService(this._client);
  final SupabaseClient _client;
  final Uuid _uuid = const Uuid();

  Future<AiAskContext> loadContext() async {
    final value = await _client.rpc('student_learning_context');
    if (value is! Map) {
      throw const AiAskException('context_unavailable',
          'Your learning subjects are not available yet.');
    }
    final context = AiAskContext.fromJson(Map<String, dynamic>.from(value));
    if (context.grade < 10 || context.subjects.isEmpty) {
      throw const AiAskException('context_unavailable',
          'AI Ask is available for your enrolled Class 10–12 subjects.');
    }
    return context;
  }

  Future<AiAskResponse> ask(
      {required String subject, required String question}) async {
    try {
      final response = await _client.functions
          .invoke('curriculum-rag', body: <String, dynamic>{
        'subject': subject,
        'question': question.trim(),
        'idempotency_key': _uuid.v4(),
      });
      final payload = _asMap(response.data);
      if (response.status >= 200 &&
          response.status < 300 &&
          payload['success'] == true) {
        return AiAskResponse.fromJson(payload);
      }
      throw _exceptionFor(payload, response.status);
    } on FunctionException catch (error) {
      throw _exceptionFor(_asMap(error.details), error.status);
    } on AiAskException {
      rethrow;
    } catch (_) {
      throw const AiAskException('network_error',
          'AI Ask could not connect. Check your connection and try again.',
          retryable: true);
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  AiAskException _exceptionFor(Map<String, dynamic> payload, int? status) {
    final code = payload['error'] as String? ?? 'ai_unavailable';
    final retryable =
        payload['retryable'] == true || status == 502 || status == 503;
    final message = switch (code) {
      'usage_limit_reached' =>
        'You have reached your AI Ask limit for this period. You can still ask your teacher for help.',
      'subject_not_enrolled' =>
        'This subject is not assigned to your account. Please ask your school to update it.',
      'unsupported_class' =>
        'AI Ask is currently available for Class 10–12 learning subjects only.',
      'invalid_question' => 'Enter a question of up to 2,000 characters.',
      'request_in_progress' =>
        'This question is still being prepared. Please wait a moment.',
      'ai_provider_unavailable' ||
      'learning_assistant_unavailable' =>
        'AI Ask is temporarily unavailable. Please try again later or ask your teacher.',
      _ =>
        'AI Ask could not answer right now. Please try again or ask your teacher.',
    };
    return AiAskException(code, message, retryable: retryable);
  }
}
