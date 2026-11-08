import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_loop.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/data/models/agent/agent_settings.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_api_client.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_prefill.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_stream_bridge.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/agent_protocol.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/prompt_assistant_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/thinking_prefill_messages.dart';

const prefix = '  我先检查当前状态。\n';
const toolPreamble = '这就用这套标签重绘一次，看效果。\n\n';
const model = Model(id: 'test', name: 'Test', api: 'test', provider: 'test');
const chat = AgentChatConfig(
  assistantPrefillEnabled: true,
  assistantPrefill: prefix,
);

void main() {
  for (final preamble in ['', toolPreamble]) {
    test('real agent loop prefills thinking across two tool executions '
        '(${preamble.isEmpty ? 'bare' : 'mixed'} tool reply)', () async {
      final run = await _run(toolPreamble: preamble);
      expect(run.tool.executions, 2);
      expect(run.approvals, 2);
      expect(run.service.requests, hasLength(3));
      expect(run.messages.whereType<ToolResultMessage>(), hasLength(2));
      final assistants = run.messages.whereType<AssistantMessage>().toList();
      expect(assistants, hasLength(3));
      for (final message in assistants) {
        expect(
          message.content.whereType<AssistantThinkingContent>().single.thinking,
          '$prefix继续思考',
        );
        expect(message.text, isNot(contains(prefix)));
        expect(message.text, isNot(contains('<launcher_tool_calls>')));
      }
      expect(assistants.take(2).map((m) => m.text), [preamble, preamble]);
      expect(assistants.last.text, '已完成。');
      final ids = assistants
          .expand((m) => m.toolCalls)
          .map((c) => c.id)
          .toSet();
      expect(ids, hasLength(2));
      for (final payload in run.service.requests) {
        final messages = payload['messages'] as List;
        expect(messages.last, {
          'role': 'assistant',
          'content': '',
          'reasoning_content': prefix,
          'prefix': true,
        });
        expect(payload.containsKey('tools'), isFalse);
        expect(payload.containsKey('tool_choice'), isFalse);
        expect(messages.where((m) => m['prefix'] == true), hasLength(1));
        expect(
          messages.every(
            (m) => m['role'] != 'tool' && !m.containsKey('tool_calls'),
          ),
          isTrue,
        );
      }
      final resumed = run.service.requests.last['messages'] as List;
      final observations = resumed.where(
        (m) =>
            m['role'] == 'user' &&
            (m['content'] as String).contains('launcher_tool_result'),
      );
      expect(observations, hasLength(2));
    });
  }

  test(
    'existing permissions still block text-protocol tool execution',
    () async {
      final run = await _run(
        blocked: true,
        toolRounds: 1,
        toolPreamble: toolPreamble,
      );
      expect(run.approvals, 1);
      expect(run.tool.executions, 0);
      expect(
        run.messages.whereType<ToolResultMessage>().single.isError,
        isTrue,
      );
      expect(run.service.requests, hasLength(2));
      expect(
        jsonEncode(run.service.requests.last),
        contains('blocked by test'),
      );
    },
  );

  test(
    'existing argument validation runs before permissions and execution',
    () async {
      final run = await _run(
        arguments: {'path': 42},
        toolRounds: 1,
        toolPreamble: toolPreamble,
      );
      expect(run.approvals, 0);
      expect(run.tool.executions, 0);
      expect(
        run.messages.whereType<ToolResultMessage>().single.isError,
        isTrue,
      );
      expect(run.service.requests, hasLength(2));
    },
  );

  for (final finish in ['length', 'content_filter', null]) {
    test(
      'transport finish $finish cannot execute a complete tool envelope',
      () async {
        final run = await _run(
          finish: finish,
          toolRounds: 1,
          toolPreamble: toolPreamble,
        );
        expect(run.tool.executions, 0);
        expect(run.approvals, 0);
        expect(run.service.requests, hasLength(1));
        expect(
          (run.messages.last as AssistantMessage).stopReason,
          StopReason.error,
        );
      },
    );
  }

  test(
    'empty thinking-only continuation restarts with a reminder and recovers',
    () async {
      final run = await _run(toolRounds: 1, emptyContinuations: 1);
      // 首轮工具 + 一次空续跑（重试）+ 成功收尾。
      expect(run.service.requests, hasLength(3));
      expect(run.tool.executions, 1);
      final assistants = run.messages.whereType<AssistantMessage>().toList();
      expect(assistants, hasLength(2));
      // 空续跑的思考被丢弃：恢复后的助手消息只含预填 + 继续思考。
      for (final message in assistants) {
        expect(message.text, isNot(contains('<launcher_tool_calls>')));
        expect(message.text, isNot(contains('REMINDER')));
      }
      expect(assistants.last.text, '已完成。');
      // 重试请求的思考前缀带有提醒标记。
      final retryPayload = run.service.requests[2];
      final prefixMessage = (retryPayload['messages'] as List).last;
      expect(
        prefixMessage['reasoning_content'] as String,
        startsWith('REMINDER'),
      );
    },
  );

  test(
    'persistently empty continuation surfaces an explicit error',
    () async {
      final run = await _run(toolRounds: 1, emptyContinuations: 99);
      expect(run.service.requests, hasLength(3));
      final last = run.messages.last as AssistantMessage;
      expect(last.stopReason, StopReason.error);
      expect(
        last.errorMessage,
        contains('no answer text and no tool request'),
      );
    },
  );

  test(
    'cancellation after tool text cannot execute the pending request',
    () async {
      final run = await _run(
        cancelAfterContent: true,
        toolRounds: 1,
        toolPreamble: toolPreamble,
      );
      expect(run.tool.executions, 0);
      expect(run.approvals, 0);
      expect(
        (run.messages.last as AssistantMessage).stopReason,
        StopReason.aborted,
      );
    },
  );

  test(
    'tool images remain image parts and respect provider input capability',
    () {
      const image = ImageContent(
        source: ImageSource.base64(
          mimeType: 'image/png',
          base64Data: 'aGVsbG8=',
        ),
      );
      final messages = <Message>[
        ToolResultMessage(
          toolCallId: 'c1',
          toolName: 'read',
          content: [
            const ToolResultTextContent('image'),
            const ToolResultImageContent(image),
          ],
          isError: true,
        ),
      ];
      for (final allowImages in [true, false]) {
        final request = _request(messages, [], allowImages: allowImages);
        final wire = buildThinkingPrefillMessages(request);
        final content = wire.first['content'];
        if (allowImages) {
          final parts = content as List;
          expect(
            parts.last['image_url']['url'],
            'data:image/png;base64,aGVsbG8=',
          );
          expect(parts.first['text'], contains('"is_error":true'));
        } else {
          expect(content, isA<String>());
          expect(content, isNot(contains('aGVsbG8=')));
        }
      }
    },
  );
}

