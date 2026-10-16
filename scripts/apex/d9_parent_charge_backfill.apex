// 고객사·사업장 누적 청구액(TotalWorkOrderCharge__c) 일괄 계산 — 2026-10-16 (필드 도입 전 데이터 1회)
// APPLY = false: 대상 수·바뀔 수·합계만 보여 줌 / true: WorkOrderChargeService로 저장
// 합계 대상 = 방문한 출동(도착·승인 대기·완료). 출동이 없으면 0
// 저장 실패(검증 규칙·사업장 주소 검사 등)는 서비스가 로그만 남기고 건너뜀 → "저장"과 "바뀔"의 차이가 실패 건수
// 익명 Apex는 WITH SYSTEM_MODE를 쓸 수 없음 → 관리자로 실행(저장은 서비스가 SYSTEM_MODE)
Boolean APPLY = false;

Map<Id, Decimal> expectedByAccount = new Map<Id, Decimal>();
for (AggregateResult ar : [
  SELECT AccountId parentId, SUM(fmTotalCharge__c) total
  FROM WorkOrder
  WHERE AccountId != NULL AND Status IN :WorkOrderChargeService.VISITED_STATUSES
  GROUP BY AccountId
]) {
  expectedByAccount.put((Id) ar.get('parentId'), (Decimal) ar.get('total'));
}
Map<Id, Decimal> expectedBySite = new Map<Id, Decimal>();
for (AggregateResult ar : [
  SELECT CustomerSite__c parentId, SUM(fmTotalCharge__c) total
  FROM WorkOrder
  WHERE CustomerSite__c != NULL AND Status IN :WorkOrderChargeService.VISITED_STATUSES
  GROUP BY CustomerSite__c
]) {
  expectedBySite.put((Id) ar.get('parentId'), (Decimal) ar.get('total'));
}

Set<Id> accountIds = new Set<Id>();
Integer accountChanging = 0;
Decimal accountGrand = 0;
for (Account a : [SELECT Id, TotalWorkOrderCharge__c FROM Account]) {
  accountIds.add(a.Id);
  Decimal expected = expectedByAccount.containsKey(a.Id) ? expectedByAccount.get(a.Id) : 0;
  accountGrand += expected;
  if (a.TotalWorkOrderCharge__c != expected) {
    accountChanging++;
  }
}
Set<Id> siteIds = new Set<Id>();
Integer siteChanging = 0;
Decimal siteGrand = 0;
for (CustomerSite__c s : [SELECT Id, TotalWorkOrderCharge__c FROM CustomerSite__c]) {
  siteIds.add(s.Id);
  Decimal expected = expectedBySite.containsKey(s.Id) ? expectedBySite.get(s.Id) : 0;
  siteGrand += expected;
  if (s.TotalWorkOrderCharge__c != expected) {
    siteChanging++;
  }
}
System.debug(LoggingLevel.WARN, 'BACKFILL 고객사 ' + accountIds.size() + '곳 · 합계 있는 ' + expectedByAccount.size() + ' · 바뀔 ' + accountChanging + ' · 전체 합계 ' + accountGrand);
System.debug(LoggingLevel.WARN, 'BACKFILL 사업장 ' + siteIds.size() + '곳 · 합계 있는 ' + expectedBySite.size() + ' · 바뀔 ' + siteChanging + ' · 전체 합계 ' + siteGrand + ' · APPLY=' + APPLY);
if (APPLY) {
  Integer savedAccounts = WorkOrderChargeService.recalculateTotals(accountIds, WorkOrder.AccountId, Account.TotalWorkOrderCharge__c);
  Integer savedSites = WorkOrderChargeService.recalculateTotals(siteIds, WorkOrder.CustomerSite__c, CustomerSite__c.TotalWorkOrderCharge__c);
  System.debug(LoggingLevel.WARN, 'BACKFILL 저장 고객사 ' + savedAccounts + '곳 · 사업장 ' + savedSites + '곳');
}
