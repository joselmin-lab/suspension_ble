import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class BlePermissions {
  /// Para Android 12+: bluetoothScan + bluetoothConnect
  /// Para Android <=11: locationWhenInUse (para que el scan devuelva resultados)
  static Future<void> requestOrThrow() async {
    if (!Platform.isAndroid) return;

    // Pedimos todo lo relevante; Android ignora lo que no aplica
    final result = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = result[Permission.bluetoothScan];
    final connect = result[Permission.bluetoothConnect];
    final loc = result[Permission.locationWhenInUse];

    // Android 12+ -> scan/connect
    final android12Ok = (scan?.isGranted ?? false) && (connect?.isGranted ?? false);

    // Android <=11 -> location
    final legacyOk = (loc?.isGranted ?? false);

    if (!(android12Ok || legacyOk)) {
      throw Exception('Permisos BLE no concedidos (Scan/Connect o Location).');
    }
  }
}