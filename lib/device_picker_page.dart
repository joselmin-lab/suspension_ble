import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_transport.dart';
import 'ble_permissions.dart';

class DevicePickerPage extends StatefulWidget {
  const DevicePickerPage({super.key, required this.ble});

  final BleTransport ble;

  @override
  State<DevicePickerPage> createState() => _DevicePickerPageState();
}

class _DevicePickerPageState extends State<DevicePickerPage> {
  List<ScanResult> results = [];
  bool scanning = false;
  String? error;

  String _nameOf(ScanResult r) {
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    final pn = r.device.platformName;
    if (pn.isNotEmpty) return pn;
    return '(sin nombre)';
  }

  Future<void> _scan() async {
    setState(() {
      scanning = true;
      error = null;
      results = [];
    });

    try {
      await BlePermissions.requestOrThrow();
      final r = await widget.ble.scan(timeout: const Duration(seconds: 6));

      // Filtrar duplicados por remoteId
      final map = <String, ScanResult>{};
      for (final x in r) {
        map[x.device.remoteId.str] = x;
      }

      setState(() {
        results = map.values.toList()
          ..sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
      });
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      setState(() => scanning = false);
    }
  }

  Future<void> _connect(ScanResult picked) async {
    try {
      await BlePermissions.requestOrThrow();
      await widget.ble.connectToResult(picked);
      if (mounted) Navigator.of(context).pop(true); // conectado
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seleccionar BT09')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          FilledButton.icon(
            onPressed: scanning ? null : _scan,
            icon: const Icon(Icons.search),
            label: Text(scanning ? 'Buscando...' : 'Buscar dispositivos (6s)'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text('Error: $error', style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 12),
          if (results.isEmpty && !scanning)
            const Text('Sin resultados todavía. Presiona "Buscar dispositivos".'),
          ...results.map((r) {
            return Card(
              child: ListTile(
                title: Text(_nameOf(r)),
                subtitle: Text(r.device.remoteId.str),
                trailing: Text('${r.rssi} dBm'),
                onTap: () => _connect(r),
              ),
            );
          }),
        ],
      ),
    );
  }
}