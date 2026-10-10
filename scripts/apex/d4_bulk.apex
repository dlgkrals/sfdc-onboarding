// D4 실습: 접수 N건을 한 번에 만들고 CaseStatsService를 실행해 한도 사용량 확인
// 20건과 200건으로 각각 실행해 SOQL·DML "횟수"가 같은지 비교 (행 수만 늘어야 정상)
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
System.debug(LoggingLevel.WARN, '대상 장비 ' + assets.size() + '대');

// 1. 접수 N건 준비 → insert 1회 (저장 전 Flow가 묶어서 실행됨)
List<Case> newCases = new List<Case>();
for (Integer i = 0; i < N; i++) {
    Asset a = assets[Math.mod(i, assets.size())];
    newCases.add(new Case(
        AssetId = a.Id,
        Subject = '[BULK] 테스트 접수 ' + i,
        Description = 'BULK_TEST_D4',
        Status = 'New',
        Origin = 'Phone'
    ));
}
insert newCases;
System.debug(LoggingLevel.WARN, '1.준비 후  SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows());

// 2. 메서드 A: 장비별 접수 집계 재계산
Set<Id> assetIds = new Set<Id>();
for (Case c : newCases) {
    assetIds.add(c.AssetId);
}
Integer updatedAssets = CaseStatsService.recalculateAssetCaseStats(assetIds);
System.debug(LoggingLevel.WARN, '2.집계 후  갱신 장비=' + updatedAssets + '  SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows());

// 3. 메서드 B: 반복 고장 일괄 표시
Set<Id> caseIds = new Map<Id, Case>(newCases).keySet();
Integer flagged = CaseStatsService.markRepeatFailures(caseIds);
System.debug(LoggingLevel.WARN, '3.반복고장 후  표시 접수=' + flagged + '  SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows());
