import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/data/models/agent/agent_settings.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_prefill.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_stream_bridge.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/agent_protocol.dart';

void main() {
  const config = AgentChatConfig(
    assistantPrefillEnabled: true,
    assistantPrefill: '  start\n',
  );
  test('user boundary preserves exact prefix, summaries never use it', () {
    final messages = <Message>[UserMessage.text('hello')];
    expect(
      resolveAgentPrefill(chat: config, messages: messages, allowPrefill: true),
      '  start\n',
    );
    expect(
      resolveAgentPrefill(
        chat: config,
        messages: messages,
        allowPrefill: false,
      ),
      isNull,
    );
    expect(
      resolveAgentPrefill(
        chat: const AgentChatConfig(),
        messages: messages,
        allowPrefill: true,
      ),
      isNull,
    );
    expect(
      resolveAgentPrefill(
        chat: config.copyWith(assistantPrefill: ''),
        messages: messages,
        allowPrefill: true,
      ),
      isNull,
    );
  });
  test('every nonempty response boundary receives a fresh prefix', () {
    for (final messages in <List<Message>>[
      [ToolResultMessage(toolCallId: '1', toolName: 'read', content: [])],
      [AssistantMessage(content: [], stopReason: StopReason.stop)],
    ]) {
      expect(
        resolveAgentPrefill(
          chat: config,
          messages: messages,
          allowPrefill: true,
        ),
        '  start\n',
      );
    }
  });
  test('first-turn mode stops injecting after any assistant reply', () {
    final chat = config.copyWith(
      assistantPrefillInjectionMode: AgentPrefillInjectionMode.firstTurn,
    );
    const firstTurn = <Message>[UserMessage.text('hello')];
    expect(
      resolveAgentPrefill(chat: chat, messages: firstTurn, allowPrefill: true),
      '  start\n',
    );
    final continuation = <Message>[
      UserMessage.text('hello'),
      AssistantMessage(content: [], stopReason: StopReason.toolUse),
      ToolResultMessage(toolCallId: '1', toolName: 'read', content: []),
    ];
    expect(
      resolveAgentPrefill(
        chat: chat,
        messages: continuation,
        allowPrefill: true,
      ),
      isNull,
    );
    // 每轮模式在相同历史下仍注入。
    expect(
      resolveAgentPrefill(
        chat: config,
        messages: continuation,
        allowPrefill: true,
      ),
      '  start\n',
    );
    // 助手回复为空内容也算已开轮：仅首轮模式随即收手。
    final assistantOnly = <Message>[
      AssistantMessage(content: [], stopReason: StopReason.stop),
    ];
    expect(
      resolveAgentPrefill(
        chat: chat,
        messages: assistantOnly,
        allowPrefill: true,
      ),
      isNull,
    );
  });
  test('empty context is not prefilled', () {
    expect(
      resolveAgentPrefill(chat: config, messages: [], allowPrefill: true),
      isNull,
    );
  });
  test(
    'thinking prefix is joined once and never appears in answer text',
    () async {
      final stream = agentWireEventStream(
        Stream.fromIterable(const <AgentWireEvent>[
          AgentWireThinkingDelta('continued'),
          AgentWireTextDelta('answer'),
          AgentWireFinish(stopReason: StopReason.stop),
        ]),
        assistantPrefill: '  start\n',
        prefillThinking: true,
      );
      final events = await stream.stream.toList();
      final result = await stream.result();
      expect(result.text, 'answer');
      expect(
        result.content.whereType<AssistantThinkingContent>().single.thinking,
        '  start\ncontinued',
      );
      expect(
        events.whereType<AmThinkingDelta>().map((e) => e.delta).join(),
        '  start\ncontinued',
      );
      expect(
        events.whereType<AmTextDelta>().map((e) => e.delta).join(),
        'answer',
      );
    },
  );
  test('thinking prefix does not fabricate content on early failure', () async {
    final stream = agentWireEventStream(
      Stream.value(const AgentWireError('HTTP 400')),
      assistantPrefill: 'prefix',
      prefillThinking: true,
    );
    final result = await stream.result();
    expect(result.content, isEmpty);
    expect(result.stopReason, StopReason.error);
  });
  test(
    'stream merges prefix once and records full text in final history',
    () async {
      final stream = agentWireEventStream(
        Stream.fromIterable(const <AgentWireEvent>[
          AgentWireThinkingDelta('thinking'),
          AgentWireTextDelta('part'),
          AgentWireTextDelta(' two'),
          AgentWireFinish(stopReason: StopReason.stop),
        ]),
        assistantPrefill: '  start\n',
      );
      final events = await stream.stream.toList();
      final result = await stream.result();
      expect(result.text, '  start\npart two');
      expect(
        events.whereType<AmTextDelta>().map((e) => e.delta).join(),
        result.text,
      );
      expect(result.content.first, isA<AssistantThinkingContent>());
    },
  );
  test('early errors and cancellation never fabricate prefix text', () async {
    for (final error in ['HTTP 400 unsupported', 'aborted']) {
      final stream = agentWireEventStream(
        Stream.value(AgentWireError(error)),
        assistantPrefill: 'prefix',
      );
      final result = await stream.result();
      expect(result.text, isEmpty);
      expect(
        result.stopReason,
        error == 'aborted' ? StopReason.aborted : StopReason.error,
      );
    }
  });
  test(
    'partial cancellation preserves only the text already received',
    () async {
      final stream = agentWireEventStream(
        Stream.fromIterable(const <AgentWireEvent>[
          AgentWireTextDelta('partial'),
          AgentWireError('aborted'),
        ]),
        assistantPrefill: 'prefix ',
      );
      final result = await stream.result();
      expect(result.text, 'prefix partial');
      expect(result.stopReason, StopReason.aborted);
    },
  );
  test('truncated and empty-delta streams do not fabricate a prefix', () async {
    final stream = agentWireEventStream(
      Stream.fromIterable(const <AgentWireEvent>[
        AgentWireTextDelta(''),
        AgentWireThinkingDelta('thinking'),
      ]),
      assistantPrefill: 'prefix',
    );
    final result = await stream.result();
    expect(result.text, isEmpty);
    expect(result.stopReason, StopReason.error);
  });
  test('disabled prefill leaves the original stream unchanged', () async {
    final stream = agentWireEventStream(
      Stream.fromIterable(const <AgentWireEvent>[
        AgentWireTextDelta('text'),
        AgentWireFinish(stopReason: StopReason.stop),
      ]),
    );
    expect((await stream.result()).text, 'text');
  });
  test('repeated terminal events do not inject the prefix twice', () async {
    final stream = agentWireEventStream(
      Stream.fromIterable(const <AgentWireEvent>[
        AgentWireFinish(stopReason: StopReason.stop),
        AgentWireFinish(stopReason: StopReason.stop),
      ]),
      assistantPrefill: 'prefix',
    );
    expect((await stream.result()).text, 'prefix');
  });
  test(
    'empty successful continuation still preserves the supplied prefix',
    () async {
      final stream = agentWireEventStream(
        Stream.value(const AgentWireFinish(stopReason: StopReason.stop)),
        assistantPrefill: 'prefix',
      );
      expect((await stream.result()).text, 'prefix');
    },
  );
  test(
    'tool call preserves prefix and tool call together for replay',
    () async {
      final stream = agentWireEventStream(
        Stream.fromIterable(const <AgentWireEvent>[
          AgentWireToolCallDone(id: '1', name: 'read', arguments: {}),
          AgentWireFinish(stopReason: StopReason.toolUse),
        ]),
        assistantPrefill: 'prefix',
      );
      final result = await stream.result();
      expect(result.text, 'prefix');
      expect(result.toolCalls.single.id, '1');
    },
  );
}
