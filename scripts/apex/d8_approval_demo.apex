// 승인 요청 Screen Flow 시연 데이터 5건 (최민호 출동, 표시: 제목 [APV-TEST])
// 정리: 아래 CLEANUP = true로 실행하면 [APV-TEST] 접수·출동 삭제 (승인 대기 건은 먼저 회수·처리)
Boolean CLEANUP = false;
String TAG = '[APV-TEST]';
if (CLEANUP) {
  delete [SELECT Id FROM WorkOrder WHERE Subject LIKE '[APV-TEST]%'];
  delete [SELECT Id FROM Case WHERE Subject LIKE '[APV-TEST]%'];
  System.debug(LoggingLevel.WARN, 'APV 정리 완료');
  return;
}
User tech = [SELECT Id FROM User WHERE Username = 'minho.choi@hangyeol-as.dev'];
// DESC: 최민호의 기존 시연 출동 00000035와 같은 장비 (사업장·센터가 기사에게 맞음)
Asset asset = [
  SELECT Id, Name
  FROM Asset
  WHERE Id IN (SELECT AssetId FROM WorkOrder WHERE WorkOrderNumber = '00000035')
  LIMIT 1
];
// 시나리오: 제목 · 출동 상태 · 방문비(= 청구 합계, 부품 없음)
List<List<Object>> scenarios = new List<List<Object>>{
  new List<Object>{ '기준 초과 60만 → 동의 필요', 'Arrived', 600000 },
  new List<Object>{ '기준 초과 120만 → 동의 필요', 'Arrived', 1200000 },
  new List<Object>{ '기준과 같음 50만 → 승인 불필요', 'Arrived', 500000 },
  new List<Object>{ '방문비만 3만 → 승인 불필요', 'Arrived', 30000 },
  new List<Object>{ '도착 전 70만 → 안내만', 'Accepted', 700000 }
};
List<Case> cases = new List<Case>();
for (List<Object> s : scenarios) {
  cases.add(new Case(AssetId = asset.Id, Subject = TAG + ' ' + s[0], Status = 'New', Origin = 'Phone', SymptomType__c = 'NoCooling'));
}
insert cases;
List<WorkOrder> wos = new List<WorkOrder>();
for (Integer i = 0; i < scenarios.size(); i++) {
  wos.add(new WorkOrder(CaseId = cases[i].Id, AssetId = asset.Id, Subject = cases[i].Subject, OwnerId = tech.Id, Status = 'Assigned', VisitFee__c = (Integer) scenarios[i][2]));
}
insert wos;
for (Integer i = 0; i < wos.size(); i++) {
  wos[i].Status = (String) scenarios[i][1];
}
update wos;
for (WorkOrder w : [SELECT WorkOrderNumber, Subject, Status, fmTotalCharge__c, fmNeedsApproval__c FROM WorkOrder WHERE Id IN :wos ORDER BY WorkOrderNumber]) {
  System.debug(LoggingLevel.WARN, 'APV ' + w.WorkOrderNumber + ' | ' + w.Status + ' | ' + w.fmTotalCharge__c + ' | 승인필요=' + w.fmNeedsApproval__c + ' | ' + w.Subject);
}
