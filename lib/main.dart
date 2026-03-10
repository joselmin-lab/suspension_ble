import 'package:flutter/material.dart';
import 'ble_transport.dart';
import 'device_picker_page.dart';

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

class SuspensionStateModel {
  static const int minClicks = 0;
  static const int maxClicks = 22;

  final Map<Corner, int> clicks = {
    Corner.fl: 0,
    Corner.fr: 0,
    Corner.rl: 0,
    Corner.rr: 0,
  };

  double kp = 18.0;
  double ki = 0.02;
  double kd = 3.0;

  int clampClicks(int v) => v.clamp(minClicks, maxClicks);
}

class SuspensionPage extends StatefulWidget {
  const SuspensionPage({super.key});

  @override
  State<SuspensionPage> createState() => _SuspensionPageState();
}

class _SuspensionPageState extends State<SuspensionPage> {
  final model = SuspensionStateModel();
  final List<String> logs = [];

  late final BleTransport ble = BleTransport(
    onLog: _log,
   
    
  );

  void _log(String line) {
    setState(() {
      logs.insert(0, '${DateTime.now().toIso8601String()}  $line');
      if (logs.length > 250) logs.removeLast();
    });
  }

    Future<void> _connect() async {
  try {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DevicePickerPage(ble: ble)),
    );
    if (ok == true && mounted) setState(() {});
  } catch (e) {
    _log('ERR -> $e');
  }
}

  Future<void> _disconnect() async {
    await ble.disconnect();
    if (mounted) setState(() {});
  }

  Future<void> _sendOne(Corner c) async {
    try {
      final v = model.clicks[c]!;
      await ble.sendSetClicks(motorId: c.motorId, clicks: v);
    } catch (e) {
      _log('ERR -> $e');
    }
  }

  Future<void> _sendAll() async {
    for (final c in Corner.values) {
      await _sendOne(c);
    }
    _log('INFO -> Enviados 4 comandos (FL/FR/RL/RR)');
  }

  Future<void> _applyPresetAndSend(String presetName, int v) async {
    v = model.clampClicks(v);

    setState(() {
      for (final c in Corner.values) {
        model.clicks[c] = v;
      }
    });

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
          initialKp: model.kp,
          initialKi: model.ki,
          initialKd: model.kd,
          logs: logs,
          onLog: _log,
          onApply: (kp, ki, kd) async {
            setState(() {
              model.kp = kp;
              model.ki = ki;
              model.kd = kd;
            });
            await ble.sendPid(kp: kp, ki: ki, kd: kd);
          },
        ),
      ),
    );
    setState(() {});
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
                onPressed: _connect,
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
    final v = model.clicks[c]!;
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
              min: SuspensionStateModel.minClicks.toDouble(),
              max: SuspensionStateModel.maxClicks.toDouble(),
              divisions: (SuspensionStateModel.maxClicks - SuspensionStateModel.minClicks),
              label: '$v',
              onChanged: (d) => setState(() => model.clicks[c] = d.toInt()),
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