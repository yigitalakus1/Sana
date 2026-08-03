import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

class SafetyConsentScreen extends StatefulWidget {
  const SafetyConsentScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<SafetyConsentScreen> createState() => _SafetyConsentScreenState();
}

class _SafetyConsentScreenState extends State<SafetyConsentScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.health_and_safety_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          'Sana',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Devam etmeden önce',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sana, laboratuvar sonuçlarını anlamana yardımcı olan bir bilgilendirme aracıdır.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SafetyItem(
                      icon: Icons.medical_information_outlined,
                      text:
                          'Tanı koymaz ve doktor değerlendirmesinin yerini almaz.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _SafetyItem(
                      icon: Icons.medication_outlined,
                      text: 'İlaç, doz, takviye veya tedavi önermez.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _SafetyItem(
                      icon: Icons.emergency_outlined,
                      text:
                          'Acil bir durumda sağlık kuruluşuna veya acil yardıma başvurmalısın.',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    CheckboxListTile(
                      value: _accepted,
                      onChanged: (value) =>
                          setState(() => _accepted = value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Bilgilendirmeyi okudum ve anladım.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _accepted ? widget.onAccepted : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Uygulamaya devam et'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyItem extends StatelessWidget {
  const _SafetyItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: AppColors.primaryDeep),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}
