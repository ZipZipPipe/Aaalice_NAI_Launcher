import '../../models/agent_protocol.dart';
import '../../models/prompt_assistant_models.dart';

/// DeepSeek's prefix extension is opt-in and must not leak to unrelated APIs.
/// Custom gateways can select the DeepSeek preset while keeping their own URL.
bool usesDeepSeekPrefill(AgentChatRequest request) =>
    request.provider.preset == ProviderPreset.deepseek ||
    Uri.tryParse(request.provider.baseUrl)?.host == 'api.deepseek.com' ||
    request.reasoningRequest?.api == AgentReasoningApi.deepSeek;

String? validateAssistantPrefill(AgentChatRequest request) {
  if (request.assistantPrefill?.isNotEmpty != true) return null;
  if (request.provider.protocol != ProviderProtocol.openaiChatCompletions ||
      request.provider.preset == ProviderPreset.pollinations ||
      request.provider.type == ProviderType.pollinations) {
    return 'Assistant prefill requires a Chat Completions endpoint that supports '
        'assistant continuation (for example DeepSeek). Disable prefill or '
        'select a compatible provider. Responses, Gemini, Anthropic and Ollama '
        'protocols are not enabled for prefill.';
  }
  return null;
}

/// Route only the official DeepSeek endpoint to beta. Never replace a custom
/// gateway's host/path, nor change model discovery or requests without prefill.
String? resolvePrefillEndpoint(AgentChatRequest request) {
  if (request.assistantPrefill?.isNotEmpty != true) return null;
  final uri = Uri.tryParse(request.provider.baseUrl.trim());
  if (uri == null || uri.host != 'api.deepseek.com') return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (!const {
    '',
    '/v1',
    '/beta',
    '/chat/completions',
    '/v1/chat/completions',
    '/beta/chat/completions',
  }.contains(path)) {
    return null;
  }
  return uri.replace(path: '/beta/chat/completions').toString();
}
