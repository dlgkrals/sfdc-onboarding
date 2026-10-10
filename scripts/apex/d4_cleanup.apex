// D4 실습 정리: 테스트 접수 삭제 후 장비 집계를 원래대로 재계산
// WARN: Description은 긴 텍스트 영역이라 SOQL 조건에 쓸 수 없어 Subject 접두어로 찾음
List<Case> bulkCases = [SELECT Id, AssetId FROM Case WHERE Subject LIKE '[BULK]%'];
Set<Id> assetIds = new Set<Id>();
for (Case c : bulkCases) {
    assetIds.add(c.AssetId);
}
delete bulkCases;
Integer updated = CaseStatsService.recalculateAssetCaseStats(assetIds);
System.debug(LoggingLevel.WARN, '삭제 ' + bulkCases.size() + '건, 재계산 장비 ' + updated + '대');
