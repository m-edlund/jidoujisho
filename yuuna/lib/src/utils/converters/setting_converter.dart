import 'dart:convert';

/// A type converter for a map of setting key and setting value, to an Isar
/// primitive.
class SettingsConverter {
  /// Deserializes the object.
  static Map<String, String> fromIsar(String object) => jsonDecode(object);

  /// Serializes the object.
  static String toIsar(Map<String, String> object) => jsonEncode(object);
}
