import '../../../core/agent/agent_types.dart';
import '../../../data/models/agent/agent_settings.dart';

/// Resolve a fresh prefix at response boundaries according to the configured
/// injection mode. Summaries opt out. Retries never mutate or append to
/// existing history.
///
/// - [AgentPrefillInjectionMode.everyTurn] keeps the historical behavior: the
///   prefix rides on every model request, including tool continuations.
/// - [AgentPrefillInjectionMode.firstTurn] stops injecting once the
///   conversation carries any assistant reply, so tool continuations run
///   without the prefix and use the provider's native tool protocol.
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
  if (chat.assistantPrefillInjectionMode ==
          AgentPrefillInjectionMode.firstTurn &&
      messages.any((message) => message is AssistantMessage)) {
    return null;
  }
  return chat.assistantPrefill;
}
