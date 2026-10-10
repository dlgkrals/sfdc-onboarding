// D5 실습: 접수 N건 update 시 CaseTrigger(after update)가 필요한 경우에만 장비를 재계산하는지 확인
// 준비(insert)는 측정 구간 밖. update 3종을 각각 1회 DML로 실행하고 구간별 SOQL·DML을 기록
//   ① 제목만 수정        → 재계산 없음 (저장 전 Flow도 AssetId가 안 바뀌어 미실행)
//   ② 장비 변경          → 이전 장비 + 새 장비 재계산
//   ③ 취소로 전환        → 누적 수에서 제외되도록 재계산 (취소 사유 필수: Validation Rule)
// 20건과 200건으로 각각 실행해 구간별 SOQL·DML "횟수"가 같은지 비교. 정리: d5_cleanup.apex (제목 접두사 [BULK5])
Integer N = 200;   // 비교용으로 20도 실행

// 0. 준비: 대상 장비 조회 + 접수 N건 insert (측정 구간 밖)
// WARN: 냉동창고·서버실 사업장 장비는 Flow가 긴급으로 바꿔 건마다 알림 메일이 나가므로 제외
List<Asset> assets = [
    SELECT Id FROM Asset
    WHERE Status = 'Installed' AND CustomerSite__c != null
      AND CustomerSite__r.UsageType__c NOT IN ('ColdStorage', 'ServerRoom')
    ORDER BY SerialKey__c
    LIMIT 200
];
Set<Id> assetIds = new Map<Id, Asset>(assets).keySet();
List<Case> cases = new List<Case>();
for (Integer i = 0; i < N; i++) {
    cases.add(new Case(
        AssetId = assets[Math.mod(i, assets.size())].Id,
        Subject = '[BULK5] 트리거 update 벌크 접수 ' + i,
        Status = 'New',
        Origin = 'Phone'
    ));
}
insert cases;
AggregateResult before = [SELECT SUM(TotalCaseCount__c) total FROM Asset WHERE Id IN :assetIds];
System.debug(LoggingLevel.WARN, '0.준비  접수 ' + N + '건 insert, 대상 장비 ' + assets.size() + '대, 누적 접수 합계=' + before.get('total')
    + '  (누적 SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows() + ')');

Integer soqlBefore;
Integer dmlBefore;
Integer rowsBefore;

// ① 제목만 수정 → after update는 재계산 대상이 없어 Asset DML이 없어야 함
for (Case c : cases) {
    c.Subject = c.Subject + ' (제목 수정)';
}
soqlBefore = Limits.getQueries(); dmlBefore = Limits.getDmlStatements(); rowsBefore = Limits.getDmlRows();
update cases;
System.debug(LoggingLevel.WARN, '1.제목만 수정  SOQL +' + (Limits.getQueries() - soqlBefore)
    + '  DML +' + (Limits.getDmlStatements() - dmlBefore) + '  Rows +' + (Limits.getDmlRows() - rowsBefore));

// ② 장비 변경 (다음 장비로 한 칸씩 이동) → 이전·새 장비 재계산
for (Integer i = 0; i < cases.size(); i++) {
    cases[i].AssetId = assets[Math.mod(i + 1, assets.size())].Id;
}
soqlBefore = Limits.getQueries(); dmlBefore = Limits.getDmlStatements(); rowsBefore = Limits.getDmlRows();
update cases;
System.debug(LoggingLevel.WARN, '2.장비 변경  SOQL +' + (Limits.getQueries() - soqlBefore)
    + '  DML +' + (Limits.getDmlStatements() - dmlBefore) + '  Rows +' + (Limits.getDmlRows() - rowsBefore));

// ③ 취소로 전환 → 누적 수에서 제외
for (Case c : cases) {
    c.Status = 'Canceled';
    c.CancelReason__c = '벌크 검증용 취소';
}
soqlBefore = Limits.getQueries(); dmlBefore = Limits.getDmlStatements(); rowsBefore = Limits.getDmlRows();
update cases;
System.debug(LoggingLevel.WARN, '3.취소 전환  SOQL +' + (Limits.getQueries() - soqlBefore)
    + '  DML +' + (Limits.getDmlStatements() - dmlBefore) + '  Rows +' + (Limits.getDmlRows() - rowsBefore));

// 4. 결과 확인: 모두 취소됐으므로 장비 누적 합계는 준비 전 값(이번 접수 제외)과 같아야 함
AggregateResult after = [SELECT SUM(TotalCaseCount__c) total FROM Asset WHERE Id IN :assetIds];
Integer actual = [SELECT COUNT() FROM Case WHERE AssetId IN :assetIds AND Status != 'Canceled'];
System.debug(LoggingLevel.WARN, '4.결과  누적 접수 합계 ' + before.get('total') + ' → ' + after.get('total')
    + ' (취소 제외 실제 접수 수 ' + actual + '와 같아야 함)');
