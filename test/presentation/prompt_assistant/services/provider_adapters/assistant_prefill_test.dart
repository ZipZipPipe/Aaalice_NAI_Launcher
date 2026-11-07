import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_api_client.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/agent_protocol.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/prompt_assistant_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/openai_chat_completions_adapter.dart';

AgentChatRequest request({
  String base = 'https://api.deepseek.com',
  ProviderPreset? preset = ProviderPreset.deepseek,
  ProviderProtocol protocol = ProviderProtocol.openaiChatCompletions,
  String? prefix = '  prefix\n',
  String? reasoning = 'max',
  List<Message>? messages,
}) => AgentChatRequest(
  sessionId: 'test',
  provider: ProviderConfig(
    id: 'test',
    name: 'Test',
    baseUrl: base,
    preset: preset,
    protocol: protocol,
  ),
  model: 'test-model',
  systemPrompt: 'system',
  apiKey: null,
  assistantPrefill: prefix,
  reasoning: reasoning,
  messages: messages ?? [UserMessage.text('hello')],
  tools: const [Tool(name: 'read', description: 'read', parameters: {})],
);

void main() {
  for (final path in [
    '',
    '/',
    '/v1',
    '/beta',
    '/beta/',
    '/chat/completions',
    '/v1/chat/completions',
    '/beta/chat/completions',
  ]) {
    test('DeepSeek prefill resolves official $path to beta', () async {
      final adapter = CaptureAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await AgentApiClient(
        dio,
      ).complete(request(base: 'https://api.deepseek.com$path')).toList();
      expect(
        adapter.options!.uri.toString(),
        'https://api.deepseek.com/beta/chat/completions',
      );
      final payload = adapter.options!.data as Map;
      expect((payload['messages'] as List).last, {
        'role': 'assistant',
        'content': '',
        'reasoning_content': '  prefix\n',
        'prefix': true,
      });
      expect(payload.containsKey('tools'), isFalse);
      expect(payload.containsKey('tool_choice'), isFalse);
      expect(payload['thinking'], {'type': 'enabled'});
    });
  }
  for (final prefix in [null, '']) {
    test(
      'empty or absent prefill preserves existing request ($prefix)',
      () async {
        final adapter = CaptureAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(dio.close);
        await AgentApiClient(dio).complete(request(prefix: prefix)).toList();
        expect(adapter.options!.uri.path, '/chat/completions');
        expect(
          (adapter.options!.data['messages'] as List).last['role'],
          'user',
        );
        expect(adapter.options!.data['tools'], isNotEmpty);
        expect(adapter.options!.data['tool_choice'], 'auto');
      },
    );
  }
  test(
    'generic compatibility adds assistant without DeepSeek-only flags',
    () async {
      final adapter = CaptureAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await AgentApiClient(dio)
          .complete(
            request(base: 'https://gateway.test/custom/v1', preset: null),
          )
          .toList();
      expect(
        adapter.options!.uri.toString(),
        'https://gateway.test/custom/v1/chat/completions',
      );
      expect((adapter.options!.data['messages'] as List).last, {
        'role': 'assistant',
        'content': '  prefix\n',
      });
    },
  );
  test(
    'DeepSeek preset preserves custom gateway and adds prefix flag',
    () async {
      final adapter = CaptureAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await AgentApiClient(dio)
          .complete(
            request(base: 'https://gateway.test/proxy/chat/completions'),
          )
          .toList();
      expect(
        adapter.options!.uri.toString(),
        'https://gateway.test/proxy/chat/completions',
      );
      expect((adapter.options!.data['messages'] as List).last['prefix'], true);
    },
  );
  for (final protocol in ProviderProtocol.values.where(
    (p) => p != ProviderProtocol.openaiChatCompletions,
  )) {
    test(
      'unsupported $protocol reports error without network request',
      () async {
        final adapter = CaptureAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(dio.close);
        final events = await AgentApiClient(
          dio,
        ).complete(request(protocol: protocol)).toList();
        expect(events.single, isA<AgentWireError>());
        expect(adapter.options, isNull);
      },
    );
  }
  test('HTTP errors stay errors; no silent downgrade or retry', () async {
    final adapter = CaptureAdapter(status: 400);
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final events = await AgentApiClient(dio).complete(request()).toList();
    expect(events.whereType<AgentWireError>(), hasLength(1));
    expect(events.whereType<AgentWireTextDelta>(), isEmpty);
    expect(adapter.calls, 1);
  });
  test('beta model discovery uses regular official models endpoint', () async {
    final adapter = CaptureAdapter(models: true);
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final models = await const OpenAiChatCompletionsAdapter().fetchModels(
      dio: dio,
      provider: request(base: 'https://api.deepseek.com/beta').provider,
      apiKey: null,
    );
    expect(models, ['test-model']);
    expect(adapter.options!.uri.toString(), 'https://api.deepseek.com/models');
  });
  test('tool history is serialized without mutating stored messages', () async {
    final messages = <Message>[
      AssistantMessage(
        content: [
          const AssistantTextContent('old'),
          const ToolCallContent(id: 'call', name: 'read', arguments: {}),
        ],
        stopReason: StopReason.toolUse,
      ),
      ToolResultMessage(
        toolCallId: 'call',
        toolName: 'read',
        content: [const ToolResultTextContent('result')],
      ),
      UserMessage.text('new'),
    ];
    final adapter = CaptureAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    await AgentApiClient(dio).complete(request(messages: messages)).toList();
    final wire = adapter.options!.data['messages'] as List;
    expect(wire[1]['content'], startsWith('old\n<launcher_tool_calls>'));
    expect(wire[1]['content'], contains('"id":"call"'));
    expect((wire[1] as Map).containsKey('prefix'), isFalse);
    expect(wire[2]['role'], 'user');
    expect(wire[2]['content'], contains('"id":"call"'));
    expect(
      wire.every((m) => m['role'] != 'tool' && !m.containsKey('tool_calls')),
      isTrue,
    );
    expect(wire.last['prefix'], true);
    expect(messages, hasLength(3));
    expect((messages.first as AssistantMessage).text, 'old');
  });
  test(
    'thinking off reports an actionable error before network access',
    () async {
      final adapter = CaptureAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final events = await AgentApiClient(
        dio,
      ).complete(request(reasoning: null)).toList();
      expect(events.single, isA<AgentWireError>());
      expect(
        (events.single as AgentWireError).message,
        contains('thinking mode'),
      );
      expect(adapter.calls, 0);
    },
  );
  test(
    'retry reuses the exact prefix without changing stored history',
    () async {
      final adapter = CaptureAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final input = request();
      for (var attempt = 0; attempt < 2; attempt++) {
        await AgentApiClient(dio).complete(input).toList();
        final messages = adapter.options!.data['messages'] as List;
        expect(messages.where((m) => m['prefix'] == true), hasLength(1));
        expect(messages.last['reasoning_content'], '  prefix\n');
        expect(input.messages, hasLength(1));
        expect(input.messages.single, isA<UserMessage>());
      }
      expect(adapter.calls, 2);
    },
  );
}

class CaptureAdapter implements HttpClientAdapter {
  CaptureAdapter({this.status = 200, this.models = false});
  final int status;
  final bool models;
  RequestOptions? options;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    calls++;
    if (models) {
      return ResponseBody.fromString(
        jsonEncode({
          'data': [
            {'id': 'test-model'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      status == 200
          ? 'data: {"choices":[{"delta":{"content":"continued"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n'
          : '{"error":{"message":"unsupported prefill"}}',
      status,
      headers: {
        Headers.contentTypeHeader: [
          status == 200 ? 'text/event-stream' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
