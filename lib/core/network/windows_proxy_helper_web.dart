/// Web 版 [WindowsProxyHelper]：浏览器环境没有系统代理注册表可读。
///
/// 对应原生实现 `windows_proxy_helper_io.dart`；Web 分支统一返回 `null`
/// （无系统代理信息），由调用方落回直连。
class WindowsProxyHelper {
  /// Web 环境读不到系统代理，返回 `null` 表示未知。
  static String? getSystemProxy() => null;
}
