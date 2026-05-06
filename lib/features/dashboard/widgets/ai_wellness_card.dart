import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/ai/wellness_ai_provider.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI-powered family wellness summary card for Leader and Monitor dashboards.
class AiWellnessCard extends ConsumerStatefulWidget {
  const AiWellnessCard({super.key});

  @override
  ConsumerState<AiWellnessCard> createState() => _AiWellnessCardState();
}

class _AiWellnessCardState extends ConsumerState<AiWellnessCard> {
  String _summary = '';
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final ai = ref.read(wellnessAiProvider);
      final profile = await ref.read(currentUserProfileProvider.future);

      if (profile == null || !ai.isReady) {
        setState(() {
          _summary = ai.isReady
              ? 'Unable to load profile.'
              : '🔑 Add your Gemini API key in .env to enable AI wellness monitoring.';
          _isLoading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'ai_summary_${profile.familyId}';
      final cacheTimeKey = 'ai_summary_time_${profile.familyId}';

      if (!forceRefresh) {
        final cachedSummary = prefs.getString(cacheKey);
        final cachedTimeStr = prefs.getString(cacheTimeKey);
        if (cachedSummary != null && cachedTimeStr != null) {
          final cachedTime = DateTime.tryParse(cachedTimeStr);
          if (cachedTime != null && DateTime.now().difference(cachedTime).inHours < 6) {
            if (mounted) {
              setState(() {
                _summary = cachedSummary;
                _isLoading = false;
              });
            }
            return;
          }
        }
      }

      final result = await ai.getWellnessSummary(profile.familyId);
      await prefs.setString(cacheKey, result);
      await prefs.setString(cacheTimeKey, DateTime.now().toIso8601String());

      if (mounted) {
        setState(() {
          _summary = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AiWellness] Error: $e');
      if (mounted) {
        String errorMsg;
        if (e.toString().contains('API_KEY') || e.toString().contains('401') || e.toString().contains('403')) {
          errorMsg = '🔑 API key issue. Check your Gemini API key in .env settings.';
        } else if (e.toString().contains('429') || e.toString().contains('quota')) {
          errorMsg = '⏳ Quota reached. Please try later.';
        } else {
          errorMsg = '⚠️ Could not connect to AI service. Tap refresh to retry.';
        }
        setState(() {
          _summary = errorMsg;
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6B4EE6).withValues(alpha: 0.08),
            ShieldColors.activeTeal.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: ShieldDesign.roundedTwelve,
        border: Border.all(
          color: const Color(0xFF6B4EE6).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6B4EE6), ShieldColors.activeTeal],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI Wellness Monitor',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF6B4EE6),
                ),
              ),
              const Spacer(),
              if (!_isLoading)
                GestureDetector(
                  onTap: () => _loadSummary(forceRefresh: true),
                  child: Icon(
                    _hasError ? Icons.refresh : Icons.sync,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6B4EE6),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Analyzing family wellness...',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          else
            Text(
              _summary,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ShieldColors.textBody,
              ),
            ),
        ],
      ),
    );
  }
}
