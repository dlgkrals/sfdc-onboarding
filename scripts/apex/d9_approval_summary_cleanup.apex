// 승인 요청 요약 org 확인용 [테스트] 정리 — 2026-10-16: 승인 회수 → 사용 부품(가격표 항목, 재고·ERP 무관) → 출동 → 접수 삭제
List<Case> cases = [SELECT Id, CaseNumber FROM Case WHERE Subject = '[테스트] 승인 요청 요약 확인'];
List<WorkOrder> wos = [SELECT Id, WorkOrderNumber FROM WorkOrder WHERE CaseId IN :cases];
List<ProductConsumed> parts = [SELECT Id, ProductItemId FROM ProductConsumed WHERE WorkOrderId IN :wos];
System.debug(LoggingLevel.WARN, 'CLEAN 대상 접수 ' + cases.size() + ' 출동 ' + wos.size() + ' 사용 부품 ' + parts.size());
for (ProductConsumed p : parts) { if (p.ProductItemId != null) { System.debug(LoggingLevel.WARN, 'CLEAN 중단: 재고 연결 부품'); return; } }
for (ProcessInstanceWorkitem wi : [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId IN :wos]) {
  Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
  req.setWorkitemId(wi.Id);
  req.setAction('Removed');
  req.setComments('org 확인 끝, 테스트 데이터 정리');
  System.debug(LoggingLevel.WARN, 'CLEAN 회수 ' + Approval.process(req).isSuccess());
}
TriggerHandler.bypassedHandlers.add('ProductConsumedTriggerHandler');
delete parts;
TriggerHandler.bypassedHandlers.remove('ProductConsumedTriggerHandler');
delete wos;
delete cases;
System.debug(LoggingLevel.WARN, 'CLEAN 남은 [테스트] 접수 ' + [SELECT COUNT() FROM Case WHERE Subject = '[테스트] 승인 요청 요약 확인']);
