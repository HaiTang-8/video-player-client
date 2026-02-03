import 'package:shadcn_flutter/shadcn_flutter.dart';

class ShadcnZhLocalizations extends DefaultShadcnLocalizations {
  const ShadcnZhLocalizations();

  static const ShadcnZhLocalizations instance = ShadcnZhLocalizations();

  @override
  String get placeholderDatePicker => '选择日期';

  @override
  String get timeAM => '上午';

  @override
  String get timePM => '下午';

  @override
  String get timeHour => '时';

  @override
  String get timeMinute => '分';

  @override
  String get timeSecond => '秒';

  @override
  String get timeDaysAbbreviation => '天';

  @override
  String get timeHoursAbbreviation => '时';

  @override
  String get timeMinutesAbbreviation => '分';

  @override
  String get timeSecondsAbbreviation => '秒';

  @override
  String getMonth(int month) {
    const months = [
      '一月', '二月', '三月', '四月', '五月', '六月',
      '七月', '八月', '九月', '十月', '十一月', '十二月'
    ];
    return months[month - 1];
  }

  @override
  String getAbbreviatedMonth(int month) {
    const months = [
      '1月', '2月', '3月', '4月', '5月', '6月',
      '7月', '8月', '9月', '10月', '11月', '12月'
    ];
    return months[month - 1];
  }

  @override
  String getAbbreviatedWeekday(int weekday) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return weekdays[weekday - 1];
  }
}

class ShadcnZhLocalizationsDelegate extends LocalizationsDelegate<ShadcnLocalizations> {
  const ShadcnZhLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';

  @override
  Future<ShadcnLocalizations> load(Locale locale) async {
    return ShadcnZhLocalizations.instance;
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<ShadcnLocalizations> old) => false;
}
