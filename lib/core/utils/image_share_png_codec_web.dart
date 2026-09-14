import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// `package:nai_png_codec` 的 Web 降级实现。
///
/// libspng 原生绑定（dart:ffi）不可用于浏览器，这里改用 `package:image`
/// 解码/重编码实现同等 API：
/// - [sanitizePngPixels]：解码后重编码，达到去除附属元数据/尾部数据的效果；
/// - [encodePngRgba]：把 RGBA 缓冲编码为 PNG。
///
/// 性能低于原生实现，仅作为 Web 分支的过渡方案。
Uint8List sanitizePngPixels(Uint8List bytes) {
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    throw const FormatException('PNG bytes could not be decoded');
  }
  return Uint8List.fromList(img.encodePng(decoded, level: 1));
}

Uint8List encodePngRgba(Uint8List pixels, int width, int height) {
  if (width <= 0 || height <= 0 || pixels.length != width * height * 4) {
    throw ArgumentError('RGBA buffer does not match its dimensions');
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image, level: 1));
}
