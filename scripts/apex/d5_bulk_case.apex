// D5 실습: 접수 N건을 insert만 하고, 트리거(CaseTrigger)가 반복 고장 표시·장비 집계를 처리하는지 확인
// 서비스를 직접 부르지 않음. 20건과 200건으로 각각 실행해 SOQL·DML "횟수"가 같은지 비교 (행 수만 늘어야 정상)
// 정리: d5_cleanup.apex (제목 접두사 [BULK5])
Integer N = 200;   // 비교용으로 20도 실행

// 0. 대상 장비 조회 (1회)
// WARN: 냉동창고·서버실 사업장 장비는 Flow가 긴급으로 바꿔 건마다 알림 메일이 나가므로 제외
List<Asset> assets = [
    SELECT Id FROM Asset
    WHERE Status = 'Installed' AND CustomerSite__c != null
      AND CustomerSite__r.UsageType__c NOT IN ('ColdStorage', 'ServerRoom')
    ORDER BY SerialKey__c
    LIMIT 200
];
Set<Id> assetIds = new Map<Id, Asset>(assets).keySet();

// 0-1. 실행 전 장비 누적 접수 수 합계 (1회)
AggregateResult before = [SELECT SUM(TotalCaseCount__c) total FROM Asset WHERE Id IN :assetIds];
Decimal totalBefore = (Decimal) before.get('total');
System.debug(LoggingLevel.WARN, '0.준비  대상 장비 ' + assets.size() + '대, 누적 접수 합계(전)=' + totalBefore
    + '  SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows());

// 1. 접수 N건 준비 → insert 1회 (저장 전 Flow → before insert 트리거 → 저장 → after insert 트리거)
List<Case> newCases = new List<Case>();
for (Integer i = 0; i < N; i++) {
    Asset a = assets[Math.mod(i, assets.size())];
    newCases.add(new Case(
        AssetId = a.Id,
        Subject = '[BULK5] 트리거 벌크 접수 ' + i,
        Status = 'New',
        Origin = 'Phone'
    ));
}
Integer soqlBefore = Limits.getQueries();
Integer dmlBefore = Limits.getDmlStatements();
Integer rowsBefore = Limits.getDmlRows();
insert newCases;
System.debug(LoggingLevel.WARN, '1.insert 구간  SOQL +' + (Limits.getQueries() - soqlBefore)
    + '  DML +' + (Limits.getDmlStatements() - dmlBefore) + '  Rows +' + (Limits.getDmlRows() - rowsBefore)
    + '  (누적 SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows() + ')');

// 2. 결과 확인 (조회 2회)
Set<Id> caseIds = new Map<Id, Case>(newCases).keySet();
Integer flagged = [SELECT COUNT() FROM Case WHERE Id IN :caseIds AND RepeatFailure__c = true];
AggregateResult after = [SELECT SUM(TotalCaseCount__c) total FROM Asset WHERE Id IN :assetIds];
Decimal totalAfter = (Decimal) after.get('total');
System.debug(LoggingLevel.WARN, '2.결과  반복 고장 표시=' + flagged + '/' + N
    + '  누적 접수 합계 ' + totalBefore + ' → ' + totalAfter + ' (증가 ' + (totalAfter - totalBefore) + ', 기대 ' + N + ')');
