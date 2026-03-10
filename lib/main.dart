import 'package:flutter/material.dart';

import 'ble_transport.dart';
import 'device_picker_page.dart';
import 'profile_models.dart';
import 'profile_store.dart';

void main() => runApp(const SuspensionUiApp());

enum Corner { fl, fr, rl, rr }

extension CornerX on Corner {
  String get label => switch (this) {
        Corner.fl => 'FL (Del Izq)',
        Corner.fr => 'FR (Del Der)',
        Corner.rl => 'RL (Tras Izq)',
        Corner.rr => 'RR (Tras Der)',
      };

  int get motorId => switch (this) {
        Corner.fl => 1,
        Corner.fr => 2,
        Corner.rl => 3,
        Corner.rr => 4,
      };
}

class SuspensionUiApp extends StatelessWidget {
  const SuspensionUiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suspensión BLE',
      theme: ThemeData.dark(useMaterial3: true),
      home: const SuspensionPage(),
    );
  }
}

class SuspensionPage extends StatefulWidget {
  const SuspensionPage({super.key});

  @override
  State<SuspensionPage> createState() => _SuspensionPageState();
}

class _SuspensionPageState extends State<SuspensionPage> {
  // ===== BLE =====
  final List<String> logs = [];
  late final BleTransport ble = BleTransport(onLog: _log);

  // ===== Profiles =====
  List<SuspensionProfile> profiles = const [];
  SuspensionProfile? active;

  bool loadingProfiles = true;

  // ===== UI state (editable) =====
  final Map<Corner, int> clicks = {
    Corner.fl: 0,
    Corner.fr: 0,
    Corner.rl: 0,
    Corner.rr: 0,
  };

  double kp = 18.0;
  double ki = 0.02;
  double kd = 3.0;

  // ===== Helpers =====
  void _log(String line) {
    setState(() {
      logs.insert(0, '${DateTime.now().toIso8601String()}  $line');
      if (logs.length > 250) logs.removeLast();
    });
  }

