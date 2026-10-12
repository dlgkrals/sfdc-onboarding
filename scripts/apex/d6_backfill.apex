// D6 실습: 새 필드(RecentCaseCount__c·RepeatFailure__c) 초기 적재 — 배포 직후 1회
// 새 필드는 처음에 비어 있어 Batch 대상 조건(최근 접수 수 > 0 또는 반복 고장)에 걸리는 장비가 없으므로,
// 접수가 있는 장비 전체를 한 번 재계산해 값을 채움. 이후에는 접수 트리거와 매일 밤 Batch가 유지
// WARN: 장비가 수천 대 이상이면 이 스크립트 대신 Batch를 전체 대상 조건으로 한 번 돌릴 것 (한 트랜잭션 DML 행 10,000 한도)
Set<Id> assetIds = new Set<Id>();
for (AggregateResult ar : [SELECT AssetId assetId FROM Case WHERE AssetId != null GROUP BY AssetId]) {
    assetIds.add((Id) ar.get('assetId'));
}
Integer repeatBefore = [SELECT COUNT() FROM Asset WHERE RepeatFailure__c = true];
Integer saved = CaseStatsService.recalculateAssetCaseStats(assetIds);
Integer repeatAfter = [SELECT COUNT() FROM Asset WHERE RepeatFailure__c = true];
Integer withRecent = [SELECT COUNT() FROM Asset WHERE RecentCaseCount__c > 0];
System.debug(LoggingLevel.WARN, '초기 적재  접수 있는 장비 ' + assetIds.size() + '대 중 저장 성공 ' + saved
    + '대, 최근 90일 접수 있는 장비 ' + withRecent + '대, 반복 고장 장비 ' + repeatBefore + ' → ' + repeatAfter + '대'
    + '  SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements());
