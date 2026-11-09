import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/data/models/agent/agent_settings.dart';
import 'package:nai_launcher/presentation/agent_settings/providers/agent_settings_provider.dart';
import 'package:nai_launcher/presentation/widgets/common/app_toast.dart';
import 'package:nai_launcher/presentation/widgets/common/horizontal_action_strip.dart';
import '../../widgets/settings_card.dart';

/// 助手预填：按注入模式随请求发送，DeepSeek 用于思考开头。
///
/// 内容保持空白，不提供示例或默认值；开关、注入模式与文本框一起保存。
class AssistantPrefillEditor extends ConsumerStatefulWidget {
  const AssistantPrefillEditor({super.key});

  @override
  ConsumerState<AssistantPrefillEditor> createState() =>
      _AssistantPrefillEditorState();
}

class _AssistantPrefillEditorState
    extends ConsumerState<AssistantPrefillEditor> {
  late final TextEditingController _controller;
  late bool _enabled;
  late bool _savedEnabled;
  late String _savedPrefill;
  late AgentPrefillInjectionMode _mode;
  late AgentPrefillInjectionMode _savedMode;
  bool _saving = false;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    final chat = ref.read(agentSettingsProvider).settings.chat;
    _controller = TextEditingController(text: chat.assistantPrefill);
    _enabled = chat.assistantPrefillEnabled;
    _savedEnabled = chat.assistantPrefillEnabled;
    _savedPrefill = chat.assistantPrefill;
    _mode = chat.assistantPrefillInjectionMode;
    _savedMode = chat.assistantPrefillInjectionMode;
    _controller.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleDraftChanged)
      ..dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chat = ref.watch(agentSettingsProvider).settings.chat;
    if (chat.assistantPrefill != _savedPrefill ||
        chat.assistantPrefillEnabled != _savedEnabled ||
        chat.assistantPrefillInjectionMode != _savedMode) {
      _scheduleSynchronization();
    }
    final dirty =
        _enabled != _savedEnabled ||
        _controller.text != _savedPrefill ||
        _mode != _savedMode;
    final canSave =
        dirty && !_saving && (!_enabled || _controller.text.isNotEmpty);
    return SettingsCard(
      title: l10n.agentSettings_assistantPrefill,
      description: l10n.agentSettings_assistantPrefillDescription,
      icon: Icons.short_text_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('agent-assistant-prefill-enabled'),
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            title: Text(l10n.agentSettings_assistantPrefillEnabled),
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 8),
          HorizontalActionStrip(
            child: SegmentedButton<AgentPrefillInjectionMode>(
              key: const ValueKey('agent-assistant-prefill-injection-mode'),
              segments: [
                ButtonSegment(
                  value: AgentPrefillInjectionMode.firstTurn,
                  icon: const Icon(Icons.looks_one_outlined),
                  label: Text(l10n.agentSettings_prefillModeFirstTurn),
                ),
                ButtonSegment(
                  value: AgentPrefillInjectionMode.everyTurn,
                  icon: const Icon(Icons.repeat_outlined),
                  label: Text(l10n.agentSettings_prefillModeEveryTurn),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (selection) =>
                        setState(() => _mode = selection.single),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _mode == AgentPrefillInjectionMode.firstTurn
                ? l10n.agentSettings_prefillModeFirstTurnDescription
                : l10n.agentSettings_prefillModeEveryTurnDescription,
            key: const ValueKey('agent-assistant-prefill-mode-description'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('agent-assistant-prefill-input'),
            controller: _controller,
            minLines: 3,
            maxLines: 8,
            maxLength: AgentSettings.maxAssistantPrefillLength,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: l10n.agentSettings_assistantPrefillInput,
              helperText: l10n.agentSettings_assistantPrefillHint,
              helperMaxLines: 2,
              alignLabelWithHint: true,
            ),
          ),
          Text(
            l10n.agentSettings_assistantPrefillScope,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('agent-assistant-prefill-save'),
                onPressed: canSave ? _save : null,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(l10n.common_save),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _scheduleSynchronization() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final chat = ref.read(agentSettingsProvider).settings.chat;
      if (chat.assistantPrefill == _savedPrefill &&
          chat.assistantPrefillEnabled == _savedEnabled &&
          chat.assistantPrefillInjectionMode == _savedMode) {
        return;
      }
      final dirty =
          _enabled != _savedEnabled ||
          _controller.text != _savedPrefill ||
          _mode != _savedMode;
      _savedEnabled = chat.assistantPrefillEnabled;
      _savedPrefill = chat.assistantPrefill;
      _savedMode = chat.assistantPrefillInjectionMode;
      if (!dirty) {
        _enabled = chat.assistantPrefillEnabled;
        _mode = chat.assistantPrefillInjectionMode;
        _setControllerText(chat.assistantPrefill);
      }
      setState(() {});
    });
  }

  void _setControllerText(String text) {
    if (_controller.text == text) return;
    _controller.removeListener(_handleDraftChanged);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _controller.addListener(_handleDraftChanged);
  }

  Future<void> _save() async {
    final prefill = _controller.text;
    final enabled = _enabled;
    final mode = _mode;
    setState(() => _saving = true);
    try {
      await ref
          .read(agentSettingsProvider.notifier)
          .saveAssistantPrefill(
            enabled: enabled,
            prefill: prefill,
            injectionMode: mode,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _savedEnabled = enabled;
        _savedPrefill = prefill;
        _savedMode = mode;
      });
      AppToast.success(
        context,
        context.l10n.agentSettings_assistantPrefillSaved,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(
        context,
        context.l10n.agentSettings_operationFailed(error.toString()),
      );
    }
  }
}
