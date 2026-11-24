import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Settings-style building blocks shared by the account screens
/// (02-profile-and-sessions.md), matching [SettingsScreen]'s rows.

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, thickness: 1, color: AuraColors.cardBorder));
      rows.add(children[i]);
    }
    return AuraCard(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: rows));
  }
}

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({super.key, required this.label, required this.value, required this.onChanged, this.note});
  final String label;
  final String? note;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(note!, style: AuraText.cardSub.copyWith(fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AuraToggle(value: value, onChanged: onChanged ?? (_) {}),
          ],
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, this.value, this.sub, this.onTap, this.trailing, this.danger = false});
  final String label;
  final String? value;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: danger ? AuraColors.dangerText : AuraColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, style: AuraText.cardSub.copyWith(fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (value != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(value!,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AuraColors.textSecondary, fontSize: 14)),
                ),
              ),
            trailing ??
                (onTap == null
                    ? const SizedBox.shrink()
                    : const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 22),
                      )),
          ],
        ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// A row of pill choices (visibility, DM, stake currency).
class SegmentChoice extends StatelessWidget {
  const SegmentChoice({super.key, required this.options, required this.selected, required this.onChanged});
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(keys[i]),
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: keys[i] == selected ? AuraGradients.brand : null,
                    color: keys[i] == selected ? null : AuraColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: keys[i] == selected ? null : Border.all(color: AuraColors.cardBorder),
                  ),
                  child: Text(
                    options[keys[i]]!,
                    style: TextStyle(
                      color: keys[i] == selected ? Colors.white : AuraColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Password field with a show/hide eye.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, this.hint = 'Current password', this.errorText, this.onChanged});
  final TextEditingController controller;
  final String hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) => AuraTextField(
        hint: widget.hint,
        icon: Icons.lock_outline,
        obscure: !_show,
        controller: widget.controller,
        errorText: widget.errorText,
        onChanged: widget.onChanged,
        trailing: IconButton(
          splashRadius: 20,
          icon: Icon(_show ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20, color: AuraColors.textSecondary),
          onPressed: () => setState(() => _show = !_show),
        ),
      );
}
