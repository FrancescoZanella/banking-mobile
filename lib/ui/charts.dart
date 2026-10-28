import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/money.dart';
import 'theme.dart';

/// Grafici di Analisi e Flussi, come quelli Chart.js del web (app.js).
/// I valori arrivano in centesimi.

/// 123456 → "1.235 €" per gli assi.
String euroTick(double cents) {
  final m = money((cents / 100).round() * 100);
  return m.replaceFirst(',00', '');
}

const _axisStyle = TextStyle(color: AppColors.muted, fontSize: 10);
const _grid = FlGridData(show: true, drawVerticalLine: false);

/// Intervallo «tondo» per l'asse Y, circa 4 righe.
double _step(double max) {
  if (max <= 0) return 100;
  final raw = max / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final f in [1, 2, 2.5, 5, 10]) {
    if (raw <= f * mag) return f * mag;
  }
  return 10 * mag;
}

AxisTitles _leftTitles(double step) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 58,
        interval: step,
        getTitlesWidget: (v, meta) => v == meta.max && v % step != 0
            ? const SizedBox.shrink()
            : Text(euroTick(v), style: _axisStyle, textAlign: TextAlign.right),
      ),
    );

AxisTitles _bottomTitles(List<String> labels, {double interval = 1}) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 22,
        interval: interval,
        getTitlesWidget: (v, meta) {
          final i = v.round();
          if (v != i || i < 0 || i >= labels.length) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i], style: _axisStyle));
        },
      ),
    );

const _none = AxisTitles(sideTitles: SideTitles(showTitles: false));

LineTouchData _lineTouch(List<String> labels, List<String> names) => LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppColors.surface3,
        getTooltipItems: (spots) => [
          for (final s in spots)
            LineTooltipItem(
              '${s.barIndex == 0 && s.x.round() < labels.length ? '${labels[s.x.round()]}\n' : ''}'
              '${names[s.barIndex]}: ${money(s.y.round())}',
              const TextStyle(color: AppColors.text, fontSize: 12),
            ),
        ],
      ),
    );

/// Legenda semplice: pallino colorato + nome.
class ChartLegend extends StatelessWidget {
  const ChartLegend(this.items, {super.key});
  final List<(String, Color, bool)> items; // nome, colore, tratteggiato

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, children: [
        for (final (name, color, dashed) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 12,
              height: dashed ? 2 : 10,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 5),
            Text(name, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
      ]);
}

/// Spesa cumulata del periodo, sovrapposta a quella del periodo precedente.
class CumulativeChart extends StatelessWidget {
  const CumulativeChart({
    super.key,
    required this.labels,
    required this.current,
    required this.previous,
    required this.currentLabel,
    required this.previousLabel,
  });
  final List<String> labels;
  final List<int> current;
  final List<int> previous;
  final String currentLabel;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final n = math.max(current.length, previous.length);
    final top = [...current, ...previous, 0].reduce(math.max).toDouble();
    final step = _step(top);
    List<FlSpot> spots(List<int> v) => [for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i].toDouble())];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ChartLegend([(currentLabel, AppColors.accent, false), (previousLabel, AppColors.muted, true)]),
      const SizedBox(height: 10),
      SizedBox(
        height: 210,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: math.max(n - 1, 1).toDouble(),
          minY: 0,
          maxY: top == 0 ? step : (top / step).ceil() * step,
          gridData: _grid,
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: _leftTitles(step),
            bottomTitles: _bottomTitles(labels, interval: n > 12 ? 5 : 1),
            topTitles: _none,
            rightTitles: _none,
          ),
          lineTouchData: _lineTouch(labels, [currentLabel, previousLabel]),
          lineBarsData: [
            LineChartBarData(
              spots: spots(current),
              color: AppColors.accent,
              barWidth: 2.5,
              isCurved: true,
              preventCurveOverShooting: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: .13)),
            ),
            LineChartBarData(
              spots: spots(previous),
              color: AppColors.muted,
              barWidth: 1.5,
              isCurved: true,
              preventCurveOverShooting: true,
              dashArray: const [5, 4],
              dotData: const FlDotData(show: false),
            ),
          ],
        )),
      ),
    ]);
  }
}

/// Spesa degli ultimi 12 mesi: barra evidenziata = periodo scelto, tocco = apri il mese.
class MonthBarsChart extends StatelessWidget {
  const MonthBarsChart({super.key, required this.labels, required this.values, required this.selected, this.onTap});
  final List<String> labels;
  final List<int> values;
  final List<bool> selected;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final top = [...values, 0].reduce(math.max).toDouble();
    final step = _step(top);
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        minY: 0,
        maxY: top == 0 ? step : (top / step).ceil() * step,
        alignment: BarChartAlignment.spaceAround,
        gridData: _grid,
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: _leftTitles(step),
          bottomTitles: _bottomTitles(labels),
          topTitles: _none,
          rightTitles: _none,
        ),
        barTouchData: _barTouch(labels, (_, value) => 'Speso: ${money(value)}', onTap),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                width: 14,
                color: selected[i] ? AppColors.accent : AppColors.muted.withValues(alpha: .35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      )),
    );
  }
}

