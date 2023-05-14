import 'package:flutter/material.dart';

import 'package:yuuna/utils.dart';

abstract class Setting<T> {
  /// Initialise this setting with the predetermined and hardset values.
  Setting({
    required this.uniqueKey,
    required this.label,
    required this.description,
    required this.defaultValue,
  });

  /// A unique name that allows distinguishing this type from others,
  /// particularly for the purposes of differentiating between persistent
  /// settings keys.
  final String uniqueKey;

  /// Name of the setting that very shortly describes what it does.
  final String label;

  /// A longer description of what the setting can do, or details left
  /// by or regarding the developer.
  final String description;

  /// The default value of the Setting
  T defaultValue;

  /// Gets the setting value for a string, returns the default setting if
  /// deserialization fails
  T deserialize(String? value);

  /// Gets string for a setting value
  String serialize(T value);

  /// Returns all possible values this setting can take on, if applicable.
  List<T>? possibleValues();

  Widget createSettingsWidget();

  T getFromMapping(Map<String, String> exportMapping) =>
      deserialize(exportMapping[uniqueKey]);
}

/// Mixin for enum settings
mixin EnumSetting<T extends Enum> on Setting<T> {
  /// Creates a settings widget for a Setting with an enum
  createEnumSettingsWidget() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10, color: Colors.pink,
              // TODO: how do I get the theme here?
              // color: Theme.of(context).unselectedWidgetColor,
            ),
          ),
          JidoujishoDropdown<T>(
            options: possibleValues()!,
            initialOption: defaultValue,
            generateLabel: serialize,
            onChanged: (settingValue) {
              //  TODO: implement saving settings
            },
          )
        ],
      );
}

/// Mixin for bool settings
mixin BoolSetting on Setting<bool> {
  /// Creates a settings widget for a Setting with a bool
  createBoolSettingsWidget() {
    ValueNotifier<bool> _notifier = ValueNotifier<bool>(defaultValue);
    return Row(
      children: [
        Expanded(child: Text(label)),
        ValueListenableBuilder<bool>(
          valueListenable: _notifier,
          builder: (_, value, __) {
            return Switch(
              value: value,
              onChanged: (value) {
                // TODO: actually update values in mapping
                _notifier.value = value;
              },
            );
          },
        )
      ],
    );
  }
}
