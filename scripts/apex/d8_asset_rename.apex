// D8 기존 장비 이름·시리얼 키를 새 규칙으로 일괄 변경 (이름을 "-"로 저장하면 저장 전 Flow가 규칙대로 다시 만듦)
// 1) APPLY = false로 먼저 실행 → 바뀔 장비 수와 예시(최대 15건)만 확인 (저장하지 않음)
// 2) 확인 후 APPLY = true → 바뀔 장비만 저장. 실패는 건별로 표시 (검증 규칙 등)
// 규칙(Flow Asset_BeforeSave_NameAndSerialKey와 같음): 모델/고객사/사업장/시리얼 끝자리(마지막 하이픈 뒤), 빈 칸은 건너뜀
Boolean APPLY = false;

List<Asset> targets = new List<Asset>();
Integer keyFix = 0;
for (Asset a : [
    SELECT Id, Name, SerialNumber, SerialKey__c, Product2.Name, Account.Name, CustomerSite__r.Name
    FROM Asset
    ORDER BY Name
]) {
    String serial = String.isBlank(a.SerialNumber) ? a.SerialKey__c : a.SerialNumber;
    List<String> parts = new List<String>();
    for (String part : new List<String>{ a.Product2?.Name, a.Account?.Name, a.CustomerSite__r?.Name }) {
        if (String.isNotBlank(part)) {
            parts.add(part);
        }
    }
    if (String.isNotBlank(serial)) {
        parts.add(serial.contains('-') ? serial.substringAfterLast('-') : serial);
    }
    String expected = parts.isEmpty() ? '미지정 장비' : String.join(parts, '/').left(255);
    Boolean keyDiff = serial != a.SerialKey__c || serial != a.SerialNumber;
    if (expected != a.Name || keyDiff) {
        if (targets.size() < 15) {
            System.debug(LoggingLevel.WARN, 'RENAME ' + a.Name + ' → ' + expected + (keyDiff ? '  (시리얼 키·일련번호 맞춤)' : ''));
        }
        if (keyDiff) {
            keyFix++;
        }
        // DESC: 이름을 바꿔 저장해야 저장 전 Flow가 돎 (진입 조건: 이름 등 변경)
        targets.add(new Asset(Id = a.Id, Name = '-'));
    }
}
System.debug(LoggingLevel.WARN, 'RENAME 바뀔 장비 ' + targets.size() + '건 (그중 시리얼 키·일련번호 맞춤 ' + keyFix + '건) / 전체 '
    + [SELECT COUNT() FROM Asset] + '건');

if (APPLY && !targets.isEmpty()) {
    List<Database.SaveResult> results = Database.update(targets, false);
    Integer ok = 0;
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            ok++;
        } else {
            System.debug(LoggingLevel.WARN, 'RENAME 실패 ' + targets[i].Id + ' ' + results[i].getErrors()[0].getMessage());
        }
    }
    System.debug(LoggingLevel.WARN, 'RENAME 저장 ' + ok + ' / ' + targets.size());
} else if (!APPLY) {
    System.debug(LoggingLevel.WARN, 'RENAME 미리 보기만 (APPLY = false)');
}
