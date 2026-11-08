import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/agent/agent_types.dart';
import '../../models/agent_protocol.dart';
import 'thinking_prefill_messages.dart';

/// Streams prose and buffers a standalone final tool frame until the response
/// finishes normally. Inline examples and Markdown code stay literal; partial,
/// cancelled or malformed batches never emit executable tool events.
class PrefillToolDecoder {
  PrefillToolDecoder(List<Tool> tools)
    : _names = tools.map((tool) => tool.name).toSet();

  final Set<String> _names;
  final StringBuffer _buffer = StringBuffer();
  final StringBuffer _line = StringBuffer();
  String _pendingStart = '';
  bool _lineStart = true;
  int _indent = 0;
  String? _fenceMarker;
  bool _toolFrame = false;
  bool _finished = false;
  static const _maxToolCharacters = 1024 * 1024;
  static final _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');

  List<AgentWireEvent> push(String delta) {
    if (_finished || delta.isEmpty) return const [];
    if (_toolFrame) {
      _buffer.write(delta);
      _checkSize();
      return const [];
    }
    final text = StringBuffer();
    for (var index = 0; index < delta.length; index++) {
      final character = delta[index];
      if (_pendingStart.isNotEmpty) {
        _pendingStart += character;
        if (_pendingStart == prefillToolStart) {
          _toolFrame = true;
          _buffer.write(_pendingStart);
          _buffer.write(delta.substring(index + 1));
          _pendingStart = '';
          _line.clear();
          _checkSize();
          break;
        }
        if (!prefillToolStart.startsWith(_pendingStart)) {
          text.write(_pendingStart);
          _pendingStart = '';
        }
      } else if (_lineStart && _fenceMarker == null && character == '<') {
        _pendingStart = character;
      } else {
        text.write(character);
      }
      _trackLine(character);
    }
    return text.isEmpty ? const [] : [AgentWireTextDelta(text.toString())];
  }

  void _trackLine(String character) {
    if (character == '\n' || character == '\r') {
      final fence = _fenceLine.firstMatch(_line.toString());
      if (fence != null) {
        final marker = fence.group(1)!;
        final suffix = fence.group(2)!;
        if (_fenceMarker == null) {
          if (marker[0] != '`' || !suffix.contains('`')) {
            _fenceMarker = marker;
          }
        } else if (marker[0] == _fenceMarker![0] &&
            marker.length >= _fenceMarker!.length &&
            suffix.trim().isEmpty) {
          _fenceMarker = null;
        }
      }
      _line.clear();
      _lineStart = true;
      _indent = 0;
      return;
    }
    _line.write(character);
    if (_lineStart && character == ' ' && _indent < 3) {
      _indent++;
    } else {
      _lineStart = false;
    }
  }

  void _checkSize() {
    if (_buffer.length > _maxToolCharacters) {
      throw const FormatException(
        'Prefill tool request exceeds the character limit.',
      );
    }
  }

  List<AgentWireEvent> finish({required String? reason, Usage? usage}) {
    if (_finished) return const [];
    _finished = true;
    if (!_toolFrame && !_pendingStart.startsWith('<launcher_')) {
      return [
        if (_pendingStart.isNotEmpty) AgentWireTextDelta(_pendingStart),
        AgentWireFinish(stopReason: _stopReason(reason), usage: usage),
      ];
    }
    _buffer.write(_pendingStart);
    final content = _buffer.toString().trim();
    if (reason != 'stop') {
      return const [
        AgentWireError(
          'Prefill tool request did not finish normally; no tools were executed.',
        ),
      ];
    }
    try {
      final calls = _decode(content);
      return [
        ...calls,
        AgentWireFinish(stopReason: StopReason.toolUse, usage: usage),
      ];
    } on FormatException catch (error) {
      return [AgentWireError('Invalid prefill tool request: ${error.message}')];
    }
  }

  List<AgentWireToolCallDone> _decode(String content) {
    if (!content.startsWith(prefillToolStart) ||
        !content.endsWith(prefillToolEnd)) {
      throw const FormatException('Incomplete tool request framing.');
    }
    final decoded = jsonDecode(
      content.substring(
        prefillToolStart.length,
        content.length - prefillToolEnd.length,
      ),
    );
    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException('Expected a nonempty tool call array.');
    }
    // Validate the whole envelope before returning any calls. Argument schema
    // validation and permissions remain in the existing agent execution path.
    return [for (final call in decoded) _decodeCall(call)];
  }

  AgentWireToolCallDone _decodeCall(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw['name'] is! String ||
        !_names.contains(raw['name']) ||
        raw['arguments'] is! Map<String, dynamic>) {
      throw const FormatException('Unknown tool or invalid argument object.');
    }
    return AgentWireToolCallDone(
      id: 'prefill_${const Uuid().v4()}',
      name: raw['name'] as String,
      arguments: raw['arguments'] as Map<String, dynamic>,
    );
  }

  StopReason _stopReason(String? reason) => switch (reason) {
    'length' || 'max_tokens' => StopReason.length,
    'content_filter' || 'error' => StopReason.error,
    _ => StopReason.stop,
  };
}
