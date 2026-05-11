import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/focus_record.dart';
import '../providers/focus_timer_provider.dart';

enum StatsRange { day, month }

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsRange _range = StatsRange.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
      ),
      body: Consumer<FocusTimerProvider>(
        builder: (_, provider, __) {
          final records = provider.historyRecords;
          if (records.isEmpty) {
            return const Center(child: Text('暂无数据'));
          }

          final series = _range == StatsRange.day
              ? _buildDailySeries(records)
              : _buildMonthlySeries(records);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<StatsRange>(
                  segments: const [
                    ButtonSegment(value: StatsRange.day, label: Text('按天')),
                    ButtonSegment(value: StatsRange.month, label: Text('按月')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) {
                    setState(() => _range = s.first);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildLineChartCard(context, series),
              const SizedBox(height: 16),
              _buildBarChartCard(context, series),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLineChartCard(BuildContext context, _StatsSeries series) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '专注/休息时间（分钟）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: true),
                  titlesData: _titles(series.labels),
                  lineBarsData: [
                    LineChartBarData(
                      spots: series.focusMinutes,
                      isCurved: false,
                      barWidth: 2,
                      color: scheme.primary,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: series.restMinutes,
                      isCurved: false,
                      barWidth: 2,
                      color: scheme.secondary,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartCard(BuildContext context, _StatsSeries series) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '专注/休息次数',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: _titles(series.labels),
                  barGroups: List.generate(series.labels.length, (i) {
                    final focus = series.focusCounts[i];
                    final rest = series.restCounts[i];
                    return BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: focus,
                          width: 8,
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: rest,
                          width: 8,
                          color: scheme.secondary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  FlTitlesData _titles(List<String> labels) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: true, reservedSize: 32),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: labels.length > 10 ? 2 : 1,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                labels[i],
                style: const TextStyle(fontSize: 10),
              ),
            );
          },
        ),
      ),
    );
  }

  _StatsSeries _buildDailySeries(List<FocusRecord> records) {
    final parsed = records
        .map((r) => (r, DateTime.tryParse(r.date)))
        .where((e) => e.$2 != null)
        .toList()
      ..sort((a, b) => a.$2!.compareTo(b.$2!));

    // Keep the latest N points for readability.
    const maxPoints = 14;
    final tail = parsed.length > maxPoints
        ? parsed.sublist(parsed.length - maxPoints)
        : parsed;

    final labels = <String>[];
    final focusMinutes = <FlSpot>[];
    final restMinutes = <FlSpot>[];
    final focusCounts = <double>[];
    final restCounts = <double>[];

    for (var i = 0; i < tail.length; i++) {
      final r = tail[i].$1;
      final d = tail[i].$2!;
      labels.add(
          '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}');
      focusMinutes.add(FlSpot(i.toDouble(), r.focusMinutes.toDouble()));
      restMinutes.add(FlSpot(i.toDouble(), r.restMinutes.toDouble()));
      focusCounts.add(r.focusCount.toDouble());
      restCounts.add(r.napCount.toDouble());
    }

    return _StatsSeries(
      labels: labels,
      focusMinutes: focusMinutes,
      restMinutes: restMinutes,
      focusCounts: focusCounts,
      restCounts: restCounts,
    );
  }

  _StatsSeries _buildMonthlySeries(List<FocusRecord> records) {
    final map = <String, _Agg>{};
    for (final r in records) {
      final d = DateTime.tryParse(r.date);
      if (d == null) continue;
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => _Agg());
      map[key]!.focusMinutes += r.focusMinutes;
      map[key]!.restMinutes += r.restMinutes;
      map[key]!.focusCount += r.focusCount;
      map[key]!.restCount += r.napCount;
    }

    final keys = map.keys.toList()..sort();

    const maxPoints = 12;
    final tailKeys =
        keys.length > maxPoints ? keys.sublist(keys.length - maxPoints) : keys;

    final labels = <String>[];
    final focusMinutes = <FlSpot>[];
    final restMinutes = <FlSpot>[];
    final focusCounts = <double>[];
    final restCounts = <double>[];

    for (var i = 0; i < tailKeys.length; i++) {
      final key = tailKeys[i];
      final parts = key.split('-');
      final monthLabel = parts.length == 2 ? '${parts[1]}月' : key;
      labels.add(monthLabel);
      final agg = map[key]!;
      focusMinutes.add(FlSpot(i.toDouble(), agg.focusMinutes.toDouble()));
      restMinutes.add(FlSpot(i.toDouble(), agg.restMinutes.toDouble()));
      focusCounts.add(agg.focusCount.toDouble());
      restCounts.add(agg.restCount.toDouble());
    }

    return _StatsSeries(
      labels: labels,
      focusMinutes: focusMinutes,
      restMinutes: restMinutes,
      focusCounts: focusCounts,
      restCounts: restCounts,
    );
  }
}

class _StatsSeries {
  final List<String> labels;
  final List<FlSpot> focusMinutes;
  final List<FlSpot> restMinutes;
  final List<double> focusCounts;
  final List<double> restCounts;

  const _StatsSeries({
    required this.labels,
    required this.focusMinutes,
    required this.restMinutes,
    required this.focusCounts,
    required this.restCounts,
  });
}

class _Agg {
  int focusMinutes = 0;
  int restMinutes = 0;
  int focusCount = 0;
  int restCount = 0;
}
