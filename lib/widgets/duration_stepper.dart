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
/// Time can each own the number. ± move by [step] minutes and repeat while
/// held; tapping the number switches to typed entry, read by
/// [parseDurationInput]. Covered by `test/duration_stepper_test.dart`.
class DurationStepper extends StatefulWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  /// Shown under the control in the error colour, e.g. after a submit with
  /// nothing set. Null hides it.
  final String? errorText;

  final List<int> quickDurations;
  final int step;
  final int max;

  const DurationStepper({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.errorText,
    this.quickDurations = kQuickDurations,
    this.step = kDurationStepMinutes,
    this.max = kMaxDurationMinutes,
  });

  @override
  State<DurationStepper> createState() => _DurationStepperState();
}

class _DurationStepperState extends State<DurationStepper> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _typing = false;
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _commit();
    });
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _step(bool up) {
    final next = stepDuration(widget.minutes,
        up: up, step: widget.step, max: widget.max);
    if (next != widget.minutes) widget.onChanged(next);
  }

  // Hold to repeat: a short pause, then a steady tick. Reads widget.minutes
  // on every tick, which the parent has rebuilt with the previous step.
  void _startRepeat(bool up) {
    _repeat?.cancel();
    _step(up);
    _repeat = Timer(const Duration(milliseconds: 350), () {
      _repeat = Timer.periodic(
          const Duration(milliseconds: 90), (_) => _step(up));
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
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
              onStart: () => _startRepeat(false),
              onStepOnce: () => _step(false),
              onStop: _stopRepeat,
            ),
            const SizedBox(width: 12),
            Expanded(child: _typing ? _buildField(palette) : _buildDisplay(palette)),
            const SizedBox(width: 12),
            _RoundStepButton(
              icon: Icons.add,
              semanticLabel: 'Increase duration',
              enabled: !atMax,
              onStart: () => _startRepeat(true),
              onStepOnce: () => _step(true),
              onStop: _stopRepeat,
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                  zero
                      ? 'tap to type · hold ± to repeat'
                      : formatDecimalHours(widget.minutes),
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

/// A round ± button that steps once on tap and repeats while held.
class _RoundStepButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onStepOnce;

  const _RoundStepButton({
    required this.onStepOnce,
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final color = enabled ? palette.text : palette.text4;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? onStepOnce : null,
      excludeSemantics: true,
      // Raw pointer events rather than tap/long-press recognisers: the first
      // step lands on press, and the repeat stops however the press ends — a
      // long-press recogniser would cancel the tap mid-hold.
      child: Listener(
        onPointerDown: enabled ? (_) => onStart() : null,
        onPointerUp: (_) => onStop(),
        onPointerCancel: (_) => onStop(),
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
