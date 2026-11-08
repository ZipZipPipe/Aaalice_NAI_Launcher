import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/agent_protocol.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/prefill_tool_decoder.dart';

const tools = [Tool(name: 'read', description: 'Read', parameters: {})];
const frame =
    '<launcher_tool_calls>'
    '[{"name":"read","arguments":{"path":"中文.png"}}]'
    '</launcher_tool_calls>';
const introduction = '这就用这套标签重绘一次，看效果。\n\n';

void main() {
  test('prose before a standalone tool frame still executes', () {
    final decoder = PrefillToolDecoder(tools);
    final streamed = decoder.push('$introduction$frame');
    expect(
      streamed.whereType<AgentWireTextDelta>().map((e) => e.delta).join(),
      introduction,
    );
    expect(streamed.whereType<AgentWireToolCallDone>(), isEmpty);
    final events = decoder.finish(reason: 'stop');
    expect(events.whereType<AgentWireToolCallDone>().single.name, 'read');
    expect(
      events.whereType<AgentWireFinish>().single.stopReason,
      StopReason.toolUse,
    );
  });

  test('mixed replies tolerate every split point and line ending', () {
    for (final newline in ['\n', '\r\n', '\r']) {
      final prose =
          '先核对角色特征。$newline'
          '准备写入。$newline';
      final content = '$prose$frame  $newline';
      for (var split = 0; split <= content.length; split++) {
        final decoder = PrefillToolDecoder(tools);
        final streamed = [
          ...decoder.push(content.substring(0, split)),
          ...decoder.push(content.substring(split)),
        ];
        expect(_text(streamed), prose);
        expect(streamed.whereType<AgentWireToolCallDone>(), isEmpty);
        final events = decoder.finish(reason: 'stop');
        expect(events.whereType<AgentWireToolCallDone>().single.name, 'read');
        expect(
          events.whereType<AgentWireFinish>().single.stopReason,
          StopReason.toolUse,
        );
      }
    }
  });

  test('mixed replies buffer tool frames across single-character deltas', () {
    final decoder = PrefillToolDecoder(tools);
    final streamed = [
      for (final character in '$introduction$frame'.split(''))
        ...decoder.push(character),
    ];
    expect(_text(streamed), introduction);
    expect(streamed.whereType<AgentWireToolCallDone>(), isEmpty);
    expect(
      decoder.finish(reason: 'stop').whereType<AgentWireToolCallDone>(),
      hasLength(1),
    );
  });

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
    final events = [
      ...decoder.push('  '),
      ...decoder.push('你好'),
      ...decoder.push('。'),
    ];
    expect(
      events.whereType<AgentWireTextDelta>().map((e) => e.delta).join(),
      '  你好。',
    );
    expect(decoder.finish(reason: 'stop').single, isA<AgentWireFinish>());
  });

  for (final reason in [
    'length',
    'content_filter',
    'tool_calls',
    'aborted',
    'insufficient_system_resource',
    null,
  ]) {
    test('complete-looking tool JSON is never executed on $reason', () {
      for (final prose in ['', introduction]) {
        final decoder = PrefillToolDecoder(tools)..push('$prose$frame');
        final events = decoder.finish(reason: reason);
        expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
        expect(events.single, isA<AgentWireError>());
      }
    });
  }

  for (final invalid in [
    '<launcher_tool_call',
    '<launcher_tool_calls>[',
    '<launcher_tool_calls>[]</launcher_tool_calls>',
    '<launcher_tool_calls>{}</launcher_tool_calls>',
    '<launcher_tool_calls>[{"name":"unknown","arguments":{}}]</launcher_tool_calls>',
    '<launcher_tool_calls>[{"name":"read","arguments":"{}"}]</launcher_tool_calls>',
    '<launcher_tool_calls>[{"name":"read","arguments":{}}]</launcher_tool_calls>extra',
    '<launcher_tool_calls>[{"name":"read","arguments":{}},{"name":"bad","arguments":{}}]</launcher_tool_calls>',
    '$frame\n$frame',
  ]) {
    test('malformed batch cannot partially execute: $invalid', () {
      for (final prose in ['', introduction]) {
        final decoder = PrefillToolDecoder(tools)..push('$prose$invalid');
        final events = decoder.finish(reason: 'stop');
        expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
        expect(events.single, isA<AgentWireError>());
      }
    });
  }

  test('cancelled or broken streams cannot emit calls before finish', () {
    final decoder = PrefillToolDecoder(tools);
    final streamed = decoder.push('$introduction$frame');
    expect(_text(streamed), introduction);
    expect(streamed.whereType<AgentWireToolCallDone>(), isEmpty);
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

  for (final example in [
    'Example: $frame',
    '`$frame`',
    '> $frame',
    '    $frame',
    '\t$frame',
    '```json\n$frame\n```',
    '~~~json\n$frame\n~~~',
    '````\n```\n$frame\n````',
    '```\n$frame',
    '```\n``` still inside code\n$frame',
  ]) {
    test('quoted protocol stays literal across all splits: $example', () {
      for (var split = 0; split <= example.length; split++) {
        final decoder = PrefillToolDecoder(tools);
        final events = [
          ...decoder.push(example.substring(0, split)),
          ...decoder.push(example.substring(split)),
          ...decoder.finish(reason: 'stop'),
        ];
        expect(_text(events), example);
        expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
        expect(events.whereType<AgentWireError>(), isEmpty);
      }
    });
  }

  test('a real trailing frame works after a closed fenced example', () {
    const prose = '协议示例：\n```json\n$frame\n```\n现在执行：\n';
    final decoder = PrefillToolDecoder(tools);
    final streamed = [
      for (final character in '$prose$frame'.split(''))
        ...decoder.push(character),
    ];
    expect(_text(streamed), prose);
    final events = decoder.finish(reason: 'stop');
    expect(events.whereType<AgentWireToolCallDone>(), hasLength(1));
  });

  test('unrelated HTML-like text is preserved when a tag prefix diverges', () {
    const prose =
        '说明：\n<launcher_tooltip>文本</launcher_tooltip>\n<aside>注释</aside>';
    final decoder = PrefillToolDecoder(tools);
    final events = [
      for (final character in prose.split('')) ...decoder.push(character),
      ...decoder.finish(reason: 'stop'),
    ];
    expect(_text(events), prose);
    expect(events.whereType<AgentWireError>(), isEmpty);
    expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
  });

  for (final prose in ['<', '比较结果：\n<l', '说明：\n<launcher']) {
    test('short non-tool prefixes remain ordinary text: $prose', () {
      final decoder = PrefillToolDecoder(tools);
      final events = [
        ...decoder.push(prose),
        ...decoder.finish(reason: 'stop'),
      ];
      expect(_text(events), prose);
      expect(events.whereType<AgentWireError>(), isEmpty);
      expect(events.whereType<AgentWireToolCallDone>(), isEmpty);
    });
  }

  test('mixed multi-tool replies receive new IDs instead of replayed IDs', () {
    final decoder = PrefillToolDecoder([
      ...tools,
      const Tool(name: 'write', description: 'Write', parameters: {}),
    ]);
    final streamed = decoder.push(
      '$introduction<launcher_tool_calls>'
      '[{"id":"old-read","name":"read","arguments":{"path":"角色.png"}},'
      '{"id":"old-write","name":"write","arguments":{"text":"标签"}}]'
      '</launcher_tool_calls>',
    );
    expect(_text(streamed), introduction);
    final calls = decoder
        .finish(reason: 'stop')
        .whereType<AgentWireToolCallDone>()
        .toList();
    expect(calls.map((call) => call.name), ['read', 'write']);
    expect(calls.map((call) => call.id).toSet(), hasLength(2));
    expect(calls.every((call) => call.id.startsWith('prefill_')), isTrue);
  });

  test('oversized mixed tool frames fail without executable events', () {
    final decoder = PrefillToolDecoder(tools);
    expect(
      () => decoder.push(
        '$introduction<launcher_tool_calls>${'x' * (2 * 1024 * 1024)}',
      ),
      throwsFormatException,
    );
  });
}

String _text(Iterable<AgentWireEvent> events) =>
    events.whereType<AgentWireTextDelta>().map((event) => event.delta).join();
