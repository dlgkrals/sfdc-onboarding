// 승인 요청 요약 org 확인용 [테스트] 접수·출동 만들고 최민호 이름으로 제출 — 2026-10-16 (Edwin 승인). 정리는 d9_approval_summary_cleanup.apex
// 사용 부품은 가격표 항목 연결 + 트리거 우회 + ERP 상태 비움 → 재고·ERP 무영향. 대상 아님: 00001028, HG23PK100-0003, 00000042
Asset asset = [SELECT Id FROM Asset WHERE SerialNumber = 'HG-HAC300-2205-0005'];
User tech = [SELECT Id FROM User WHERE Username = 'minho.choi@hangyeol-as.dev'];
Pricebook2 book = [SELECT Id FROM Pricebook2 WHERE Name = 'Standard' AND IsActive = true AND IsStandard = false LIMIT 1];
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.assignmentRuleHeader.useDefaultRule = true;
Case c = new Case(AssetId = asset.Id, Subject = '[테스트] 승인 요청 요약 확인', SymptomType__c = 'NoCooling', Origin = 'Phone', Status = 'InProgress', Description = '승인 요청 요약 org 확인용(확인 후 삭제)');
c.setOptions(dmo);
insert c;
WorkOrder wo = new WorkOrder(CaseId = c.Id, AssetId = asset.Id, Subject = c.Subject, OwnerId = tech.Id, Status = 'Arrived', ArrivalDateTime__c = Datetime.now(), Pricebook2Id = book.Id, Purpose__c = 'Repair');
insert wo;
Map<String, PricebookEntry> pbeByCode = new Map<String, PricebookEntry>();
for (PricebookEntry e : [SELECT Id, Product2.ErpPartCode__c, Product2.ErpUnitPrice__c, Product2.Family FROM PricebookEntry WHERE Pricebook2Id = :book.Id AND Product2.ErpPartCode__c IN ('HG-P-CB7','HG-P-FT10')]) {
  pbeByCode.put(e.Product2.ErpPartCode__c, e);
}
List<ProductConsumed> parts = new List<ProductConsumed>{
  new ProductConsumed(WorkOrderId = wo.Id, PricebookEntryId = pbeByCode.get('HG-P-CB7').Id, QuantityConsumed = 2, AutoChargeType__c = 'Paid', ChargeType__c = 'Paid', UnitPriceAtUse__c = pbeByCode.get('HG-P-CB7').Product2.ErpUnitPrice__c, PartCategoryAtUse__c = 'General'),
  new ProductConsumed(WorkOrderId = wo.Id, PricebookEntryId = pbeByCode.get('HG-P-FT10').Id, QuantityConsumed = 1, AutoChargeType__c = 'Free', ChargeType__c = 'Free', UnitPriceAtUse__c = pbeByCode.get('HG-P-FT10').Product2.ErpUnitPrice__c, PartCategoryAtUse__c = 'General')
};
TriggerHandler.bypassedHandlers.add('ProductConsumedTriggerHandler');
insert parts;
for (ProductConsumed pc : parts) { pc.ErpSyncStatus__c = null; }
update parts;
TriggerHandler.bypassedHandlers.remove('ProductConsumedTriggerHandler');
Flow.Interview iv = Flow.Interview.createInterview('WorkOrder_Sub_SubmitApproval', new Map<String, Object>{
  'recordId' => wo.Id, 'requestReason' => '제어보드 2개 교체, 고객 유상 동의', 'customerConsent' => true,
  'submitterComment' => '테스트 메모: 단가 확인 부탁드립니다', 'submitterId' => tech.Id });
iv.start();
WorkOrder saved = [SELECT WorkOrderNumber, Status, fmTotalCharge__c, ApprovalSummary__c FROM WorkOrder WHERE Id = :wo.Id];
System.debug(LoggingLevel.WARN, 'CHK 접수 ' + [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber + ' 출동 ' + saved.WorkOrderNumber + ' 상태 ' + saved.Status + ' 청구 ' + saved.fmTotalCharge__c + ' 제출 ' + iv.getVariableValue('isSubmitted') + ' 오류 ' + iv.getVariableValue('errorMessage'));
System.debug(LoggingLevel.WARN, 'CHK 요약\n' + saved.ApprovalSummary__c);
for (ProcessInstanceWorkitem w : [SELECT Actor.Name, ProcessInstance.SubmittedBy.Name FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :wo.Id]) {
  System.debug(LoggingLevel.WARN, 'CHK 승인자 ' + w.Actor.Name + ' · 제출자 ' + w.ProcessInstance.SubmittedBy.Name);
}
