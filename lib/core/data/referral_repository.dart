import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/referral_service.dart';

class ReferralRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> associateReferral({
    required String userId,
    String? organizationId,
  }) async {
    try {
      final referralCode = await ReferralService.instance.getReferralCode();

      if (referralCode == null || referralCode.isEmpty) {
        print('No referral found.');
        return;
      }

      print('Associating referral: $referralCode');

      final response = await _supabase.functions.invoke(
        'associate-referral',
        body: {
          'user_id': userId,
          'organization_id': organizationId,
          'referral_code': referralCode,
        },
      );

      print('Referral response: ${response.data}');

      // if (response.data != null && response.data['success'] == true) {
      //   await ReferralService.instance.clearReferralCode();
      // }
    } catch (e) {
      print(e.toString());
      print("sasasasasa");
    }
  }
}
