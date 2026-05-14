import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
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
  DateTime _selectedDay = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _chartMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _chartYear = DateTime.now().year;

  final ScrollController _dayLineScroll = ScrollController();
  final ScrollController _dayBarScroll = ScrollController();
  final ScrollController _yearLineScroll = ScrollController();
  final ScrollController _yearBarScroll = ScrollController();

  String? _lastAutoCenterTokenDayLine;
  String? _lastAutoCenterTokenDayBar;

  @override
  void dispose() {
    _dayLineScroll.dispose();
    _dayBarScroll.dispose();
    _yearLineScroll.dispose();
    _yearBarScroll.dispose();
    super.dispose();
  }

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
              ? _buildMonthDailySeries(records, _chartMonth)
              : _buildYearMonthlySeries(records, _chartYear);

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
                    setState(() {
                      _range = s.first;
                      if (_range == StatsRange.day) {
                        _chartMonth =
                            DateTime(_selectedDay.year, _selectedDay.month);
                      } else {
                        _chartYear = _selectedMonth.year;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (_range == StatsRange.day)
                _buildDaySummaryCard(context, records),
              if (_range == StatsRange.month)
                _buildMonthSummaryCard(context, records),
              const SizedBox(height: 16),
              if (_range == StatsRange.day) _buildChartMonthSwitcher(context),
              if (_range == StatsRange.month) _buildChartYearSwitcher(context),
              const SizedBox(height: 8),
              _buildLineChartCard(context, series),
              const SizedBox(height: 16),
              _buildBarChartCard(context, series),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDaySummaryCard(BuildContext context, List<FocusRecord> records) {
    final key = _dayKey(_selectedDay);
    final record = records.cast<FocusRecord?>().firstWhere(
          (r) => r?.date == key,
          orElse: () => null,
        );

    final focusMinutes = record?.focusMinutes;
    final restMinutes = record?.restMinutes;
    final focusCount = record?.focusCount;
    final restCount = record?.napCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedDay =
                          _selectedDay.subtract(const Duration(days: 1));
                      _chartMonth =
                          DateTime(_selectedDay.year, _selectedDay.month);
                    });
                  },
                ),
                Expanded(
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDay,
                          firstDate: DateTime(2000, 1, 1),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (!mounted || picked == null) return;
                        setState(() {
                          _selectedDay = picked;
                          _chartMonth = DateTime(picked.year, picked.month);
                        });
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        key,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _selectedDay = _selectedDay.add(const Duration(days: 1));
                      _chartMonth =
                          DateTime(_selectedDay.year, _selectedDay.month);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statItem(
                  icon: Icons.hourglass_empty,
                  label: '专注时长',
                  value: focusMinutes == null ? '--' : '$focusMinutes分钟',
                  color: Colors.deepOrange,
                ),
                _statItem(
                  icon: Icons.weekend,
                  label: '休息时长',
                  value: restMinutes == null ? '--' : '$restMinutes分钟',
                  color: Colors.lightBlue,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statItem(
                  icon: Icons.timer,
                  label: '专注次数',
                  value: focusCount?.toString() ?? '--',
                  color: Colors.orange,
                ),
                _statItem(
                  icon: Icons.coffee,
                  label: '休息次数',
                  value: restCount?.toString() ?? '--',
                  color: Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSummaryCard(
    BuildContext context,
    List<FocusRecord> records,
  ) {
    final monthKey = _monthKey(_selectedMonth);
    final agg = _Agg();
    var hasAny = false;
    for (final r in records) {
      if (r.date.startsWith(monthKey)) {
        hasAny = true;
        agg.focusMinutes += r.focusMinutes;
        agg.restMinutes += r.restMinutes;
        agg.focusCount += r.focusCount;
        agg.restCount += r.napCount;
      }
    }

    final label =
        '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                      );
                      _chartYear = _selectedMonth.year;
                    });
                  },
                ),
                Expanded(
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked =
                            await _pickMonth(context, _selectedMonth);
                        if (!mounted || picked == null) return;
                        setState(() {
                          _selectedMonth = picked;
                          _chartYear = picked.year;
                        });
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month + 1,
                      );
                      _chartYear = _selectedMonth.year;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statItem(
                  icon: Icons.hourglass_empty,
                  label: '专注时长',
                  value: hasAny ? '${agg.focusMinutes}分钟' : '--',
                  color: Colors.deepOrange,
                ),
                _statItem(
                  icon: Icons.weekend,
                  label: '休息时长',
                  value: hasAny ? '${agg.restMinutes}分钟' : '--',
                  color: Colors.lightBlue,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statItem(
                  icon: Icons.timer,
                  label: '专注次数',
                  value: hasAny ? agg.focusCount.toString() : '--',
                  color: Colors.orange,
                ),
                _statItem(
                  icon: Icons.coffee,
                  label: '休息次数',
                  value: hasAny ? agg.restCount.toString() : '--',
                  color: Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem({
    required IconData icon,
    required String label,
    required String value,
    Color color = Colors.black87,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _dayKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _monthKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  Widget _buildChartMonthSwitcher(BuildContext context) {
    final label =
        '${_chartMonth.year}-${_chartMonth.month.toString().padLeft(2, '0')}';
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _chartMonth = DateTime(_chartMonth.year, _chartMonth.month - 1);
              _selectedDay = _clampDayToMonth(_selectedDay, _chartMonth);
            });
          },
        ),
        Expanded(
          child: Center(
            child: TextButton.icon(
              onPressed: () async {
                final picked = await _pickMonth(context, _chartMonth);
                if (!mounted || picked == null) return;
                setState(() {
                  _chartMonth = picked;
                  _selectedDay = _clampDayToMonth(_selectedDay, _chartMonth);
                });
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(label),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() {
              _chartMonth = DateTime(_chartMonth.year, _chartMonth.month + 1);
              _selectedDay = _clampDayToMonth(_selectedDay, _chartMonth);
            });
          },
        ),
      ],
    );
  }

  Widget _buildChartYearSwitcher(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _chartYear -= 1),
        ),
        Expanded(
          child: Center(
            child: Text(
              '$_chartYear',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => _chartYear += 1),
        ),
      ],
    );
  }

  static Future<DateTime?> _pickMonth(
    BuildContext context,
    DateTime initialMonth,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initialMonth.year, initialMonth.month, 1),
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null) return null;
    return DateTime(picked.year, picked.month);
  }

  static DateTime _clampDayToMonth(DateTime day, DateTime month) {
    final daysInTarget = DateTime(month.year, month.month + 1, 1)
        .subtract(const Duration(days: 1))
        .day;
    final clampedDay = day.day <= daysInTarget ? day.day : daysInTarget;
    return DateTime(month.year, month.month, clampedDay);
  }

  Widget _buildLineChartCard(BuildContext context, _StatsSeries series) {
    final scheme = Theme.of(context).colorScheme;
    final visibleCount = _visibleCountForSeries(series);
    final scale = _yScaleForLine(series);
    final isYearly = series.labels.length == 12;
    final scrollController = isYearly ? _yearLineScroll : _dayLineScroll;
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
              child: Row(
                children: [
                  _buildPinnedYAxis(context, scale),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final pointWidth = constraints.maxWidth / visibleCount;
                        final chartWidth = math.max(
                          constraints.maxWidth,
                          pointWidth * series.labels.length,
                        );

                        _maybeAutoCenterDayCharts(
                          kind: _AutoCenterKind.line,
                          isYearly: isYearly,
                          controller: scrollController,
                          pointWidth: pointWidth,
                          viewportWidth: constraints.maxWidth,
                          chartWidth: chartWidth,
                        );

                        return SingleChildScrollView(
                          controller: scrollController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            height: 220,
                            child: LineChart(
                              LineChartData(
                                minY: 0,
                                maxY: scale.maxY,
                                minX: 0,
                                maxX: (series.labels.length - 1).toDouble(),
                                gridData: FlGridData(
                                  show: true,
                                  horizontalInterval: scale.interval,
                                ),
                                borderData: FlBorderData(show: false),
                                lineTouchData: LineTouchData(
                                  enabled: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (_) =>
                                        Colors.black.withOpacity(0.8),
                                    fitInsideHorizontally: true,
                                    fitInsideVertically: true,
                                  ),
                                ),
                                titlesData: _titles(series.labels,
                                    showLeftTitles: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: series.focusMinutes,
                                    isCurved: true,
                                    curveSmoothness: 0.45,
                                    preventCurveOverShooting: true,
                                    barWidth: 2,
                                    color: Colors.lightBlue,
                                    dotData: const FlDotData(show: false),
                                  ),
                                  LineChartBarData(
                                    spots: series.restMinutes,
                                    isCurved: true,
                                    curveSmoothness: 0.35,
                                    preventCurveOverShooting: true,
                                    barWidth: 2,
                                    color: Colors.orange,
                                    dotData: const FlDotData(show: false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartCard(BuildContext context, _StatsSeries series) {
    final scheme = Theme.of(context).colorScheme;
    final visibleCount = _visibleCountForSeries(series);
    final scale = _yScaleForBar(series);
    final isYearly = series.labels.length == 12;
    final scrollController = isYearly ? _yearBarScroll : _dayBarScroll;
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
              child: Row(
                children: [
                  _buildPinnedYAxis(context, scale),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final pointWidth = constraints.maxWidth / visibleCount;
                        final chartWidth = math.max(
                          constraints.maxWidth,
                          pointWidth * series.labels.length,
                        );

                        _maybeAutoCenterDayCharts(
                          kind: _AutoCenterKind.bar,
                          isYearly: isYearly,
                          controller: scrollController,
                          pointWidth: pointWidth,
                          viewportWidth: constraints.maxWidth,
                          chartWidth: chartWidth,
                        );

                        return SingleChildScrollView(
                          controller: scrollController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            height: 220,
                            child: BarChart(
                              BarChartData(
                                minY: 0,
                                maxY: scale.maxY,
                                gridData: FlGridData(
                                  show: true,
                                  horizontalInterval: scale.interval,
                                ),
                                borderData: FlBorderData(show: false),
                                barTouchData: BarTouchData(
                                  enabled: true,
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipColor: (_) =>
                                        Colors.black.withOpacity(0.8),
                                    fitInsideHorizontally: true,
                                    fitInsideVertically: true,
                                  ),
                                ),
                                titlesData: _titles(series.labels,
                                    showLeftTitles: false),
                                barGroups:
                                    List.generate(series.labels.length, (i) {
                                  final focus = series.focusCounts[i];
                                  final rest = series.restCounts[i];
                                  return BarChartGroupData(
                                    x: i,
                                    barsSpace: 4,
                                    barRods: [
                                      BarChartRodData(
                                        toY: focus,
                                        width: 8,
                                        color: Colors.lightBlue,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      BarChartRodData(
                                        toY: rest,
                                        width: 8,
                                        color: Colors.orange.shade300,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  FlTitlesData _titles(List<String> labels, {required bool showLeftTitles}) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: showLeftTitles,
          reservedSize: showLeftTitles ? 32 : 0,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
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

  Widget _buildPinnedYAxis(BuildContext context, _YScale scale) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10);
    final values = <double>[
      scale.maxY,
      scale.maxY - scale.interval,
      scale.maxY - scale.interval * 2,
      scale.maxY - scale.interval * 3,
      0,
    ];

    return SizedBox(
      width: 40,
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values
            .map(
              (v) => Text(
                v.toStringAsFixed(0),
                style: style,
              ),
            )
            .toList(),
      ),
    );
  }

  static double _maxSpotY(List<FlSpot> spots) {
    var maxY = 0.0;
    for (final s in spots) {
      if (s.y > maxY) maxY = s.y;
    }
    return maxY;
  }

  static double _maxDouble(List<double> values) {
    var maxV = 0.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    return maxV;
  }

  static _YScale _yScaleFromRawMax(double rawMax) {
    final interval = math.max(1.0, (rawMax / 4).ceilToDouble());
    return _YScale(maxY: interval * 4, interval: interval);
  }

  static _YScale _yScaleForLine(_StatsSeries series) {
    final rawMax = math.max(
      _maxSpotY(series.focusMinutes),
      _maxSpotY(series.restMinutes),
    );
    return _yScaleFromRawMax(rawMax);
  }

  static _YScale _yScaleForBar(_StatsSeries series) {
    final rawMax = math.max(
      _maxDouble(series.focusCounts),
      _maxDouble(series.restCounts),
    );
    return _yScaleFromRawMax(rawMax);
  }

  void _maybeAutoCenterDayCharts({
    required _AutoCenterKind kind,
    required bool isYearly,
    required ScrollController controller,
    required double pointWidth,
    required double viewportWidth,
    required double chartWidth,
  }) {
    if (isYearly) return;
    if (_range != StatsRange.day) return;
    if (_selectedDay.year != _chartMonth.year ||
        _selectedDay.month != _chartMonth.month) {
      return;
    }

    final token =
        '${_chartMonth.year}-${_chartMonth.month}-${_selectedDay.day}-v7';

    if (kind == _AutoCenterKind.line && token == _lastAutoCenterTokenDayLine) {
      return;
    }
    if (kind == _AutoCenterKind.bar && token == _lastAutoCenterTokenDayBar) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!controller.hasClients) return;

      final index = (_selectedDay.day - 1).clamp(0, 1000000);
      const visibleCount = 7;
      const centerIndex = (visibleCount ~/ 2);
      final desired = (index - centerIndex) * pointWidth;
      final maxScroll = math.max(0.0, chartWidth - viewportWidth);
      final clamped = desired.clamp(0.0, maxScroll);
      controller.jumpTo(clamped);
    });

    if (kind == _AutoCenterKind.line) {
      _lastAutoCenterTokenDayLine = token;
    } else {
      _lastAutoCenterTokenDayBar = token;
    }
  }

  static int _visibleCountForSeries(_StatsSeries series) {
    // Month-daily charts: show 7 days per screen.
    // Year-monthly charts: show 6 months per screen.
    return series.labels.length == 12 ? 6 : 7;
  }

  _StatsSeries _buildMonthDailySeries(
      List<FocusRecord> records, DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;

    final byDate = <String, FocusRecord>{
      for (final r in records) r.date: r,
    };

    final labels = <String>[];
    final focusMinutes = <FlSpot>[];
    final restMinutes = <FlSpot>[];
    final focusCounts = <double>[];
    final restCounts = <double>[];

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(monthStart.year, monthStart.month, day);
      final key = _dayKey(date);
      final r = byDate[key];

      final i = day - 1;
      labels.add(day.toString());
      focusMinutes.add(FlSpot(i.toDouble(), (r?.focusMinutes ?? 0).toDouble()));
      restMinutes.add(FlSpot(i.toDouble(), (r?.restMinutes ?? 0).toDouble()));
      focusCounts.add((r?.focusCount ?? 0).toDouble());
      restCounts.add((r?.napCount ?? 0).toDouble());
    }

    return _StatsSeries(
      labels: labels,
      focusMinutes: focusMinutes,
      restMinutes: restMinutes,
      focusCounts: focusCounts,
      restCounts: restCounts,
    );
  }

  _StatsSeries _buildYearMonthlySeries(List<FocusRecord> records, int year) {
    final byMonth = <int, _Agg>{
      for (var m = 1; m <= 12; m++) m: _Agg(),
    };

    for (final r in records) {
      final d = DateTime.tryParse(r.date);
      if (d == null) continue;
      if (d.year != year) continue;
      final agg = byMonth[d.month]!;
      agg.focusMinutes += r.focusMinutes;
      agg.restMinutes += r.restMinutes;
      agg.focusCount += r.focusCount;
      agg.restCount += r.napCount;
    }

    final labels = <String>[];
    final focusMinutes = <FlSpot>[];
    final restMinutes = <FlSpot>[];
    final focusCounts = <double>[];
    final restCounts = <double>[];

    for (var m = 1; m <= 12; m++) {
      final i = m - 1;
      labels.add('$m月');
      final agg = byMonth[m]!;
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

class _YScale {
  final double maxY;
  final double interval;

  const _YScale({required this.maxY, required this.interval});
}

enum _AutoCenterKind { line, bar }
