class FocusRecord {
  final String date;
  final int focusCount;
  final int napCount;
  final int focusMinutes;
  final int restMinutes;

  FocusRecord({
    required this.date,
    required this.focusCount,
    required this.napCount,
    required this.focusMinutes,
    required this.restMinutes,
  });

  factory FocusRecord.fromJson(Map<String, dynamic> json) {
    return FocusRecord(
      date: json['date'] as String,
      focusCount: json['focus_count'] as int,
      napCount: json['nap_count'] as int,
      focusMinutes: json['focus_minutes'] as int,
      restMinutes: json['rest_minutes'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'focus_count': focusCount,
      'nap_count': napCount,
      'focus_minutes': focusMinutes,
      'rest_minutes': restMinutes,
    };
  }
}

class TodayData {
  final int focusMinutes;
  final int restMinutes;
  final int focusCount;
  final int napCount;

  TodayData({
    required this.focusMinutes,
    required this.restMinutes,
    required this.focusCount,
    required this.napCount,
  });

  factory TodayData.fromRawData(List<int> data) {
    if (data.length < 6) {
      return TodayData(
          focusMinutes: 0, restMinutes: 0, focusCount: 0, napCount: 0);
    }
    // Little-endian uint16_t
    final focusMinutes = data[0] | (data[1] << 8);
    final restMinutes = data[2] | (data[3] << 8);
    final focusCount = data[4];
    final napCount = data[5];
    return TodayData(
      focusMinutes: focusMinutes,
      restMinutes: restMinutes,
      focusCount: focusCount,
      napCount: napCount,
    );
  }
}
