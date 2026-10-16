// B1 시연 데이터 정리 — 2026-10-16 (Edwin 승인: 출동 9건 완료(빈 도착 일시 = 생성 + 1시간), 출동 00000041 삭제(방문 전·부품 없음, 10-16 최민호 거절 상태), 접수 11건 취소, 00001026 완료)
// APPLY = false: 대상 건수만 / true: 저장. 실행 순서 B1 → B2 → B3 → C(d9_asset_charge_backfill → d9_parent_charge_backfill)
Boolean APPLY = false;
String REASON = '테스트 데이터 정리';
List<String> woNumbers = new List<String>{ '00000001','00000033','00000034','00000035','00000036','00000037','00000038','00000039','00000040' };
List<WorkOrder> wos = [SELECT Id, WorkOrderNumber, Status, ArrivalDateTime__c, CreatedDate FROM WorkOrder WHERE WorkOrderNumber IN :woNumbers];
for (WorkOrder wo : wos) {
  if (wo.ArrivalDateTime__c == null) { wo.ArrivalDateTime__c = wo.CreatedDate.addHours(1); }
  wo.Status = 'Completed';
}
if (APPLY) { update wos; }
System.debug(LoggingLevel.WARN, 'B1 출동 완료 대상 ' + wos.size());
List<WorkOrder> wo41 = [SELECT Id FROM WorkOrder WHERE WorkOrderNumber = '00000041' AND Status IN ('Assigned','Accepted','Declined') AND Id NOT IN (SELECT WorkOrderId FROM ProductConsumed)];
if (APPLY) { delete wo41; }
System.debug(LoggingLevel.WARN, 'B1 출동 00000041 삭제 대상 ' + wo41.size());
List<String> cancelNumbers = new List<String>{ '00001968','00001969','00001970','00001971','00001972','00001763','00001764','00001765','00001966','00001967','00001973' };
List<Case> cancels = [SELECT Id FROM Case WHERE CaseNumber IN :cancelNumbers AND Status NOT IN ('Closed','Canceled')];
for (Case c : cancels) { c.Status = 'Canceled'; c.CancelReason__c = REASON; }
if (APPLY) { update cancels; }
System.debug(LoggingLevel.WARN, 'B1 접수 취소 대상 ' + cancels.size());
List<Case> done = [SELECT Id FROM Case WHERE CaseNumber = '00001026' AND Status NOT IN ('Closed','Canceled')];
for (Case c : done) { c.Status = 'Completed'; }
if (APPLY) { update done; }
System.debug(LoggingLevel.WARN, 'B1 접수 완료 대상 ' + done.size());
Asset a = [SELECT TotalWorkOrderCharge__c, VisitedWorkOrderCount__c FROM Asset WHERE SerialNumber = 'HG25CH500-0001'];
System.debug(LoggingLevel.WARN, 'B1 APPLY=' + APPLY);
System.debug(LoggingLevel.WARN, 'B1 장비 누적 ' + a.TotalWorkOrderCharge__c + ' / 방문 ' + a.VisitedWorkOrderCount__c);
