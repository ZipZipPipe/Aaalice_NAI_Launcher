import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/agent_protocol.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/prefill_tool_decoder.dart';

const tools = [Tool(name: 'read', description: 'Read', parameters: {})];
const frame =
    '<launcher_tool_calls>'
    '[{"name":"read","arguments":{"path":"中文.png"}}]'
    '</launcher_tool_calls>';

void main() {
  test('every split point buffers calls until successful completion', () {
    for (var split = 0; split <= frame.length; split++) {
      final decoder = PrefillToolDecoder(tools);
      expect(decoder.push(frame.substring(0, split)), isEmpty);
      expect(decoder.push(frame.substring(split)), isEmpty);
      final events = decoder.finish(reason: 'stop');
      final call = events.whereType<AgentWireToolCallDone>().single;
      expect(call.name, 'read');
      expect(call.arguments, {'path': '中文.png'});
      expect(call.id, startsWith('prefill_'));
      expect(
        events.whereType<AgentWireFinish>().single.stopReason,
        StopReason.toolUse,
      );
      expect(decoder.finish(reason: 'stop'), isEmpty);
      expect(decoder.push(frame), isEmpty);
    }
  });

  test('plain final answers stream without tool framing', () {
    final decoder = PrefillToolDecoder(tools);
    expect(decoder.push('  '), isEmpty);
    final events = [...decoder.push('你好'), ...decoder.push('。')];
    expect(
      events.whereType<AgentWireTextDelta>().map((e) => e.delta).join(),
      '  你好。',
    );
    expect(decoder.finish(reason: 'stop').single, isA<AgentWireFinish>());
  });

  for (final reason in ['length', 'content_filter', 'tool_calls', null]) {
    test('complete-looking tool JSON is never executed on $reason', () {
      final decoder = PrefillToolDecoder(tools)..push(frame);
      final events = decoder.finish(reason: reason);
      expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
      expect(events.single, isA<AgentWireError>());
    });
  }

  for (final invalid in [
    '<launcher_tool_calls>[',
    '<launcher_tool_calls>[]</launcher_tool_calls>',
    '<launcher_tool_calls>{}</launcher_tool_calls>',
    '<launcher_tool_calls>[{"name":"unknown","arguments":{}}]</launcher_tool_calls>',
    '<launcher_tool_calls>[{"name":"read","arguments":"{}"}]</launcher_tool_calls>',
    '<launcher_tool_calls>[{"name":"read","arguments":{}}]</launcher_tool_calls>extra',
    '<launcher_tool_calls>[{"name":"read","arguments":{}},{"name":"bad","arguments":{}}]</launcher_tool_calls>',
  ]) {
    test('malformed batch cannot partially execute: $invalid', () {
      final decoder = PrefillToolDecoder(tools)..push(invalid);
      final events = decoder.finish(reason: 'stop');
      expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
      expect(events.single, isA<AgentWireError>());
    });
  }

  test('cancelled or broken streams cannot emit calls before finish', () {
    final decoder = PrefillToolDecoder(tools);
    expect(decoder.push(frame), isEmpty);
    // The transport emits an error and intentionally never calls finish.
  });

  test('a tag in ordinary prose is never treated as a call', () {
    final decoder = PrefillToolDecoder(tools);
    final events = decoder.push('Example: $frame');
    expect(events.single, isA<AgentWireTextDelta>());
    expect(
      decoder.finish(reason: 'stop').whereType<AgentWireToolCallDone>(),
      isEmpty,
    );
  });
}