AgentChatRequest _request(
  List<Message> messages,
  List<Tool> tools, {
  bool allowImages = true,
}) => AgentChatRequest(
  sessionId: 'test',
  provider: ProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    preset: ProviderPreset.deepseek,
    allowImageInput: allowImages,
  ),
  model: 'deepseek-test',
  systemPrompt: '',
  apiKey: null,
  messages: List.of(messages),
  tools: tools,
  reasoningRequest: const AgentReasoningRequest(
    api: AgentReasoningApi.deepSeek,
    enabled: true,
    effort: 'max',
    preserveReasoningContent: true,
  ),
  assistantPrefill: resolveAgentPrefill(
    chat: chat,
    messages: messages,
    allowPrefill: true,
  ),
);

Future<_Run> _run({
  bool blocked = false,
  Map<String, dynamic> arguments = const {'path': '角色.png'},
  int toolRounds = 2,
  String? finish = 'stop',
  bool cancelAfterContent = false,
  String toolPreamble = '',
  int emptyContinuations = 0,
}) async {
  final service = _StrictService(
    arguments,
    toolRounds,
    finish,
    cancelAfterContent,
    toolPreamble: toolPreamble,
    emptyContinuations: emptyContinuations,
  );
  final dio = Dio()..httpClientAdapter = service;
  final client = AgentApiClient(dio);
  final tool = _ReadTool();
  var approvals = 0;
  final loop = agentLoop(
    [UserMessage.text('检查角色并完成任务')],
    AgentContext(systemPrompt: '', messages: const [], tools: [tool]),
    AgentLoopConfig(
      model: model,
      convertToLlm: (messages) async => messages,
      beforeToolCall: (context, signal) async {
        approvals++;
        return blocked
            ? const BeforeToolCallResult(block: true, reason: 'blocked by test')
            : null;
      },
    ),
    null,
    (model, context, [options]) {
      final request = _request(context.messages, [tool]);
      return agentWireEventStream(
        client.complete(request),
        assistantPrefill: request.assistantPrefill,
        prefillThinking: true,
      );
    },
  );
  try {
    await loop.stream.drain<void>();
    return _Run(await loop.result(), service, tool, approvals);
  } finally {
    dio.close(force: true);
  }
}

