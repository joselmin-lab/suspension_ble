class SuspensionPid {
  final double kp;
  final double ki;
  final double kd;

  const SuspensionPid({required this.kp, required this.ki, required this.kd});

  Map<String, Object?> toJson() => {'kp': kp, 'ki': ki, 'kd': kd};

  static SuspensionPid fromJson(Map<String, Object?> json) {
    double d(dynamic v, double fallback) => (v is num) ? v.toDouble() : fallback;
    return SuspensionPid(
      kp: d(json['kp'], 18.0),
      ki: d(json['ki'], 0.02),
      kd: d(json['kd'], 3.0),
    );
  }
}

class SuspensionProfile {
  final String id; // uuid simple (string)
  final String name;

  /// BLE remoteId.str (ej: "C0:98:E5:...") o null si no asignado
  final String? deviceId;

  /// Nombre visible del BLE (opcional)
  final String? deviceName;

  final int fl;
  final int fr;
  final int rl;
  final int rr;

  final SuspensionPid pid;

  final int lastUsedMs;

  final int presetComfort;
  final int presetSport;
  final int presetTrack;

  const SuspensionProfile({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.deviceName,
    required this.fl,
    required this.fr,
    required this.rl,
    required this.rr,
    required this.pid,
    required this.lastUsedMs,
    this.presetComfort = 0,
    this.presetSport = 11,
    this.presetTrack = 22,
  });

  SuspensionProfile copyWith({
    String? id,
    String? name,
    String? deviceId,
    String? deviceName,
    int? fl,
    int? fr,
    int? rl,
    int? rr,
    SuspensionPid? pid,
    int? lastUsedMs,
    int? presetComfort,
    int? presetSport,
    int? presetTrack,
  }) {
    return SuspensionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      fl: fl ?? this.fl,
      fr: fr ?? this.fr,
      rl: rl ?? this.rl,
      rr: rr ?? this.rr,
      pid: pid ?? this.pid,
      lastUsedMs: lastUsedMs ?? this.lastUsedMs,
      presetComfort: presetComfort ?? this.presetComfort,
      presetSport: presetSport ?? this.presetSport,
      presetTrack: presetTrack ?? this.presetTrack,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'fl': fl,
        'fr': fr,
        'rl': rl,
        'rr': rr,
        'pid': pid.toJson(),
        'lastUsedMs': lastUsedMs,
        'presetComfort': presetComfort,
        'presetSport': presetSport,
        'presetTrack': presetTrack,
      };

  static SuspensionProfile fromJson(Map<String, Object?> json) {
    int i(dynamic v, int fallback) => (v is num) ? v.toInt() : fallback;
    String? s(dynamic v) => (v is String && v.trim().isNotEmpty) ? v : null;

    final pidJson = json['pid'];
    final pid = (pidJson is Map)
        ? SuspensionPid.fromJson(pidJson.map((k, v) => MapEntry('$k', v as Object?)))
        : const SuspensionPid(kp: 18.0, ki: 0.02, kd: 3.0);

    return SuspensionProfile(
      id: (json['id'] as String?) ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
      name: (json['name'] as String?) ?? 'Perfil',
      deviceId: s(json['deviceId']),
      deviceName: s(json['deviceName']),
      fl: i(json['fl'], 0).clamp(0, 22),
      fr: i(json['fr'], 0).clamp(0, 22),
      rl: i(json['rl'], 0).clamp(0, 22),
      rr: i(json['rr'], 0).clamp(0, 22),
      pid: pid,
      lastUsedMs: i(json['lastUsedMs'], 0),
      presetComfort: i(json['presetComfort'], 0).clamp(0, 22),
      presetSport: i(json['presetSport'], 11).clamp(0, 22),
      presetTrack: i(json['presetTrack'], 22).clamp(0, 22),
    );
  }
}