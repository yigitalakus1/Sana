import 'package:flutter/material.dart';

import '../../../core/branding/sana_mark.dart';
import '../../../core/theme/app_spacing.dart';
import 'assistant_screen.dart';
import 'explain_screen.dart';
import 'home_screen.dart';
import 'report_parse_screen.dart';
import 'settings_screen.dart';
import 'terms_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _index = 0;
  String? _explainQuestion;
  String? _explainLabTest;
  int _explainSeed = 0;
  String? _assistantQuestion;
  int _assistantPrefillRevision = 0;

  void _go(int index) => setState(() => _index = index);

  void _openExplain({String? question, String? labTest}) {
    setState(() {
      _index = 1;
      if (question != null) {
        _explainQuestion = question;
        _explainLabTest = labTest;
        _explainSeed++;
      }
    });
  }

  void _openAssistant({String? question}) {
    setState(() {
      _index = 4;
      if (question != null) {
        _assistantQuestion = question;
        _assistantPrefillRevision++;
      }
    });
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  List<Widget> _screens() => <Widget>[
    HomeScreen(
      onOpenExplain: () => _openExplain(),
      onOpenTerms: () => _go(2),
      onOpenReport: () => _go(3),
      onOpenAssistant: () => _openAssistant(),
      onOpenSettings: _openSettings,
    ),
    ExplainScreen(
      key: ValueKey(_explainSeed),
      initialQuestion: _explainQuestion,
      initialLabTest: _explainLabTest,
    ),
    TermsScreen(
      onAskAssistant: (question, _) => _openAssistant(question: question),
    ),
    ReportParseScreen(
      onExplainRequested: (question, labTest) =>
          _openExplain(question: question, labTest: labTest),
      onAskAssistant: (question) => _openAssistant(question: question),
    ),
    AssistantScreen(
      initialQuestion: _assistantQuestion,
      prefillRevision: _assistantPrefillRevision,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = IndexedStack(index: _index, children: _screens());
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: 232,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(right: BorderSide(color: scheme.outlineVariant)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: _RailBrand(),
                    ),
                    const Divider(),
                    Expanded(
                      child: NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: _go,
                        extended: true,
                        minExtendedWidth: 231,
                        groupAlignment: -1,
                        labelType: NavigationRailLabelType.none,
                        destinations: _railDestinations,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: _RailSafetyNote(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Ayarlar'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: _bottomDestinations,
        ),
      ),
    );
  }
}

const _railDestinations = <NavigationRailDestination>[
  NavigationRailDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home_rounded),
    label: Text('Ana Sayfa'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.auto_awesome_outlined),
    selectedIcon: Icon(Icons.auto_awesome),
    label: Text('Sonuç Açıkla'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.menu_book_outlined),
    selectedIcon: Icon(Icons.menu_book_rounded),
    label: Text('Tahlil Sözlüğü'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.description_outlined),
    selectedIcon: Icon(Icons.description_rounded),
    label: Text('Rapor Tara'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.forum_outlined),
    selectedIcon: Icon(Icons.forum_rounded),
    label: Text('Asistan'),
  ),
];

const _bottomDestinations = <NavigationDestination>[
  NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home_rounded),
    label: 'Ana Sayfa',
  ),
  NavigationDestination(
    icon: Icon(Icons.auto_awesome_outlined),
    selectedIcon: Icon(Icons.auto_awesome),
    label: 'Açıkla',
  ),
  NavigationDestination(
    icon: Icon(Icons.menu_book_outlined),
    selectedIcon: Icon(Icons.menu_book_rounded),
    label: 'Sözlük',
  ),
  NavigationDestination(
    icon: Icon(Icons.description_outlined),
    selectedIcon: Icon(Icons.description_rounded),
    label: 'Rapor',
  ),
  NavigationDestination(
    icon: Icon(Icons.forum_outlined),
    selectedIcon: Icon(Icons.forum_rounded),
    label: 'Asistan',
  ),
];

class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    // Marka: nabız halkası işareti + küçük harf kelime markası.
    return const Row(
      children: [
        SanaMarkBadge(size: 36),
        SizedBox(width: AppSpacing.md),
        Text(
          'sana',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _RailSafetyNote extends StatelessWidget {
  const _RailSafetyNote();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_outlined, size: 17, color: muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Bilgilendirme amaçlıdır. Tanı koymaz.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
          ),
        ),
      ],
    );
  }
}
