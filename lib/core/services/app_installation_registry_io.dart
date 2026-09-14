import 'package:win32_registry/win32_registry.dart';

/// 读取 Windows 卸载注册表项中的 `InstallLocation`。
///
/// 仅在原生（桌面）构建中可用；Web 构建使用同名的桩实现
/// `app_installation_registry_web.dart`。
String? readWindowsInstallLocationFromRegistry(String registryPath) {
  RegistryKey? key;
  try {
    key = Registry.openPath(RegistryHive.currentUser, path: registryPath);
    return key.getValueAsString('InstallLocation');
  } catch (_) {
    return null;
  } finally {
    key?.close();
  }
}
