import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/sana_api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/chat_models.dart';
import '../services/ml_dictionary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/status_chip.dart';

enum _TurnRole { user, assistant }

class _ChatTurn {
  const _ChatTurn.user(this.text) : role = _TurnRole.user, response = null;

  _ChatTurn.assistant(this.response)
    : role = _TurnRole.assistant,
      text = response!.answer;

  final _TurnRole role;
  final String text;
  final ChatResponse? response;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    this.initialQuestion,
    this.prefillRevision = 0,
    this.service,
  });

  final String? initialQuestion;
  final int prefillRevision;
  final MlDictionaryService? service;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final MlDictionaryService _service;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<ChatMessage> _backendMessages = [];
  final List<_ChatTurn> _turns = [];

  bool _loading = false;
  bool _longWait = false;
  String? _error;
  Timer? _loadingHintTimer;

  static const List<String> _suggestions = [
    'CRP 13.5 çıktı ne anlama gelir?',
    'Ferritin nedir?',
    'B12 neden ölçülür?',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MlDictionaryService();
    _applyPrefill(widget.initialQuestion);
  }

  @override
  void didUpdateWidget(covariant AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefillRevision != oldWidget.prefillRevision) {
      _applyPrefill(widget.initialQuestion, requestFocus: true);
    }
  }

  void _applyPrefill(String? question, {bool requestFocus = false}) {
    final value = question?.trim() ?? '';
    if (value.isEmpty) return;
    _inputCtrl.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _loadingHintTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _pickSuggestion(String value) {
    _inputCtrl.text = value;
    _inputCtrl.selection = TextSelection.collapsed(offset: value.length);
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _longWait = false;
      _error = null;
      _turns.add(_ChatTurn.user(text));
      _backendMessages.add(ChatMessage(role: 'user', content: text));
      _inputCtrl.clear();
    });
    _loadingHintTimer?.cancel();
    _loadingHintTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _loading) setState(() => _longWait = true);
    });
    _scrollToEnd();

    try {
      final response = await _service.chat(
        messages: List<ChatMessage>.unmodifiable(_backendMessages),
      );
      if (!mounted) return;
      setState(() {
        _turns.add(_ChatTurn.assistant(response));
        _backendMessages.add(
          ChatMessage(role: 'assistant', content: response.answer),
        );
      });
      _scrollToEnd();
    } on SanaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _restoreFailedMessage(text);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Beklenmeyen bir hata oluştu.';
        _restoreFailedMessage(text);
      });
    } finally {
      _loadingHintTimer?.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _longWait = false;
        });
      }
    }
  }

  void _restoreFailedMessage(String text) {
    if (_backendMessages.isNotEmpty &&
        _backendMessages.last.role == 'user' &&
        _backendMessages.last.content == text) {
      _backendMessages.removeLast();
    }
    if (_turns.isNotEmpty &&
        _turns.last.role == _TurnRole.user &&
        _turns.last.text == text) {
      _turns.removeLast();
    }
    if (_inputCtrl.text.isEmpty) _applyPrefill(text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sana Asistan')),
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scrollCtrl,
                  padding: AppSpacing.pagePadding(
                    MediaQuery.sizeOf(context).width,
                  ),
                  children: [
                    const _AssistantHeader(),
                    const SizedBox(height: AppSpacing.lg),
                    if (_turns.isEmpty)
                      _SuggestionPanel(onPick: _pickSuggestion),
                    for (final turn in _turns) ...[
                      const SizedBox(height: AppSpacing.md),
                      _MessageBubble(turn: turn),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: AppSpacing.md),
                      _TypingBubble(longWait: _longWait),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      ErrorBox(message: _error!),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _loading ? null : _send,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tekrar dene'),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
              _Composer(
                controller: _inputCtrl,
                focusNode: _focusNode,
                loading: _loading,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  const _AssistantHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Icon(
                  Icons.forum_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Sana Asistan',
                  style: AppTextStyles.screenTitle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tahlil sonuçları hakkında sade ve kaynaklı sorular sorabilirsin.',
            style: AppTextStyles.muted(context),
          ),
          const SizedBox(height: AppSpacing.md),
          const StatusChip(
            label: 'Kaynaklı yanıt',
            icon: Icons.health_and_safety_outlined,
          ),
        ],
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final suggestion in _AssistantScreenState._suggestions)
          ActionChip(
            avatar: const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(suggestion),
            onPressed: () => onPick(suggestion),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.turn});

  final _ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    if (turn.role == _TurnRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              turn.text,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
        ),
      );
    }

    final response = turn.response!;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _AssistantAnswerCard(response: response),
      ),
    );
  }
}

class _AssistantAnswerCard extends StatelessWidget {
  const _AssistantAnswerCard({required this.response});

  final ChatResponse response;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (response.responseType != 'answer') ...[
            _ResponseTypeNotice(type: response.responseType),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            response.answer,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ConfidenceChip(confidenceLabel: response.confidenceLabel),
              if (response.labTest != null && response.labTest!.isNotEmpty)
                StatusChip(label: response.labTest!),
              if (response.llmProvider.isNotEmpty)
                StatusChip(label: 'Sağlayıcı: ${response.llmProvider}'),
            ],
          ),
          if (response.citations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Kaynaklar', style: AppTextStyles.sectionTitle(context)),
            const SizedBox(height: AppSpacing.xs),
            for (final citation in response.citations)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.link,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(citation.sourceTitle),
                          if (citation.sourceUrl != null &&
                              citation.sourceUrl!.isNotEmpty)
                            Text(
                              citation.sourceUrl!,
                              style: AppTextStyles.caption(context),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.lg),
          DisclaimerBox(text: response.disclaimer),
        ],
      ),
    );
  }
}

class _ResponseTypeNotice extends StatelessWidget {
  const _ResponseTypeNotice({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final label = type == 'safety_block'
        ? 'Güvenlik gereği bu soru yanıtlanmadı.'
        : 'Bu soru için desteklenen tahlil eşleşmesi bulunamadı.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.longWait});

  final bool longWait;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              longWait
                  ? 'Yanıt hazırlanıyor, biraz daha sürebilir...'
                  : 'Yanıt hazırlanıyor...',
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              enabled: !loading,
              decoration: const InputDecoration(
                hintText: 'Örn. CRP 13.5 çıktı ne anlama gelir?',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: loading ? null : onSend,
            style: FilledButton.styleFrom(
              minimumSize: const Size(52, 52),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
