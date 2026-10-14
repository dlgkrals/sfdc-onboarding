// D8 사업장 서비스센터 다시 적용 — 관리자가 ServiceCenterMapping__mdt(행정구역 → 센터)를 고친 뒤 기존 사업장에 반영
// 1) APPLY = false로 먼저 실행 → 대상 건수와 목록(최대 50건)만 확인 (저장하지 않음)
// 2) 확인 후 APPLY = true로 다시 실행 → 매핑과 다른 사업장만 저장 (트리거가 매핑 센터로 채움)
// 참고: 이미 만든 접수(Case)의 서비스센터·담당 Queue는 바뀌지 않음 (접수 시점 값). 새 접수부터 새 센터로
Boolean APPLY = false;

List<CustomerSite__c> changes = new List<CustomerSite__c>();
Integer noCode = 0;
Integer noMapping = 0;
for (CustomerSite__c s : [
    SELECT Id, Name, AdminDistrictCode__c, ServiceCenter__c
    FROM CustomerSite__c
    ORDER BY Name
]) {
    if (String.isBlank(s.AdminDistrictCode__c)) {
        noCode++;
        continue;
    }
    String mapped = ServiceCenterMappingService.resolveServiceCenter(s.AdminDistrictCode__c);
    if (mapped == null) {
        noMapping++;
        continue;
    }
    if (mapped != s.ServiceCenter__c) {
        if (changes.size() < 50) {
            System.debug(LoggingLevel.WARN, 'REAPPLY 대상 ' + s.Name + ' (' + s.AdminDistrictCode__c + ') ' + s.ServiceCenter__c + ' → ' + mapped);
        }
        changes.add(new CustomerSite__c(Id = s.Id, ServiceCenter__c = mapped));
    }
}
System.debug(LoggingLevel.WARN, 'REAPPLY 바뀔 사업장 ' + changes.size() + '건 / 행정구역 코드 없음 ' + noCode
    + '건 / 매핑 없음 ' + noMapping + '건 (이 둘은 바꾸지 않음, 주소 검색 또는 매핑 추가 필요)');

if (APPLY && !changes.isEmpty()) {
    List<Database.SaveResult> results = Database.update(changes, false);
    Integer ok = 0;
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            ok++;
        } else {
            System.debug(LoggingLevel.WARN, 'REAPPLY 실패 ' + changes[i].Id + ' ' + results[i].getErrors()[0].getMessage());
        }
    }
    System.debug(LoggingLevel.WARN, 'REAPPLY 저장 ' + ok + ' / ' + changes.size());
} else if (!APPLY) {
    System.debug(LoggingLevel.WARN, 'REAPPLY 미리 보기만 (APPLY = false)');
}
