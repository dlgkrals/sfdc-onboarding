// 장비 누적 청구액(Asset.TotalWorkOrderCharge__c) 일괄 계산 — 2026-10-16 (출동 트리거 도입 전 데이터 1회)
// APPLY = false: 대상 장비 수·바뀔 장비 수·합계만 보여 줌 / true: WorkOrderChargeService로 저장
// 합계 대상 = 방문한 출동(도착·승인 대기·완료). 출동이 없으면 0
// 익명 Apex는 WITH SYSTEM_MODE를 쓸 수 없음 → 관리자로 실행(저장은 서비스가 SYSTEM_MODE)
// WARN: 장비 수천 대 이상이면 Batch로 나눌 것(이 스크립트는 한 트랜잭션, 장비 10,000대 이하 가정)
Boolean APPLY = false;

Map<Id, Decimal> expectedByAsset = new Map<Id, Decimal>();
for (AggregateResult ar : [
  SELECT AssetId assetId, SUM(fmTotalCharge__c) total
  FROM WorkOrder
  WHERE AssetId != NULL AND Status IN :WorkOrderChargeService.VISITED_STATUSES
  GROUP BY AssetId
]) {
  expectedByAsset.put((Id) ar.get('assetId'), (Decimal) ar.get('total'));
}
Set<Id> allIds = new Set<Id>();
Integer changing = 0;
Decimal grandTotal = 0;
for (Asset a : [SELECT Id, TotalWorkOrderCharge__c FROM Asset]) {
  allIds.add(a.Id);
  Decimal expected = expectedByAsset.containsKey(a.Id)
    ? expectedByAsset.get(a.Id)
    : 0;
  grandTotal += expected;
  if (a.TotalWorkOrderCharge__c != expected) {
    changing++;
  }
}
System.debug(
  LoggingLevel.WARN,
  'BACKFILL 장비 ' +
    allIds.size() +
    '대 · 출동 합계가 있는 장비 ' +
    expectedByAsset.size() +
    '대 · 바뀔 장비 ' +
    changing +
    '대 · 전체 합계 ' +
    grandTotal +
    ' · APPLY=' +
    APPLY
);
if (APPLY) {
  Integer saved = WorkOrderChargeService.recalculateAssetTotals(allIds);
  System.debug(LoggingLevel.WARN, 'BACKFILL 저장 ' + saved + '대');
}
