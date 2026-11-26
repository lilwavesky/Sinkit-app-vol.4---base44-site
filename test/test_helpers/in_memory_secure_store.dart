import 'package:karen_next/core/storage/local_storage_service.dart';

class InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> data = {};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;
  bool silentNoOpWrites = false;
  Duration? artificialWriteDelay;

  final Set<String> failingReadKeys = {};
  final Set<String> failingWriteKeys = {};
  final Set<String> failingDeleteKeys = {};

  /// Optional per-key write failure trigger after N successful writes.
  /// Example: `failWriteAfterCount[key] = 1` lets the 1st write succeed and fails the 2nd+.
  final Map<String, int> failWriteAfterCount = {};
  final Map<String, int> silentNoOpAfterCount = {};
  final Map<String, int> writeThenThrowAfterCount = {};
  final Map<String, int> writeCounts = {};
  final Set<String> deleteThenThrowKeys = {};

  /// Keys where `write()` returns without throwing, but silently fails to store the value.
  final Set<String> silentNoOpWriteKeys = {};

  /// Keys where `delete()` silently does nothing (simulating a broken keystore
  /// that doesn't throw but fails to remove the entry).
  final Set<String> stickyKeys = {};

  @override
  Future<String?> read(String key) async {
    if (failReads || failingReadKeys.contains(key)) {
      throw Exception('Simulated Android Keystore read failure for $key');
    }
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (artificialWriteDelay != null) {
      await Future<void>.delayed(artificialWriteDelay!);
    }
    final countSoFar = writeCounts[key] ?? 0;
    writeCounts[key] = countSoFar + 1;

    final failAfter = failWriteAfterCount[key];
    if (failWrites ||
        failingWriteKeys.contains(key) ||
        (failAfter != null && countSoFar >= failAfter)) {
      throw Exception('Simulated Android Keystore write failure for $key');
    }
    final writeThenThrowAfter = writeThenThrowAfterCount[key];
    if (writeThenThrowAfter != null && countSoFar >= writeThenThrowAfter) {
      data[key] = value;
      writeThenThrowAfterCount.remove(key);
      throw Exception('Simulated post-write Android Keystore failure for $key');
    }
    final noOpAfter = silentNoOpAfterCount[key];
    if (silentNoOpWrites ||
        silentNoOpWriteKeys.contains(key) ||
        (noOpAfter != null && countSoFar >= noOpAfter)) {
      return;
    }
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes || failingDeleteKeys.contains(key)) {
      throw Exception('Simulated Android Keystore delete failure for $key');
    }
    if (stickyKeys.contains(key)) {
      return;
    }
    data.remove(key);
    if (deleteThenThrowKeys.remove(key)) {
      throw Exception('Simulated post-delete Android Keystore failure for $key');
    }
  }
}

class InMemoryPreferencesStore implements PreferencesKeyValueStore {
  final Map<String, String> data = {};
  bool returnFalseOnSet = false;
  bool throwOnSet = false;
  bool silentNoOpSet = false;
  bool returnFalseOnRemove = false;

  final Set<String> failingSetKeys = {};
  final Set<String> silentNoOpSetKeys = {};
  final Set<String> stickyRemoveKeys = {};

  /// Allows the first N setString calls for a key to succeed, then fails subsequent ones.
  final Map<String, int> returnFalseAfterCount = {};
  final Map<String, int> writeThenReturnFalseAfterCount = {};
  final Map<String, int> writeThenThrowAfterCount = {};
  final Map<String, int> setCounts = {};

  @override
  String? getString(String key) => data[key];

  @override
  bool containsKey(String key) => data.containsKey(key);

  @override
  Future<bool> setString(String key, String value) async {
    final countSoFar = setCounts[key] ?? 0;
    setCounts[key] = countSoFar + 1;

    if (throwOnSet) {
      throw Exception('Simulated SharedPreferences write exception for $key');
    }
    final failAfter = returnFalseAfterCount[key];
    if (returnFalseOnSet ||
        failingSetKeys.contains(key) ||
        (failAfter != null && countSoFar >= failAfter)) {
      return false;
    }
    final writeThenFalseAfter = writeThenReturnFalseAfterCount[key];
    if (writeThenFalseAfter != null && countSoFar >= writeThenFalseAfter) {
      data[key] = value;
      writeThenReturnFalseAfterCount.remove(key);
      return false;
    }
    final writeThenThrowAfter = writeThenThrowAfterCount[key];
    if (writeThenThrowAfter != null && countSoFar >= writeThenThrowAfter) {
      data[key] = value;
      writeThenThrowAfterCount.remove(key);
      throw Exception('Simulated post-write SharedPreferences exception for $key');
    }
    if (silentNoOpSet || silentNoOpSetKeys.contains(key)) {
      return true;
    }
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (returnFalseOnRemove) return false;
    if (stickyRemoveKeys.contains(key)) return true;
    data.remove(key);
    return true;
  }
}
