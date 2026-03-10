import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract class CommandTransport {
  Future<void> sendSetClicks({required int motorId, required int clicks});
  Future<void> sendPid({required double kp, required double ki, required double kd});
}

class BleTransport implements CommandTransport {
  BleTransport({required this.onLog});

  final void Function(String line) onLog;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;

  bool get isConnected => _device != null && _writeChar != null;

  Future<void> ensureAdapterOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw Exception('Bluetooth apagado. Enciéndelo.');
    }
  }

  /// Escaneo que retorna resultados (para UI de selección)
  /// Nota: acumulamos resultados durante todo el tiempo para evitar que el primer evento llegue vacío.
  Future<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 6)}) async {
    await ensureAdapterOn();

    onLog('BLE -> scan start (${timeout.inSeconds}s)');

    // por si hubiera un scan anterior colgado
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final Map<String, ScanResult> map = {};

    final sub = FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        map[r.device.remoteId.str] = r;
      }
    });

    try {
      // LowLatency suele mejorar el descubrimiento en Android
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      // esperamos a que termine el timeout
      await Future.delayed(timeout);
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await sub.cancel();
    }

    final results = map.values.toList();
    onLog('BLE -> scan done (${results.length} resultados)');
    return results;
  }

  /// Conecta a un resultado elegido por el usuario
  Future<void> connectToResult(ScanResult picked) async {
    _device = picked.device;

    final name = picked.advertisementData.advName.isNotEmpty
        ? picked.advertisementData.advName
        : (picked.device.platformName.isNotEmpty ? picked.device.platformName : '(sin nombre)');

    onLog('BLE -> connecting to $name (${picked.device.remoteId.str})');

    try {
      await _device!.connect(timeout: const Duration(seconds: 12), autoConnect: false);
    } catch (_) {
      // si ya estaba conectado, puede fallar
    }

    onLog('BLE -> discoverServices');
    final services = await _device!.discoverServices();

    // (opcional) volcado para debug
    for (final s in services) {
      onLog('BLE -> service: ${s.uuid}');
      for (final c in s.characteristics) {
        onLog('  char: ${c.uuid} '
            'write=${c.properties.write} '
            'wwr=${c.properties.writeWithoutResponse} '
            'notify=${c.properties.notify} '
            'read=${c.properties.read}');
      }
    }

    // Seleccionamos la primera característica que permita escribir
    BluetoothCharacteristic? candidate;
    for (final s in services) {
      for (final c in s.characteristics) {
        final p = c.properties;
        if (p.write || p.writeWithoutResponse) {
          candidate ??= c;
        }
      }
    }

    if (candidate == null) {
      throw Exception('No encontré característica con permiso WRITE.');
    }

    _writeChar = candidate;
    onLog('BLE -> writeChar selected: ${_writeChar!.uuid}');
  }

  Future<void> disconnect() async {
    if (_device == null) return;
    onLog('BLE -> disconnect');
    await _device!.disconnect();
    _device = null;
    _writeChar = null;
  }

  Future<void> _writeLine(String line) async {
    if (_writeChar == null) throw Exception('No conectado (writeChar null).');

    final payload = Uint8List.fromList(utf8.encode(line));
    final withoutResponse = _writeChar!.properties.writeWithoutResponse && !_writeChar!.properties.write;
    await _writeChar!.write(payload, withoutResponse: withoutResponse);

    onLog('BLE -> wrote: ${line.trim()}');
  }

  @override
  Future<void> sendSetClicks({required int motorId, required int clicks}) async {
    clicks = clicks.clamp(0, 22);
    motorId = motorId.clamp(1, 4);
    await _writeLine('M$motorId:$clicks\n');
  }

  @override
  Future<void> sendPid({required double kp, required double ki, required double kd}) async {
    await _writeLine('PID:KP=$kp,KI=$ki,KD=$kd\n');
  }
}