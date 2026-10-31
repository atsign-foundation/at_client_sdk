import 'dart:convert';

typedef LabResult = ({
  String experiment,
  String vfs,
  String browser,
  String browserVersion,
  Map<String, num> metrics,
  String notes,
});

extension LabResultExtension on LabResult {
  Map<String, dynamic> toJson() => {
        'experiment': experiment,
        'vfs': vfs,
        'browser': browser,
        'browserVersion': browserVersion,
        'metrics': metrics,
        'notes': notes,
      };

  String format() => 'LABRESULT ${jsonEncode(toJson())}';

  void emit() {
    print(format());
  }
}

void emitLabResult(LabResult result) {
  result.emit();
}
