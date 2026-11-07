import '../../../core/agent/agent_types.dart';
import '../../../data/models/agent/agent_settings.dart';

/// Use a prefix only at a user-message boundary, never for summaries or tool
/// continuations. A retry resolves the same prefix without mutating history.
String? resolveAgentPrefill({
  required AgentChatConfig chat,
  required List<Message> messages,
  required bool allowPrefill,
}) {
  if (!allowPrefill ||
      !chat.assistantPrefillEnabled ||
      chat.assistantPrefill.isEmpty ||
      messages.isEmpty ||
      messages.last is! UserMessage) {
    return null;
  }
  return chat.assistantPrefill;
}
