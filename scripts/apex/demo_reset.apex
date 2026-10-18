// 발표 시연 데이터 리셋 — [시연/…] 데이터를 처음 상태로 (2026-10-18, 처음 상태 = demo_setup.apex 실행 직후)
// APPLY = false: 지울 것·되돌릴 것 건수만 출력 / true: 저장
// 순서: ① 이 스크립트(APPLY = true) → ② d7_erp_seed.apex (ERP 재고 = Salesforce 재고, 콜아웃이라 따로 실행) → ③ docs/demo_checklist.md 점검
// 처음 상태의 기준 = BASELINE(준비 끝난 시각). [시연/…] 접수 아래에서 이 시각 이후에 생긴 것은 연습 데이터로 보고 지움
//  - 연습 중 생긴 출동·사용 부품·재고 이동, 연습 사용자(이서연·김병철·최민호)가 만든 일반 접수(가상 착신 연습)
//  - 승인 대기는 회수(Removed). 지난 승인 이력(ProcessInstance)은 지울 수 없어 출동 "승인 내역"에 남음
//  - 처음부터 있던 출동·접수는 상태·소유자·승인 필드를 시나리오 시작 값으로
//  - 최민호 차량·경기남부 창고 재고 = 아래 기준값(기준값에 없는 재고는 0)
// WARN: 사용 부품 삭제 규칙(대기·완료 삭제 거부)은 이 실행에서만 우회(TriggerHandler.bypassedHandlers). 종결 접수 되돌리기는 실행 사용자에게 HG_BypassValidation 필요(HG_Admin)
Boolean APPLY = false;
Datetime BASELINE = Datetime.newInstanceGmt(2026, 10, 18, 1, 48, 0);
Set<Id> PRACTICE_USER_IDS = new Set<Id>{ '005aj00000fWXXVAA4', '005aj00000ewE9JAAU', '005aj00000fWYF3AAO' };
String TECH_USERNAME = 'minho.choi@hangyeol-as.dev';
String QUEUE = 'HG_GyeonggiSouthCases';

// DESC: 재고 기준값 (위치 코드|ERP 부품 코드 → 수량), 2026-10-18 준비 직후 Salesforce = ERP
Map<String, Decimal> baselineStock = new Map<String, Decimal>{
  'VAN-GS-001|CMP-404-50' => 3, 'VAN-GS-001|HG-P-CB7' => 6, 'VAN-GS-001|HG-P-DP4' => 1, 'VAN-GS-001|HG-P-EV12' => 6,
  'VAN-GS-001|HG-P-FM30' => 6, 'VAN-GS-001|HG-P-FT10' => 1, 'VAN-GS-001|RFG-404A' => 14,
  'WH-GS-001|CMP-404-50' => 6, 'WH-GS-001|HG-P-CB7' => 14, 'WH-GS-001|HG-P-CP200' => 5, 'WH-GS-001|HG-P-CP350' => 5,
  'WH-GS-001|HG-P-CP500' => 5, 'WH-GS-001|HG-P-DP4' => 19, 'WH-GS-001|HG-P-EV12' => 14, 'WH-GS-001|HG-P-FM30' => 14,
  'WH-GS-001|HG-P-FM50' => 20, 'WH-GS-001|HG-P-FT10' => 19, 'WH-GS-001|HG-P-R32' => 50, 'WH-GS-001|HG-P-R410A' => 50,
  'WH-GS-001|HG-P-TS2' => 20, 'WH-GS-001|RFG-404A' => 54
};
// DESC: 시나리오 시작 값 — 접수 상태, 처음부터 있던 출동 상태(null = 출동 없음)
Map<String, List<String>> startByScenario = new Map<String, List<String>>{
  '기사 배정' => new List<String>{ 'New', null },
  '보증 내 무상' => new List<String>{ 'InProgress', 'Arrived' },
  '유상 50만 이하' => new List<String>{ 'InProgress', 'Arrived' },
  '유상 50만 초과' => new List<String>{ 'InProgress', 'Arrived' },
  '예외 무상' => new List<String>{ 'InProgress', 'Arrived' },
  '승인 반려' => new List<String>{ 'InProgress', 'Arrived' },
  '기사 거절' => new List<String>{ 'InProgress', 'Assigned' },
  '재고 부족' => new List<String>{ 'InProgress', 'Arrived' },
  '중복 접수' => new List<String>{ 'InProgress', null },
  '종결 대기' => new List<String>{ 'Completed', 'Completed' }
};