BarTouchData _barTouch(List<String> labels, String Function(int rod, int value) text, ValueChanged<int>? onTap) =>
    BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => AppColors.surface3,
        getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
          '${labels[group.x]}\n${text(rodIndex, rod.toY.round())}',
          const TextStyle(color: AppColors.text, fontSize: 12),
        ),
      ),
      touchCallback: (event, response) {
        final spot = response?.spot;
        if (onTap != null && event is FlTapUpEvent && spot != null) onTap(spot.touchedBarGroupIndex);
      },
    );

/// Flussi: entrate e uscite per mese, linea del risparmio, tocco = apri il mese.
class FlowsChart extends StatelessWidget {
  const FlowsChart({
    super.key,
    required this.labels,
    required this.income,
    required this.expense,
    required this.net,
    required this.selected,
    this.onTap,
  });
  final List<String> labels;
  final List<int> income;
  final List<int> expense;
  final List<int> net;
  final List<bool> selected;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final all = [...income, ...expense, ...net, 0];
    final step = _step(math.max(all.reduce(math.max), -all.reduce(math.min)).toDouble());
    final maxY = (all.reduce(math.max) / step).ceil() * step;
    final minY = (all.reduce(math.min) / step).floor() * step;
    final titles = FlTitlesData(
      leftTitles: _leftTitles(step),
      bottomTitles: _bottomTitles(labels),
      topTitles: _none,
      rightTitles: _none,
    );
    final n = labels.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const ChartLegend([
        ('Entrate', AppColors.pos, false),
        ('Uscite', AppColors.muted, false),
        ('Risparmio', AppColors.accent, true),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 230,
        // Barre e linea sovrapposte con gli stessi assi: con spaceAround il
        // centro del mese i cade a i + 0,5 su 12, come la linea da -0,5 a 11,5.
        child: Stack(children: [
          BarChart(BarChartData(
            minY: minY,
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid,
            borderData: FlBorderData(show: false),
            titlesData: titles,
            barTouchData: _barTouch(
                labels,
                (rod, value) => rod == 0 ? 'Entrate: ${money(value)}' : 'Uscite: ${money(value)}',
                onTap),
            barGroups: [
              for (var i = 0; i < n; i++)
                BarChartGroupData(x: i, barsSpace: 2, barRods: [
                  BarChartRodData(
                    toY: income[i].toDouble(),
                    width: 7,
                    color: AppColors.pos.withValues(alpha: selected[i] ? 1 : .5),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                  BarChartRodData(
                    toY: expense[i].toDouble(),
                    width: 7,
                    color: AppColors.muted.withValues(alpha: selected[i] ? 1 : .35),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ]),
            ],
          )),
          IgnorePointer(
            child: LineChart(LineChartData(
              minX: -.5,
              maxX: n - .5,
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 58, getTitlesWidget: (_, _) => const SizedBox.shrink())),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (_, _) => const SizedBox.shrink())),
                topTitles: _none,
                rightTitles: _none,
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), net[i].toDouble())],
                  color: AppColors.accent,
                  barWidth: 2,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  dotData: FlDotData(
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3, color: AppColors.accent, strokeWidth: 0),
                  ),
                ),
              ],
            )),
          ),
        ]),
      ),
    ]);
  }
}

/// Patrimonio a fine mese (ricostruito dai movimenti).
class NetWorthChart extends StatelessWidget {
  const NetWorthChart({super.key, required this.labels, required this.values});
  final List<String> labels;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final low = values.reduce(math.min).toDouble(), high = values.reduce(math.max).toDouble();
    final step = _step(math.max(high - low, high.abs() / 10));
    return SizedBox(
      height: 200,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: math.max(values.length - 1, 1).toDouble(),
        minY: (low / step).floor() * step,
        maxY: (high / step).ceil() * step + (high == low ? step : 0),
        gridData: _grid,
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: _leftTitles(step),
          bottomTitles: _bottomTitles(labels, interval: 2),
          topTitles: _none,
          rightTitles: _none,
        ),
        lineTouchData: _lineTouch(labels, ['Patrimonio']),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].toDouble())],
            color: AppColors.accent,
            barWidth: 2.5,
            isCurved: true,
            preventCurveOverShooting: true,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 2, color: AppColors.accent, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: .13)),
          ),
        ],
      )),
    );
  }
}
