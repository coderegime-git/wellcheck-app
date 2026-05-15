import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gemini;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gemini-powered family wellness AI service.
/// Analyzes well_events, medications, check_ins to provide
/// intelligent wellness summaries and conversational assistance.
class WellnessAiService {
  late final gemini.GenerativeModel _model;
  final List<gemini.Content> _chatHistory = [];
  bool _initialized = false;

  /// Initialize the Gemini model with active agent tools.
  void initialize() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY_HERE') {
      _initialized = false;
      return;
    }

    final tools = [
      gemini.Tool(
        functionDeclarations: [
          gemini.FunctionDeclaration(
            'log_medication_taken',
            'Log that the user has taken a specific medication. Use this when the user says they took their pill/medication. Always use this instead of just acknowledging.',
            gemini.Schema(
              gemini.SchemaType.object,
              properties: {
                'medication_name': gemini.Schema(
                  gemini.SchemaType.string,
                  description: 'The name of the medication taken',
                ),
              },
              requiredProperties: ['medication_name'],
            ),
          ),
          gemini.FunctionDeclaration(
            'send_family_update',
            'Send a status update or alert to the family dashboard. Use this when the user asks you to tell their family something, or if they sound distressed.',
            gemini.Schema(
              gemini.SchemaType.object,
              properties: {
                'message': gemini.Schema(
                  gemini.SchemaType.string,
                  description: 'The message to send to the family',
                ),
                'is_urgent': gemini.Schema(
                  gemini.SchemaType.boolean,
                  description: 'True if it is an emergency or urgent issue',
                ),
              },
              requiredProperties: ['message', 'is_urgent'],
            ),
          ),
        ],
      ),
    ];

    _model = gemini.GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      tools: tools,
      systemInstruction: gemini.Content.system(
        'You are a warm, caring wellness assistant for an elderly portal in a family safety app called Well-Check. '
        'You monitor medication adherence, check-in patterns, and safety events. '
        'If the user says they took a medication, you MUST call the log_medication_taken tool. '
        'If the user asks you to tell or alert their family, or if they sound in danger, you MUST call the send_family_update tool. '
        'Keep verbal responses concise (1-2 sentences max) and reassuring as they will be spoken aloud via text-to-speech. '
        'Always confirm out loud when you have successfully logged a pill or sent a message.',
      ),
    );
    _initialized = true;
  }

  bool get isReady => _initialized;

  /// Build family context from database for AI to analyze.
  Future<String> _buildFamilyContext(String familyId) async {
    final sb = StringBuffer();
    final supabase = Supabase.instance.client;

    try {
      final events = await supabase
          .from('well_events')
          .select('event_type, title, description, created_at, user_id')
          .eq('family_id', familyId)
          .order('created_at', ascending: false)
          .limit(20);

      sb.writeln('=== RECENT EVENTS (last 20) ===');
      for (final e in events) {
        sb.writeln(
          '- [${e['event_type']}] ${e['title']}: ${e['description'] ?? 'N/A'} (at ${e['created_at']})',
        );
      }

      final members = await supabase
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', familyId);

      sb.writeln('\n=== FAMILY MEMBERS ===');
      for (final m in members) {
        final name = m['profiles']?['full_name'] ?? 'Unknown';
        sb.writeln('- $name (${m['role']})');
      }

      final meds = await supabase
          .from('medications')
          .select('medication_name, dosage, frequency, assigned_to')
          .eq('family_id', familyId);

      sb.writeln('\n=== ACTIVE MEDICATIONS ===');
      if (meds.isEmpty) {
        sb.writeln('- No medications tracked');
      }
      for (final m in meds) {
        sb.writeln(
          '- ${m['medication_name']} (${m['dosage']}, ${m['frequency']})',
        );
      }
    } catch (e) {
      sb.writeln('[Error fetching context: $e]');
    }

    return sb.toString();
  }

  Future<void> _logMedicationStatus(String familyId, String? medName) async {
    if (medName == null) return;
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    int batteryLevel =
    100; // Safe default for simulators and aggressive background iOS policies
    try {
      final battery = Battery();
      batteryLevel = await battery.batteryLevel;
    } catch (e) {
      debugPrint(
        'Battery info not available over isolate, using default: $e',
      );
    }
    await supabase.from('well_events').insert({
      'family_id': familyId,
      'user_id': userId,
      'event_type': 'status_change', // Using an existing enum mapping
      'title': 'Medication Voice Log',
      'description': 'Verbally confirmed taking: $medName',
      'created_by': userId,
      'battery_level': batteryLevel,

    });
  }

  Future<void> _sendFamilyUpdate(
    String familyId,
    String? message,
    bool isUrgent,
  ) async {
    if (message == null) return;
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    int batteryLevel =
    100; // Safe default for simulators and aggressive background iOS policies
    try {
      final battery = Battery();
      batteryLevel = await battery.batteryLevel;
    } catch (e) {
      debugPrint(
        'Battery info not available over isolate, using default: $e',
      );
    }
    await supabase.from('well_events').insert({
      'family_id': familyId,
      'user_id': userId,
      'event_type': isUrgent ? 'sos' : 'check_in',
      'title': isUrgent ? 'Urgent Voice Alert' : 'Voice Update',
      'description': message,
      'created_by': userId,
      'battery_level': batteryLevel,

    });
  }

  /// Chat with the AI assistant, executing tools if triggered.
  Future<String> chat(String userMessage, String familyId) async {
    if (!_initialized) {
      return "I'm not connected yet. Please ask your family to add a Gemini API key in the app settings.";
    }

    try {
      final context = await _buildFamilyContext(familyId);
      final fullPrompt =
          'Here is the current family data:\n\n$context\n\nThe user says: "$userMessage"\n\nIf they are reporting a medication or asking to update the family, use your tools immediately. Otherwise, respond naturally.';

      _chatHistory.add(gemini.Content.text(fullPrompt));

      final chatSession = _model.startChat(
        history: _chatHistory.take(_chatHistory.length - 1).toList(),
      );
      var response = await chatSession.sendMessage(
        gemini.Content.text(fullPrompt),
      );

      // Check if Gemini wants to call a function/tool
      final functionCalls = response.functionCalls.toList();
      if (functionCalls.isNotEmpty) {
        final functionResponses = <gemini.FunctionResponse>[];

        for (final call in functionCalls) {
          if (call.name == 'log_medication_taken') {
            final medName = call.args['medication_name'] as String?;
            await _logMedicationStatus(familyId, medName);
            functionResponses.add(
              gemini.FunctionResponse(call.name, {'status': 'success'}),
            );
          } else if (call.name == 'send_family_update') {
            final msg = call.args['message'] as String?;
            final urgent = call.args['is_urgent'] as bool? ?? false;
            await _sendFamilyUpdate(familyId, msg, urgent);
            functionResponses.add(
              gemini.FunctionResponse(call.name, {'status': 'success'}),
            );
          }
        }

        // Send function execution results back to get the final spoken answer
        response = await chatSession.sendMessage(
          gemini.Content.functionResponses(functionResponses),
        );
      }

      final responseText = response.text ?? "I've handled that for you.";
      _chatHistory.add(gemini.Content.model([gemini.TextPart(responseText)]));

      return responseText;
    } catch (e) {
      print('[WellnessAI] Chat error: $e');
      rethrow;
    }
  }

  /// Generate a quick wellness summary for the dashboard card.
  Future<String> getWellnessSummary(String familyId) async {
    if (!_initialized) {
      return "AI wellness monitoring requires a Gemini API key.";
    }

    try {
      final context = await _buildFamilyContext(familyId);
      final prompt =
          'Based on this family data, provide a ONE-LINE wellness status summary. '
          'Use a green ✅ if all is good, yellow ⚠️ if attention needed, or red 🚨 if critical. '
          'Be specific about what needs attention.\n\n$context';

      final response = await _model.generateContent([
        gemini.Content.text(prompt),
      ]);
      return response.text ?? "Unable to generate summary.";
    } catch (e) {
      print('[WellnessAI] Summary error: $e');
      rethrow;
    }
  }

  /// Clear conversation history.
  void clearHistory() => _chatHistory.clear();
}