List<Case> demoCases = [SELECT Id, CaseNumber, Subject, Status, OwnerId, CancelReason__c FROM Case WHERE Subject LIKE '[시연/%' AND CreatedDate < :BASELINE];
List<Case> practiceCases = [SELECT Id, CaseNumber, Subject FROM Case WHERE CreatedDate > :BASELINE AND CreatedById IN :PRACTICE_USER_IDS AND (NOT Subject LIKE '[시연/%')];
Set<Id> caseIds = new Set<Id>();
for (Case c : demoCases) { caseIds.add(c.Id); }
for (Case c : practiceCases) { caseIds.add(c.Id); }

List<WorkOrder> allWos = [SELECT Id, WorkOrderNumber, CaseId, CreatedDate, Status, OwnerId, ApprovalStatus__c, ApprovalRequestReason__c, ApprovalRejectReason__c, CustomerConsent__c, ApprovalSummary__c, DeclineReason__c, CompletionResult__c, CompletedDateTime__c FROM WorkOrder WHERE CaseId IN :caseIds];
List<WorkOrder> practiceWos = new List<WorkOrder>();
List<WorkOrder> baseWos = new List<WorkOrder>();
Set<Id> woIds = new Set<Id>();
for (WorkOrder wo : allWos) {
  woIds.add(wo.Id);
  if (wo.CreatedDate > BASELINE) { practiceWos.add(wo); } else { baseWos.add(wo); }
}
List<ProductConsumed> practiceParts = [SELECT Id, ProductConsumedNumber, ErpSyncStatus__c FROM ProductConsumed WHERE WorkOrderId IN :woIds AND CreatedDate > :BASELINE];
List<ProcessInstanceWorkitem> pendingApprovals = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId IN :woIds];
Integer otherPending = [SELECT COUNT() FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId NOT IN :woIds];
List<ProductTransfer> practiceTransfers = [SELECT Id, ProductTransferNumber FROM ProductTransfer WHERE CreatedDate > :BASELINE];

Id techId = [SELECT Id FROM User WHERE Username = :TECH_USERNAME].Id;
Id queueId = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :QUEUE].Id;
Map<Id, String> scenarioByCaseId = new Map<Id, String>();
for (Case c : demoCases) {
  scenarioByCaseId.put(c.Id, c.Subject.substringBetween('[시연/', ']'));
}

// DESC: 처음부터 있던 출동 → 시작 값
List<WorkOrder> woRestores = new List<WorkOrder>();
for (WorkOrder wo : baseWos) {
  List<String> start = startByScenario.get(scenarioByCaseId.get(wo.CaseId));
  if (start == null || start[1] == null) { continue; }
  WorkOrder r = new WorkOrder(Id = wo.Id, Status = start[1], OwnerId = techId, ApprovalStatus__c = null, ApprovalRequestReason__c = null, ApprovalRejectReason__c = null, CustomerConsent__c = false, ApprovalSummary__c = null, DeclineReason__c = null);
  if (start[1] != 'Completed') { r.CompletionResult__c = null; r.CompletedDateTime__c = null; }
  if (start[1] == 'Assigned') { r.ArrivalDateTime__c = null; }
  Boolean changed = wo.Status != start[1] || wo.OwnerId != techId || wo.ApprovalStatus__c != null || wo.ApprovalRequestReason__c != null || wo.ApprovalRejectReason__c != null || wo.CustomerConsent__c || wo.ApprovalSummary__c != null || wo.DeclineReason__c != null;
  if (changed) { woRestores.add(r); }
}
// DESC: 접수 → 시작 값
List<Case> caseRestores = new List<Case>();
for (Case c : demoCases) {
  List<String> start = startByScenario.get(scenarioByCaseId.get(c.Id));
  if (start == null) { continue; }
  if (c.Status != start[0] || c.OwnerId != queueId || c.CancelReason__c != null) {
    caseRestores.add(new Case(Id = c.Id, Status = start[0], OwnerId = queueId, CancelReason__c = null));
  }
}
// DESC: 재고 → 기준값
List<ProductItem> stockRestores = new List<ProductItem>();
List<String> stockDiffs = new List<String>();
for (ProductItem p : [SELECT Id, Location.ErpLocationCode__c, Product2.ErpPartCode__c, QuantityOnHand FROM ProductItem WHERE Location.ErpLocationCode__c IN ('VAN-GS-001', 'WH-GS-001')]) {
  String key = p.Location.ErpLocationCode__c + '|' + p.Product2.ErpPartCode__c;
  Decimal target = baselineStock.containsKey(key) ? baselineStock.get(key) : 0;
  if (p.QuantityOnHand != target) {
    stockRestores.add(new ProductItem(Id = p.Id, QuantityOnHand = target));
    stockDiffs.add(key + ' ' + p.QuantityOnHand + '→' + target);
  }
}

