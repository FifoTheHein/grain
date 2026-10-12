import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/duration_input.dart';
import '../theme/harvest_palette.dart';
import '../theme/harvest_tokens.dart';

/// `− [1h 45m] +` with the decimal hours underneath and quick chips below.
///
/// Controlled: it shows [minutes] and reports every change through
/// [onChanged], holding no value of its own, so Log Time and (later) Edit
/// Time can each own the number. A tap on ± moves 1 minute; holding repeats
/// and speeds up to 5, then 15 ([holdStepMinutes]). Tapping the number
/// switches to typed entry, read by [parseDurationInput]. Covered by
/// `test/duration_stepper_test.dart`.
class DurationStepper extends StatefulWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  /// Shown under the control in the error colour, e.g. after a submit with
  /// nothing set. Null hides it.
  final String? errorText;

  final List<int> quickDurations;
  final int max;

  const DurationStepper({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.errorText,
    this.quickDurations = kQuickDurations,
    this.max = kMaxDurationMinutes,
  });

  @override
  State<DurationStepper> createState() => _DurationStepperState();
}

class _DurationStepperState extends State<DurationStepper> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Reads widget.minutes on every call, which the parent has rebuilt with
  // the previous step while a hold repeats.
  void _step(bool up, int step) {
    final next =
        stepDuration(widget.minutes, up: up, step: step, max: widget.max);
    if (next != widget.minutes) widget.onChanged(next);
  }

  void _startTyping() {
    _controller.text =
        widget.minutes == 0 ? '' : formatDurationLabel(widget.minutes);
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// Applies what was typed when it reads as a duration, and leaves the value
  /// alone when it does not — an empty field included.
  void _commit() {
    final parsed = parseDurationInput(_controller.text);
    setState(() => _typing = false);
    if (parsed != null && parsed != widget.minutes) widget.onChanged(parsed);
  }

  void _cancel() {
    setState(() => _typing = false);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final theme = Theme.of(context);
    final atZero = widget.minutes <= 0;
    final atMax = widget.minutes >= widget.max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _RoundStepButton(
              icon: Icons.remove,
              semanticLabel: 'Decrease duration',
              enabled: !atZero,
              onStep: (step) => _step(false, step),
            ),
            const SizedBox(width: 12),
            Expanded(child: _typing ? _buildField(palette) : _buildDisplay(palette)),
            const SizedBox(width: 12),
            _RoundStepButton(
              icon: Icons.add,
              semanticLabel: 'Increase duration',
              enabled: !atMax,
              onStep: (step) => _step(true, step),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const _AccelHint(),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < widget.quickDurations.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _QuickChip(
                  label: formatQuickDuration(widget.quickDurations[i]),
                  selected: widget.minutes == widget.quickDurations[i],
                  onTap: () {
                    if (_typing) _cancel();
                    widget.onChanged(widget.quickDurations[i]);
                  },
                ),
              ),
            ],
          ],
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              widget.errorText!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildDisplay(HarvestPalette palette) {
    final parts = splitDuration(widget.minutes);
    final zero = widget.minutes == 0;
    final big = zero ? palette.text4 : palette.text;
    final unit = zero ? palette.text4 : palette.text2;
    final bigStyle = TextStyle(
        fontSize: 30, fontWeight: FontWeight.w700, color: big, height: 1.1);
    final unitStyle =
        TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: unit);

    return Semantics(
      button: true,
      label: 'Duration ${formatDurationLabel(widget.minutes)}, tap to type',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('duration-display'),
          onTap: _startTyping,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: palette.borderStrong),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${parts.hours}', style: bigStyle),
                    TextSpan(text: 'h ', style: unitStyle),
                    TextSpan(
                        text: parts.minutes.toString().padLeft(2, '0'),
                        style: bigStyle),
                    TextSpan(text: 'm', style: unitStyle),
                  ]),
                ),
                const SizedBox(height: 2),
                Text(
                  zero ? 'tap to type' : formatDecimalHours(widget.minutes),
                  style: TextStyle(fontSize: 11, color: palette.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(HarvestPalette palette) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final text = value.text.trim();
        final parsed = parseDurationInput(text);
        final String hint;
        if (text.isEmpty) {
          hint = '1:45 · 1.75 · 1h 45m · 105m';
        } else if (parsed == null) {
          hint = 'Try 1:45, 1.75 or 105m';
        } else {
          hint = '= ${formatDurationLabel(parsed)}';
        }
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          },
          child: TextField(
            key: const ValueKey('duration-field'),
            controller: _controller,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            onSubmitted: (_) => _commit(),
            decoration: InputDecoration(
              isDense: true,
              helperText: hint,
              helperStyle: TextStyle(
                fontSize: 11,
                color: parsed == null && text.isNotEmpty
                    ? Theme.of(context).colorScheme.error
                    : palette.text3,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.brand, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Steps once on press, then repeats while held, speeding up on the
/// [holdStepMinutes] schedule. [onStep] receives the step in minutes:
/// [kDurationStepMinutes] for the press, then whatever the schedule says for
/// each repeat.
///
/// Raw pointer events rather than tap/long-press recognisers: the first step
/// lands on press, and the repeat stops however the press ends — a
/// long-press recogniser would cancel the tap mid-hold. Shared by the
/// duration ± and Log Time's Start & End nudges.
class HoldToRepeat extends StatefulWidget {
  final bool enabled;
  final ValueChanged<int> onStep;
  final String semanticLabel;
  final Widget child;

  const HoldToRepeat({
    super.key,
    required this.enabled,
    required this.onStep,
    required this.semanticLabel,
    required this.child,
  });

  @override
  State<HoldToRepeat> createState() => _HoldToRepeatState();
}

class _HoldToRepeatState extends State<HoldToRepeat> {
  Timer? _repeat;
  int _ticks = 0;

  @override
  void didUpdateWidget(HoldToRepeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reached the end of the range mid-hold: stop rather than tick on nothing.
    if (!widget.enabled) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _stop();
    widget.onStep(kDurationStepMinutes);
    _repeat = Timer(kHoldRepeatDelay, () {
      _repeat = Timer.periodic(kHoldRepeatInterval, (_) {
        _ticks++;
        // widget, not a captured callback: the parent rebuilds this with
        // the latest value between ticks.
        widget.onStep(holdStepMinutes(holdElapsedAtTick(_ticks)));
      });
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
    _ticks = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      onTap: widget.enabled ? () => widget.onStep(kDurationStepMinutes) : null,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _start() : null,
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: widget.child,
      ),
    );
  }
}

/// A round ± button: 1 minute per tap, faster while held.
class _RoundStepButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final ValueChanged<int> onStep;

  const _RoundStepButton({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onStep,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final color = enabled ? palette.text : palette.text4;
    return HoldToRepeat(
      enabled: enabled,
      semanticLabel: semanticLabel,
      onStep: onStep,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: enabled ? palette.borderStrong : palette.border),
        ),
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }
}

/// "tap ±1 min · hold 1 → 5 → 15" under the stepper.
class _AccelHint extends StatelessWidget {
  const _AccelHint();

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final style = TextStyle(fontSize: 11, color: palette.text3);
    Widget step(String n) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(n, style: TextStyle(fontSize: 11, color: palette.text2)),
        );
    // An icon, not "→": the web build's bundled font has no arrow glyph.
    Widget arrow() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(Icons.arrow_forward, size: 11, color: palette.text3),
        );
    return Semantics(
      label: 'Tap plus or minus for 1 minute. Hold to step by 1, then 5, '
          'then 15 minutes.',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('tap ±1 min · hold ', style: style),
          step('1'),
          arrow(),
          step('5'),
          arrow(),
          step('15'),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.brand : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
              color: selected ? palette.brand : palette.borderStrong),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? palette.onBrand : palette.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
