import '../../../core/agent/agent_types.dart';
import '../../../data/models/agent/agent_settings.dart';

/// Resolve a fresh prefix at every response boundary, including tool results.
/// Summaries opt out. Retries never mutate or append to existing history.
String? resolveAgentPrefill({
  required AgentChatConfig chat,
  required List<Message> messages,
  required bool allowPrefill,
}) {
  if (!allowPrefill ||
      !chat.assistantPrefillEnabled ||
      chat.assistantPrefill.isEmpty ||
      messages.isEmpty) {
    return null;
  }
  return chat.assistantPrefill;
}