System.debug(LoggingLevel.WARN, 'RESET APPLY=' + APPLY + ' · 기준 시각 ' + BASELINE.formatGmt('yyyy-MM-dd HH:mm') + ' UTC · 시연 접수 ' + demoCases.size() + ' (처음 출동 ' + baseWos.size() + ')');
System.debug(LoggingLevel.WARN, 'RESET 지울 것: 연습 출동 ' + practiceWos.size() + ' · 연습 사용 부품 ' + practiceParts.size() + ' · 연습 접수 ' + practiceCases.size() + ' · 연습 재고 이동 ' + practiceTransfers.size() + ' · 승인 대기 회수 ' + pendingApprovals.size() + ' (시연 밖 승인 대기 ' + otherPending + ')');
System.debug(LoggingLevel.WARN, 'RESET 되돌릴 것: 출동 ' + woRestores.size() + ' · 접수 ' + caseRestores.size() + ' · 재고 ' + stockRestores.size() + ' ' + stockDiffs);
for (WorkOrder wo : practiceWos) { System.debug(LoggingLevel.WARN, '  연습 출동 ' + wo.WorkOrderNumber + ' ' + wo.Status); }
for (Case c : practiceCases) { System.debug(LoggingLevel.WARN, '  연습 접수 ' + c.CaseNumber + ' ' + c.Subject); }
if (!APPLY) {
  return;
}

// 1) 승인 대기 회수 (잠금 해제)
List<Approval.ProcessWorkitemRequest> removals = new List<Approval.ProcessWorkitemRequest>();
for (ProcessInstanceWorkitem w : pendingApprovals) {
  Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
  req.setWorkitemId(w.Id);
  req.setAction('Removed');
  req.setComments('시연 리셋');
  removals.add(req);
}
if (!removals.isEmpty()) { Approval.process(removals); }
// 2) 연습 사용 부품 삭제 (삭제 규칙 우회, Salesforce 재고는 표준이 되돌리고 아래 기준값으로 다시 맞춤)
TriggerHandler.bypassedHandlers.add('ProductConsumedTriggerHandler');
delete practiceParts;
TriggerHandler.bypassedHandlers.remove('ProductConsumedTriggerHandler');
// 3) 연습 출동·접수·재고 이동 삭제
delete practiceWos;
delete practiceCases;
List<Database.DeleteResult> transferResults = Database.delete(practiceTransfers, false);
Integer transferFailed = 0;
for (Database.DeleteResult r : transferResults) { if (!r.isSuccess()) { transferFailed++; } }
// 4) 처음 출동·접수를 시작 값으로 (출동 먼저 — 접수 자동 완료·재오픈이 출동 상태를 따라감)
update woRestores;
List<Case> caseFinal = new List<Case>();
for (Case c : [SELECT Id, Subject, Status, OwnerId, CancelReason__c FROM Case WHERE Id IN :scenarioByCaseId.keySet()]) {
  List<String> start = startByScenario.get(scenarioByCaseId.get(c.Id));
  if (start != null && (c.Status != start[0] || c.OwnerId != queueId || c.CancelReason__c != null)) {
    caseFinal.add(new Case(Id = c.Id, Status = start[0], OwnerId = queueId, CancelReason__c = null));
  }
}
update caseFinal;
// 5) 재고 기준값 (표준 되돌림 이후 값을 다시 읽어 맞춤)
List<ProductItem> stockFinal = new List<ProductItem>();
for (ProductItem p : [SELECT Id, Location.ErpLocationCode__c, Product2.ErpPartCode__c, QuantityOnHand FROM ProductItem WHERE Location.ErpLocationCode__c IN ('VAN-GS-001', 'WH-GS-001')]) {
  String key = p.Location.ErpLocationCode__c + '|' + p.Product2.ErpPartCode__c;
  Decimal target = baselineStock.containsKey(key) ? baselineStock.get(key) : 0;
  if (p.QuantityOnHand != target) { stockFinal.add(new ProductItem(Id = p.Id, QuantityOnHand = target)); }
}
update stockFinal;
System.debug(LoggingLevel.WARN, 'RESET 완료 · 회수 ' + removals.size() + ' · 삭제 부품 ' + practiceParts.size() + '/출동 ' + practiceWos.size() + '/접수 ' + practiceCases.size() + '/이동 ' + (practiceTransfers.size() - transferFailed) + (transferFailed > 0 ? ' (이동 삭제 실패 ' + transferFailed + ' — 재고는 기준값으로 맞춤)' : '') + ' · 출동 ' + woRestores.size() + ' · 접수 ' + caseFinal.size() + ' · 재고 ' + stockFinal.size() + ' → 다음: d7_erp_seed.apex');
