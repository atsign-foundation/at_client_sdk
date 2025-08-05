import 'dart:convert';

void main() {
  var result =
      '[{"atKey":"@naresh:phone@jagan","operation":"+","opTime":"2020-07-01 16:50:59.607410Z","commitId":3,"value":"5555"},{"atKey":"@colin:phone@jagan","operation":"+","opTime":"2020-07-01 16:51:30.127190Z","commitId":4,"value":"6666"}]';
  var resultJson = jsonDecode(result);
  resultJson.forEach((e) => print(e));
}