  int _clampClicks(int v) => v.clamp(0, 22);

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => loadingProfiles = true);

    final loaded = await ProfileStore.loadProfiles();
    final activeId = await ProfileStore.loadActiveProfileId();

    SuspensionProfile picked;
    if (activeId != null) {
      picked = loaded.firstWhere(
        (p) => p.id == activeId,
        orElse: () => loaded.first,
      );
    } else {
      picked = loaded.first;
    }

    setState(() {
      profiles = loaded;
      active = picked;
      loadingProfiles = false;
    });

    _applyProfileToUi(picked);

    // Auto-connect (opción B) si tiene device asignado
    await _autoConnectForActiveProfile();
  }

  void _applyProfileToUi(SuspensionProfile p) {
    setState(() {
      clicks[Corner.fl] = _clampClicks(p.fl);
      clicks[Corner.fr] = _clampClicks(p.fr);
      clicks[Corner.rl] = _clampClicks(p.rl);
      clicks[Corner.rr] = _clampClicks(p.rr);

      kp = p.pid.kp;
      ki = p.pid.ki;
      kd = p.pid.kd;
    });
  }

  SuspensionProfile _uiToProfile(SuspensionProfile base, {String? deviceId, String? deviceName}) {
    return base.copyWith(
      deviceId: deviceId ?? base.deviceId,
      deviceName: deviceName ?? base.deviceName,
      fl: _clampClicks(clicks[Corner.fl] ?? 0),
      fr: _clampClicks(clicks[Corner.fr] ?? 0),
      rl: _clampClicks(clicks[Corner.rl] ?? 0),
      rr: _clampClicks(clicks[Corner.rr] ?? 0),
      pid: SuspensionPid(kp: kp, ki: ki, kd: kd),
      lastUsedMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _saveActiveFromUi() async {
    final a = active;
    if (a == null) return;

    final updated = _uiToProfile(a);

    final newProfiles = profiles.map((p) => p.id == updated.id ? updated : p).toList();

    setState(() {
      profiles = newProfiles;
      active = updated;
    });

    await ProfileStore.saveProfiles(newProfiles);
    await ProfileStore.saveActiveProfileId(updated.id);
  }

  Future<void> _setActiveProfile(SuspensionProfile p) async {
    // antes de cambiar, guardamos el active actual con lo que haya en UI
    await _saveActiveFromUi();

    setState(() => active = p);
    _applyProfileToUi(p);

    await ProfileStore.saveActiveProfileId(p.id);

    // Auto-connect por perfil
    await _autoConnectForActiveProfile();
  }

  Future<void> _autoConnectForActiveProfile() async {
    final a = active;
    if (a == null) return;

    if (a.deviceId == null || a.deviceId!.trim().isEmpty) {
      _log('INFO -> Perfil "${a.name}" sin device asignado (no auto-connect).');
      return;
    }

    // Si ya está conectado, no hacemos nada.
    if (ble.isConnected) {
      _log('INFO -> Ya conectado. (Perfil: ${a.name})');
      return;
    }

    try {
      _log('BLE -> Auto-connect: buscando ${a.deviceName ?? "(sin nombre)"} (${a.deviceId})');
      // Escaneamos y buscamos match por remoteId.str
      final results = await ble.scan(timeout: const Duration(seconds: 6));
      final match = results.where((r) => r.device.remoteId.str == a.deviceId).toList();

      if (match.isEmpty) {
        _log('WARN -> No encontré el device del perfil en el scan.');
        return;
      }

      await ble.connectToResult(match.first);
      if (mounted) setState(() {});
      _log('BLE -> Auto-connect OK (perfil "${a.name}")');
    } catch (e) {
      _log('ERR -> Auto-connect falló: $e');
    }
  }

  // ===== Profile UI actions =====

  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
    String okText = 'OK',
  }) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(okText),
          ),
        ],
      ),
    );
    if (res == null || res.trim().isEmpty) return null;
    return res.trim();
  }

  Future<void> _createProfile() async {
    final name = await _promptText(title: 'Nuevo perfil', label: 'Nombre del perfil', okText: 'Crear');
    if (name == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'p_$now';

    // por defecto: copia valores actuales de UI (así puedes crear “nuevo vehículo” desde un setup)
    final p = SuspensionProfile(
      id: id,
      name: name,
      deviceId: null,
      deviceName: null,
      fl: _clampClicks(clicks[Corner.fl] ?? 0),
      fr: _clampClicks(clicks[Corner.fr] ?? 0),
      rl: _clampClicks(clicks[Corner.rl] ?? 0),
      rr: _clampClicks(clicks[Corner.rr] ?? 0),
      pid: SuspensionPid(kp: kp, ki: ki, kd: kd),
      lastUsedMs: now,
    );

    final newProfiles = [...profiles, p];

    setState(() {
      profiles = newProfiles;
      active = p;
    });

    await ProfileStore.saveProfiles(newProfiles);
    await ProfileStore.saveActiveProfileId(p.id);
  }

  Future<void> _renameActiveProfile() async {
    final a = active;
    if (a == null) return;

    final name =
        await _promptText(title: 'Renombrar perfil', label: 'Nuevo nombre', initial: a.name, okText: 'Guardar');
    if (name == null) return;

    final updated = a.copyWith(name: name);
    final newProfiles = profiles.map((p) => p.id == updated.id ? updated : p).toList();

    setState(() {
      profiles = newProfiles;
      active = updated;
    });

    await ProfileStore.saveProfiles(newProfiles);
    await ProfileStore.saveActiveProfileId(updated.id);
  }

  Future<void> _deleteActiveProfile() async {
    final a = active;
    if (a == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar perfil'),
        content: Text('¿Eliminar "${a.name}"? (No se puede deshacer)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final remaining = profiles.where((p) => p.id != a.id).toList();
    if (remaining.isEmpty) {
      // si borró el último, creamos uno default
      final now = DateTime.now().millisecondsSinceEpoch;
      final def = SuspensionProfile(
        id: 'default_$now',
        name: 'Default',
        deviceId: null,
        deviceName: null,
        fl: 0,
        fr: 0,
        rl: 0,
        rr: 0,
        pid: const SuspensionPid(kp: 18.0, ki: 0.02, kd: 3.0),
        lastUsedMs: now,
      );
      remaining.add(def);
    }

    final newActive = remaining.first;

    setState(() {
      profiles = remaining;
      active = newActive;
    });

    await ProfileStore.saveProfiles(remaining);
    await ProfileStore.saveActiveProfileId(newActive.id);

    _applyProfileToUi(newActive);
  }

  Future<void> _assignDeviceToActiveProfile() async {
    final picked = await Navigator.of(context).push<PickedDevice>(
      MaterialPageRoute(builder: (_) => DevicePickerPage(ble: ble)),
    );

    if (picked == null) return;

    final a = active;
    if (a == null) return;

    final updated = _uiToProfile(a, deviceId: picked.deviceId, deviceName: picked.deviceName);

    final newProfiles = profiles.map((p) => p.id == updated.id ? updated : p).toList();

    setState(() {
      profiles = newProfiles;
      active = updated;
    });

    await ProfileStore.saveProfiles(newProfiles);
    await ProfileStore.saveActiveProfileId(updated.id);

    _log('INFO -> Perfil "${updated.name}" asignado a ${picked.deviceName} (${picked.deviceId})');
  }

  // ===== BLE buttons =====

  Future<void> _connectManual() async {
    try {
      final picked = await Navigator.of(context).push<PickedDevice>(
        MaterialPageRoute(builder: (_) => DevicePickerPage(ble: ble)),
      );

      if (picked == null) return;
      if (mounted) setState(() {});

      // Guardar último device en perfil activo (porque pediste "1) sí")
      final a = active;
      if (a != null) {
        final updated = _uiToProfile(a, deviceId: picked.deviceId, deviceName: picked.deviceName);
        final newProfiles = profiles.map((p) => p.id == updated.id ? updated : p).toList();
        setState(() {
          profiles = newProfiles;
          active = updated;
        });
        await ProfileStore.saveProfiles(newProfiles);
        await ProfileStore.saveActiveProfileId(updated.id);
      }
    } catch (e) {
      _log('ERR -> $e');
    }
  }

  Future<void> _disconnect() async {
    await ble.disconnect();
    if (mounted) setState(() {});
  }

  // ===== Sending =====

  Future<void> _sendOne(Corner c) async {
    try {
      final v = _clampClicks(clicks[c] ?? 0);
      await ble.sendSetClicks(motorId: c.motorId, clicks: v);
      await _saveActiveFromUi(); // persistimos cambio/estado actual
    } catch (e) {
      _log('ERR -> $e');
    }
  }

  Future<void> _sendAll() async {
    try {
      for (final c in Corner.values) {
        await _sendOne(c);
      }
      _log('INFO -> Enviados 4 comandos (FL/FR/RL/RR)');
    } catch (e) {
      _log('ERR -> $e');
    }
  }

  Future<void> _applyPresetAndSend(String presetName, int v) async {
    v = _clampClicks(v);

    setState(() {
      for (final c in Corner.values) {
        clicks[c] = v;
      }
    });

    await _saveActiveFromUi();

    _log('UI  -> Preset $presetName aplicado: $v clicks (enviando...)');

    for (final c in Corner.values) {
      await ble.sendSetClicks(motorId: c.motorId, clicks: v);
    }

    _log('INFO -> Preset $presetName enviado a los 4 motores');
  }

  Future<void> _openAdvanced() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvancedSettingsPage(
          initialKp: kp,
          initialKi: ki,
          initialKd: kd,
          logs: logs,
          onLog: _log,
          onApply: (newKp, newKi, newKd) async {
            setState(() {
              kp = newKp;
              ki = newKi;
              kd = newKd;
            });
            await _saveActiveFromUi();
            await ble.sendPid(kp: newKp, ki: newKi, kd: newKd);
          },
        ),
      ),
    );
    setState(() {});
  }

  // ===== Widgets =====

  Widget _profilesPanel() {
    final a = active;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Perfil', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: loadingProfiles
                      ? const Text('Cargando perfiles...')
                      : DropdownButtonFormField<String>(
                          initialValue: a?.id,
                          items: profiles
                              .map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name),
                                  ))
                              .toList(),
                          onChanged: (id) {
                            if (id == null) return;
                            final p = profiles.firstWhere((x) => x.id == id);
                            _setActiveProfile(p);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Seleccionar perfil',
                            border: OutlineInputBorder(),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _createProfile,
                  tooltip: 'Nuevo perfil',
                  icon: const Icon(Icons.add),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones de perfil',
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _renameActiveProfile();
                        break;
                      case 'assign':
                        _assignDeviceToActiveProfile();
                        break;
                      case 'delete':
                        _deleteActiveProfile();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                    PopupMenuItem(value: 'assign', child: Text('Asignar/Conectar dispositivo')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              a?.deviceId == null
                  ? 'Device: (no asignado)'
                  : 'Device: ${a?.deviceName ?? "(sin nombre)"} (${a?.deviceId})',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blePanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                ble.isConnected ? 'BLE: Conectado' : 'BLE: Desconectado',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (!ble.isConnected)
              FilledButton.icon(
                onPressed: _connectManual,
                icon: const Icon(Icons.bluetooth_connected),
                label: const Text('Conectar'),
              )
            else
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Desconectar'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _presetButton(String label, int value) {
    return Expanded(
      child: FilledButton(
        onPressed: ble.isConnected ? () => _applyPresetAndSend(label, value) : null,
        child: Text('$label ($value)'),
      ),
    );
  }

  Widget _cornerCard(Corner c) {
    final v = _clampClicks(clicks[c] ?? 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('$v', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                const Text('clicks'),
                const Spacer(),
                FilledButton.icon(
                  onPressed: ble.isConnected ? () => _sendOne(c) : null,
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar'),
                ),
              ],
            ),
            Slider(
              value: v.toDouble(),
              min: 0,
              max: 22,
              divisions: 22,
              label: '$v',
              onChanged: (d) => setState(() => clicks[c] = d.toInt()),
              onChangeEnd: (_) => _saveActiveFromUi(), // guardar al soltar
            ),
          ],
        ),
      ),
    );
  }

  Widget _logPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Consola', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: logs.isEmpty
                      ? const Text('Logs BLE y comandos.')
                      : ListView.builder(
                          itemCount: logs.length,
                          itemBuilder: (context, i) => Text(
                            logs[i],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => logs.clear()),
                    child: const Text('Limpiar'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const comfort = 0;
    const sport = 11;
    const track = 22;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suspensión BLE'),
        actions: [
          IconButton(
            onPressed: _openAdvanced,
            icon: const Icon(Icons.tune),
            tooltip: 'Ajustes avanzados',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _profilesPanel(),
          _blePanel(),
          Row(
            children: [
              _presetButton('Comfort', comfort),
              const SizedBox(width: 8),
              _presetButton('Sport', sport),
              const SizedBox(width: 8),
              _presetButton('Track', track),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: ble.isConnected ? _sendAll : null,
            icon: const Icon(Icons.send),
            label: const Text('Enviar todo'),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 760 ? 2 : 1,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: MediaQuery.of(context).size.width > 760 ? 2.7 : 1.95,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _cornerCard(Corner.fl),
              _cornerCard(Corner.fr),
              _cornerCard(Corner.rl),
              _cornerCard(Corner.rr),
            ],
          ),
          const SizedBox(height: 12),
          _logPanel(),
        ],
      ),
    );
  }
}

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({
    super.key,
    required this.initialKp,
    required this.initialKi,
    required this.initialKd,
    required this.onApply,
    required this.logs,
    required this.onLog,
  });

  final double initialKp;
  final double initialKi;
  final double initialKd;

  final Future<void> Function(double kp, double ki, double kd) onApply;

  final List<String> logs;
  final void Function(String line) onLog;

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  late double kp = widget.initialKp;
  late double ki = widget.initialKi;
  late double kd = widget.initialKd;

  final _kpCtrl = TextEditingController();
  final _kiCtrl = TextEditingController();
  final _kdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kpCtrl.text = kp.toStringAsFixed(3);
    _kiCtrl.text = ki.toStringAsFixed(5);
    _kdCtrl.text = kd.toStringAsFixed(3);
  }

  double _parse(String s, double fallback) => double.tryParse(s.trim()) ?? fallback;

  Future<void> _apply() async {
    final newKp = _parse(_kpCtrl.text, kp);
    final newKi = _parse(_kiCtrl.text, ki);
    final newKd = _parse(_kdCtrl.text, kd);

    setState(() {
      kp = newKp;
      ki = newKi;
      kd = newKd;
    });

    widget.onLog('UI  -> Aplicar PID: Kp=$kp Ki=$ki Kd=$kd');
    await widget.onApply(kp, ki, kd);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PID enviado')),
      );
    }
  }

  @override
  void dispose() {
    _kpCtrl.dispose();
    _kiCtrl.dispose();
    _kdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes avanzados')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PID', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _kpCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Kp'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _kiCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ki'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _kdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Kd'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.send),
                    label: const Text('Enviar PID'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}