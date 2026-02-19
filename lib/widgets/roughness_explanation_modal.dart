import 'package:flutter/material.dart';
import '../models/marine_data.dart';

/// Modal explaining the roughness index calculation
class RoughnessExplanationModal extends StatelessWidget {
  final HourlyForecast? forecast;

  const RoughnessExplanationModal({super.key, this.forecast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              'Sea State Index',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A measure of sea state from 0 (Glassy) to 100 (Intense)',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Score ranges
            const _SectionHeader(title: 'Sea State Scale'),
            const SizedBox(height: 12),
            const _ScoreRow(color: Color(0xFF22C55E), label: 'GLASSY',   range: '0-20',  desc: 'Perfect / Flat'),
            const _ScoreRow(color: Color(0xFF3B82F6), label: 'MODERATE', range: '21-40', desc: 'Standard West Coast'),
            const _ScoreRow(color: Color(0xFFF97316), label: 'CHOPPY',   range: '41-60', desc: 'Experienced swimmers'),
            const _ScoreRow(color: Color(0xFFEF4444), label: 'INTENSE',  range: '60+',   desc: 'High sea state'),

            const SizedBox(height: 24),

            // Formula breakdown
            const _SectionHeader(title: 'Calculation Components'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start at 0 (Glassy)', style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('Formula Components:', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  const _FormulaRow(label: 'Wind Speed × 0.5', weight: 'Misery Factor'),
                  const _FormulaRow(label: 'Wind Wave Height × 60', weight: 'Local Chop'),
                  const _FormulaRow(label: 'Swell Height × 20 × Power', weight: 'Danger Factor'),
                  Divider(color: theme.dividerColor, height: 24),
                  const Text('Power Multiplier:', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const _FormulaRow(label: 'Period > 13s (deceptive power)', weight: '× 1.8'),
                  const _FormulaRow(label: 'Period 10-13s (moderate)', weight: '× 1.4'),
                  const _FormulaRow(label: 'Period < 10s (standard)', weight: '× 1.0'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Cross-sea warning
            if (forecast?.swimCondition.diagnostics?.crossSeaLevel == 'cross-sea') ...[
              const _SectionHeader(title: 'Cross-Swell Advisory'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF97316)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('⚠️', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 8),
                        Text(
                          'Cross-Swell Detected',
                          style: TextStyle(
                            color: Color(0xFFFCD34D),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'When wave and wind directions differ significantly, cross-swell conditions can form, creating an irregular sea state.',
                      style: TextStyle(color: Color(0xFFFCD34D), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Data sources
            const _SectionHeader(title: 'Data Sources'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  const _SourceRow(icon: '🌊', label: 'Wave Data', source: 'Open-Meteo Marine API'),
                  _SourceRow(
                    icon: '🌤️', 
                    label: 'Weather', 
                    source: forecast?.dataSource ?? 'Open-Meteo'
                  ),
                  const _SourceRow(icon: '🌕', label: 'Tides', source: 'Marine Institute Ireland'),
                  if (forecast?.tideStation != null)
                    _SourceRow(
                      icon: '📍', 
                      label: 'Tide Station', 
                      source: forecast!.tideStation!
                    ),
                  if (forecast?.lat != null && forecast?.lon != null)
                    _SourceRow(
                      icon: '🗺️', 
                      label: 'Coordinates', 
                      source: '${forecast!.lat!.toStringAsFixed(4)}, ${forecast!.lon!.toStringAsFixed(4)}'
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ℹ️', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Always swim within your ability and stay within your depth. '
                      'Conditions can change quickly. This data is for information only — '
                      'use your own judgement before entering the water.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got it!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.8), // Using primary color for headers
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final Color color;
  final String label;
  final String range;
  final String desc;

  const _ScoreRow({
    required this.color,
    required this.label,
    required this.range,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            range,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            desc,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FormulaRow extends StatelessWidget {
  final String label;
  final String weight;

  const _FormulaRow({required this.label, required this.weight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Text(weight, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final String icon;
  final String label;
  final String source;

  const _SourceRow({required this.icon, required this.label, required this.source});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          const Spacer(),
          Text(source, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}
