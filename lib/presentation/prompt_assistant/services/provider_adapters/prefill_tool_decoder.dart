import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/agent/agent_types.dart';
import '../../models/agent_protocol.dart';
import 'thinking_prefill_messages.dart';

/// Streams ordinary text, but buffers an explicitly framed tool request until
/// the response finishes normally. Partial, cancelled or malformed batches
/// never emit executable tool events.
class PrefillToolDecoder {
  PrefillToolDecoder(List<Tool> tools)
    : _names = tools.map((tool) => tool.name).toSet();

  final Set<String> _names;
  final StringBuffer _buffer = StringBuffer();
  bool _plainText = false;
  bool _toolFrame = false;
  bool _finished = false;
  static const _maxToolCharacters = 1024 * 1024;

  List<AgentWireEvent> push(String delta) {
    if (_finished || delta.isEmpty) return const [];
    if (_plainText) return [AgentWireTextDelta(delta)];
    _buffer.write(delta);
    if (_toolFrame) {
      _checkSize();
      return const [];
    }
    final content = _buffer.toString().trimLeft();
    if (content.startsWith(prefillToolStart)) {
      _toolFrame = true;
      _checkSize();
      return const [];
    }
    if (prefillToolStart.startsWith(content)) {
      _checkSize();
      return const [];
    }
    _plainText = true;
    return [AgentWireTextDelta(_buffer.toString())];
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
    if (_plainText) {
      return [AgentWireFinish(stopReason: _stopReason(reason), usage: usage)];
    }
    final content = _buffer.toString().trim();
    if (content.isEmpty) {
      return [AgentWireFinish(stopReason: _stopReason(reason), usage: usage)];
    }
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
