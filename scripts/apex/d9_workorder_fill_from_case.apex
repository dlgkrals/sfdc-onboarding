// 기존 출동의 비어 있는 장비·고객사·사업장·서비스센터를 접수 값으로 채움 — 2026-10-16 (안전망 Flow 도입 전 데이터 1회)
// APPLY = false: 대상 건수만 / true: 저장 (저장 전 Flow WorkOrder_BeforeSave_FillAsset이 같은 규칙으로 채우므로 빈 update로 충분)
// 서비스센터가 채워지면 조건 기준 공유 규칙(센터 출동 → 센터장)이 자동으로 다시 계산됨
Boolean APPLY = false;

List<WorkOrder> targets = [
  SELECT Id, WorkOrderNumber, Status, AssetId, AccountId, CustomerSite__c, ServiceCenter__c, Case.ServiceCenter__c
  FROM WorkOrder
  WHERE CaseId != null
    AND (AssetId = null OR AccountId = null OR CustomerSite__c = null OR ServiceCenter__c = null)
];
for (WorkOrder wo : targets) {
  System.debug(LoggingLevel.WARN, 'FILL 대상 ' + wo.WorkOrderNumber + ' 상태=' + wo.Status + ' 센터=' + wo.ServiceCenter__c + ' → 접수 센터=' + wo.Case.ServiceCenter__c);
}
System.debug(LoggingLevel.WARN, 'FILL 대상 ' + targets.size() + '건 · APPLY=' + APPLY);
if (APPLY && !targets.isEmpty()) {
  List<WorkOrder> touch = new List<WorkOrder>();
  for (WorkOrder wo : targets) {
    touch.add(new WorkOrder(Id = wo.Id));
  }
  update touch;
  Integer stillBlank = [SELECT COUNT() FROM WorkOrder WHERE Id IN :touch AND (AccountId = null OR CustomerSite__c = null OR ServiceCenter__c = null)];
  System.debug(LoggingLevel.WARN, 'FILL 저장 ' + touch.size() + '건 · 남은 빈칸 ' + stillBlank + '건');
}