class _Run {
  _Run(this.messages, this.service, this.tool, this.approvals);
  final List<Message> messages;
  final _StrictService service;
  final _ReadTool tool;
  final int approvals;
}

class _ReadTool extends AgentTool {
  _ReadTool()
    : super(
        name: 'read',
        description: 'Read a file',
        label: 'Read',
        parameters: const {
          'type': 'object',
          'required': ['path'],
          'properties': {
            'path': {'type': 'string'},
          },
        },
      );
  int executions = 0;
  @override
  Future<AgentToolResult> execute(
    String id,
    Map<String, dynamic> params, [
    AbortSignal? signal,
    AgentToolUpdateCallback? onUpdate,
  ]) async {
    executions++;
    return AgentToolResult(
      content: [const ToolResultTextContent('观察结果')],
      details: null,
    );
  }
}

/// Mirrors the DeepSeek request constraints which the original fixed-200 mock
/// omitted. This is a protocol integration test, not a live provider test.
class _StrictService implements HttpClientAdapter {
  _StrictService(
    this.arguments,
    this.toolRounds,
    this.finish,
    this.cancelAfterContent, {
    this.toolPreamble = '',
    this.emptyContinuations = 0,
  });
  final Map<String, dynamic> arguments;
  final int toolRounds;
  final String? finish;
  final bool cancelAfterContent;
  final String toolPreamble;
  final int emptyContinuations;
  final requests = <Map<String, dynamic>>[];
  var _continuationRequests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    final payload =
        jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
    requests.add(payload);
    final messages = payload['messages'] as List;
    if (payload.containsKey('tools') ||
        payload.containsKey('tool_choice') ||
        messages.any(
          (m) => m['role'] == 'tool' || m.containsKey('tool_calls'),
        ) ||
        messages.last['content'] != '' ||
        payload['thinking']['type'] != 'enabled') {
      return ResponseBody.fromString(
        '{"error":{"message":"incompatible prefix request"}}',
        400,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    // 重试请求的思考前缀带提醒；普通请求保持用户原样前缀。
    final expectedPrefix = (messages.last['reasoning_content'] as String)
        .replaceAll(RegExp(r'^REMINDER[^\n]*\n\n'), '');
    if (expectedPrefix != prefix) {
      return ResponseBody.fromString(
        '{"error":{"message":"incompatible prefix request"}}',
        400,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    final seenToolResults = messages
        .where((m) => m['role'] == 'user')
        .where(
          (m) =>
              m['content'] is String &&
              (m['content'] as String).contains('launcher_tool_result'),
        )
        .length;
    var content = '已完成。';
    if (seenToolResults < toolRounds) {
      content =
          '$toolPreamble<launcher_tool_calls>${jsonEncode([
              {'name': 'read', 'arguments': arguments},
            ])}</launcher_tool_calls>';
    } else {
      // 按续跑请求序号模拟真实故障：前 N 次续跑只输出思考、正文为空
      // （含适配器带提醒的重试请求），其后恢复正常收尾。
      _continuationRequests++;
      if (_continuationRequests <= emptyContinuations) {
        content = '';
      }
    }
    String event(Map<String, dynamic> delta, [String? stop]) =>
        'data: ${jsonEncode({
          'choices': [
            {'delta': delta, if (stop != null) 'finish_reason': stop},
          ],
        })}\n\n';
    final output = StringBuffer(event({'reasoning_content': '继续思考'}));
    for (final char in content.runes) {
      output.write(event({'content': String.fromCharCode(char)}));
    }
    if (!cancelAfterContent) {
      if (finish != null) output.write(event({}, finish));
      output.write('data: [DONE]\n\n');
    }
    final bytes = utf8.encode(output.toString());
    Stream<Uint8List> stream() async* {
      // Split SSE records and multibyte UTF-8 across transport chunks.
      for (var i = 0; i < bytes.length; i += 7) {
        yield Uint8List.fromList(
          bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7),
        );
      }
      if (cancelAfterContent) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      }
    }

    return ResponseBody(
      stream(),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
