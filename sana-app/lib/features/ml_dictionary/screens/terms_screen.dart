import 'package:flutter/material.dart';

import '../../../core/network/sana_api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/term_models.dart';
import '../services/dictionary_preferences_service.dart';
import '../services/ml_dictionary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/sana_card.dart';
import 'term_detail_screen.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({
    super.key,
    this.onAskAssistant,
    this.service,
    this.preferences,
  });

  final void Function(String question, String labTest)? onAskAssistant;
  final MlDictionaryService? service;
  final DictionaryPreferencesService? preferences;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  late final MlDictionaryService _service =
      widget.service ?? MlDictionaryService();
  final TextEditingController _searchCtrl = TextEditingController();
  late final DictionaryPreferencesService _preferences =
      widget.preferences ?? DictionaryPreferencesService();

  bool _loading = true;
  String? _error;
  List<TermSummary> _terms = const [];
  Set<String> _favorites = <String>{};
  List<String> _recent = const [];
  bool _favoritesOnly = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });
    _load();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final favorites = await _preferences.loadFavorites();
      final recent = await _preferences.loadRecent();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _recent = recent;
      });
    } catch (_) {
      // Tarayıcı depolaması kapalı olsa da sözlük kullanılabilir kalır.
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final terms = await _service.getTerms();
      if (!mounted) return;
      setState(() {
        _terms = sortTermSummariesAlphabetically(terms);
        _loading = false;
      });
    } on SanaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Testler yüklenemedi.';
        _loading = false;
      });
    }
  }

  // Yalnız backend'den gelen liste üzerinde client-side filtreleme.
  List<TermSummary> get _filtered {
    final source = _favoritesOnly
        ? _terms.where((term) => _favorites.contains(term.labTest))
        : _terms;
    if (_query.isEmpty) return source.toList();
    final q = _query.toLowerCase();
    return source
        .where((t) => '${t.labTest} ${t.title ?? ''}'.toLowerCase().contains(q))
        .toList();
  }

  void _openTerm(TermSummary term) {
    _rememberRecent(term.labTest);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => TermDetailScreen(
          labTest: term.labTest,
          onAskAssistant: widget.onAskAssistant == null
              ? null
              : (question, labTest) {
                  Navigator.of(routeContext).pop();
                  widget.onAskAssistant!(question, labTest);
                },
        ),
      ),
    );
  }

  Future<void> _rememberRecent(String labTest) async {
    try {
      final recent = await _preferences.addRecent(labTest);
      if (mounted) setState(() => _recent = recent);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = <String>[
          labTest,
          ..._recent.where((value) => value != labTest),
        ].take(6).toList();
      });
    }
  }

  void _toggleFavorite(TermSummary term) {
    final favorite = !_favorites.contains(term.labTest);
    setState(() {
      favorite ? _favorites.add(term.labTest) : _favorites.remove(term.labTest);
    });
    _persistFavorite(term.labTest, favorite);
  }

  Future<void> _persistFavorite(String labTest, bool favorite) async {
    try {
      await _preferences.setFavorite(labTest, favorite);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Favori bu oturum için eklendi; tarayıcı depolamasına yazılamadı.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tahlil Sözlüğü')),
      body: ResponsiveCenter(
        child: Padding(
          padding: AppSpacing.pagePadding(MediaQuery.sizeOf(context).width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Açıklanabilen tahlilleri arayabilir, bölümlerini ve '
                'kaynaklarını inceleyebilirsin.',
                style: AppTextStyles.muted(context),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'CRP, ferritin, B12 ara',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchCtrl.clear(),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('Tümü'),
                    selected: !_favoritesOnly,
                    onSelected: (_) => setState(() => _favoritesOnly = false),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.star_outline, size: 17),
                    label: Text('Favoriler (${_favorites.length})'),
                    selected: _favoritesOnly,
                    onSelected: (_) => setState(() => _favoritesOnly = true),
                  ),
                  for (final recent in _recent.take(3))
                    ActionChip(
                      avatar: const Icon(Icons.history, size: 17),
                      label: Text(recent),
                      onPressed: () => _searchCtrl.text = recent,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.md),
            Text('Tahliller yükleniyor...'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorBox(message: _error!),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _query.isEmpty
                    ? 'Tahlil bulunamadı.'
                    : 'Aramanızla eşleşen tahlil bulunamadı.',
                style: AppTextStyles.muted(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final term = list[i];
        final letter = term.labTest.isEmpty
            ? '#'
            : term.labTest[0].toUpperCase();
        final previousLetter = i == 0 || list[i - 1].labTest.isEmpty
            ? null
            : list[i - 1].labTest[0].toUpperCase();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i == 0 || letter != previousLetter) ...[
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.sm,
                ),
                child: Text(letter, style: AppTextStyles.sectionTitle(context)),
              ),
            ],
            _TermCard(
              term: term,
              favorite: _favorites.contains(term.labTest),
              onFavorite: () => _toggleFavorite(term),
              onTap: () => _openTerm(term),
            ),
          ],
        );
      },
    );
  }
}

class _TermCard extends StatelessWidget {
  const _TermCard({
    required this.term,
    required this.favorite,
    required this.onFavorite,
    required this.onTap,
  });

  final TermSummary term;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SanaCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              term.labTest.isNotEmpty ? term.labTest.substring(0, 1) : '?',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(term.labTest, style: AppTextStyles.sectionTitle(context)),
                Text(
                  term.title ?? '${term.sections.length} bilgi bölümü',
                  style: AppTextStyles.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: favorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
            onPressed: onFavorite,
            color: favorite ? Colors.amber.shade800 : scheme.onSurfaceVariant,
            icon: Icon(favorite ? Icons.star_rounded : Icons.star_outline),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 15,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
