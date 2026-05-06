import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:well_check_v3/core/ai/wellness_ai_service.dart';

part 'wellness_ai_provider.g.dart';

@Riverpod(keepAlive: true)
WellnessAiService wellnessAi(Ref ref) {
  final service = WellnessAiService();
  service.initialize();
  return service;
}
