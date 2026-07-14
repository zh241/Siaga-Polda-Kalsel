class GpsThrottle {
  DateTime? _lastWriteTime;

  /// Returns true if the database write should be performed.
  /// If it is performed, it updates the last write timestamp.
  bool shouldWrite(DateTime now, int intervalSeconds) {
    if (_lastWriteTime != null) {
      final difference = now.difference(_lastWriteTime!);
      if (difference.inSeconds < intervalSeconds) {
        return false;
      }
    }
    _lastWriteTime = now;
    return true;
  }

  /// Reset the throttle state (useful for starting new tracking sessions).
  void reset() {
    _lastWriteTime = null;
  }

  /// Exposed getter for testing/debugging.
  DateTime? get lastWriteTime => _lastWriteTime;
}
