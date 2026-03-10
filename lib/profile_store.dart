import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_models.dart';

class ProfileStore {
  static const _kProfiles = 'profiles.v1';
  static const _kActiveId = 'profiles.activeId.v1';

  static Future<List<SuspensionProfile>> loadProfiles() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kProfiles);
    if (raw == null || raw.trim().isEmpty) {
      // perfil default
      final now = DateTime.now().millisecondsSinceEpoch;
      return [
        SuspensionProfile(
          id: 'default',
          name: 'Default',
          deviceId: null,
          deviceName: null,
          fl: 0,
          fr: 0,
          rl: 0,
          rr: 0,
          pid: const SuspensionPid(kp: 18.0, ki: 0.02, kd: 3.0),
          lastUsedMs: now,
        )
      ];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((m) => SuspensionProfile.fromJson(m.map((k, v) => MapEntry('$k', v as Object?))))
        .toList();
  }

  static Future<void> saveProfiles(List<SuspensionProfile> profiles) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await sp.setString(_kProfiles, raw);
  }

  static Future<String?> loadActiveProfileId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kActiveId);
  }

  static Future<void> saveActiveProfileId(String id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kActiveId, id);
  }
}