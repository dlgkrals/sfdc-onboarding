// B3 발표 시연 데이터 — 2026-10-16 (Edwin 승인). B1·B2 다음에 실행. 같은 제목이 이미 있으면 그 항목은 건너뜀(다시 실행해도 안전)
// 1) 제품 이름 "1kg" 정리 2건(단위 kg·ERP 코드는 그대로)
// 2) [시연] 배정 대기 접수: 세광전자 물류센터(경기남부) HG-HAC500-2309-0025, 상태 접수·출동 없음 → 발표 때 [기사 배정]
// 3) [시연] 압축기 교체: 새한식품 2창고(경기남부, 보증 만료) HG-HAC500-2206-0053 → [기사 배정](DispatchService, 최민호) → 도착 + 압축기 50HP 1대(PI-0001, 유상)
//    → 총 청구액 50만 원 초과, 승인 요청 사유는 비움(발표 중 [승인 요청]). 부품 저장 시 ERP 차감 전송(차량 압축기 1 → 0)
// 4) [시연] 진행 중 접수: HG25CH500-0001, 상태 처리 중 → 가상 착신 중복 경고용
// 접수는 할당 규칙을 적용해 센터 Queue 소유(센터장이 보게)
Boolean APPLY = false;
String SUBJECT_WAITING = '[시연] 배정 대기 접수 · 냉방 불가';
String SUBJECT_APPROVAL = '[시연] 압축기 교체 · 냉방 불가';
String SUBJECT_OPEN = '[시연] 진행 중 접수 · 소음';

List<Product2> products = [SELECT Id, Name FROM Product2 WHERE Name IN ('냉매 R-410A 1kg', '냉매 R-32 1kg')];
for (Product2 p : products) {
  p.Name = p.Name.removeEnd(' 1kg');
}
Set<String> existing = new Set<String>();
for (Case c : [SELECT Subject FROM Case WHERE Subject LIKE '[시연]%' AND Status NOT IN ('Closed', 'Canceled')]) {
  existing.add(c.Subject);
}
Map<String, Asset> assetsBySerial = new Map<String, Asset>();
for (Asset a : [SELECT Id, SerialNumber FROM Asset WHERE SerialNumber IN ('HG-HAC500-2309-0025', 'HG-HAC500-2206-0053', 'HG25CH500-0001')]) {
  assetsBySerial.put(a.SerialNumber, a);
}
System.debug(LoggingLevel.WARN, 'B3 제품 이름 ' + products.size() + ' · 장비 ' + assetsBySerial.size() + '/3 · 이미 있는 시연 접수 ' + existing + ' · APPLY=' + APPLY);
if (!APPLY) {
  return;
}
update products;

Database.DMLOptions dmo = new Database.DMLOptions();
dmo.assignmentRuleHeader.useDefaultRule = true;
List<Case> cases = new List<Case>();
if (!existing.contains(SUBJECT_WAITING)) {
  Case c = new Case(AssetId = assetsBySerial.get('HG-HAC500-2309-0025').Id, Subject = SUBJECT_WAITING, SymptomType__c = 'NoCooling', Origin = 'Phone', Status = 'New', Description = '발표 시연용: 센터장이 [기사 배정]으로 출동을 만듭니다.');
  c.setOptions(dmo);
  cases.add(c);
}
Case approvalCase;
if (!existing.contains(SUBJECT_APPROVAL)) {
  approvalCase = new Case(AssetId = assetsBySerial.get('HG-HAC500-2206-0053').Id, Subject = SUBJECT_APPROVAL, SymptomType__c = 'NoCooling', Origin = 'Phone', Status = 'New', Description = '발표 시연용: 압축기 교체(유상) → 기사가 [승인 요청] → 센터장 승인.');
  approvalCase.setOptions(dmo);
  cases.add(approvalCase);
}
if (!existing.contains(SUBJECT_OPEN)) {
  Case c = new Case(AssetId = assetsBySerial.get('HG25CH500-0001').Id, Subject = SUBJECT_OPEN, SymptomType__c = 'Noise', Origin = 'Phone', Status = 'InProgress', Description = '발표 시연용: 가상 착신에서 이 장비를 고르면 진행 중 접수 경고가 뜹니다.');
  c.setOptions(dmo);
  cases.add(c);
}
insert cases;
System.debug(LoggingLevel.WARN, 'B3 접수 생성 ' + cases.size());

if (approvalCase != null) {
  User tech = [SELECT Id FROM User WHERE Username = 'minho.choi@hangyeol-as.dev'];
  DispatchService.DispatchRequest req = new DispatchService.DispatchRequest();
  req.action = DispatchService.ACTION_DISPATCH;
  req.caseId = approvalCase.Id;
  req.technicianId = tech.Id;
  req.purpose = 'PartReplacement';
  req.plannedStart = Datetime.now();
  req.instruction = '압축기 50HP 교체';
  DispatchService.DispatchResult res = DispatchService.run(new List<DispatchService.DispatchRequest>{ req })[0];
  System.debug(LoggingLevel.WARN, 'B3 배정 ' + res.success + ' ' + res.message);
  if (res.success) {
    update new WorkOrder(Id = res.workOrderId, Status = 'Arrived', ArrivalDateTime__c = Datetime.now(), VisitFee__c = 30000);
    ProductItem compressor = [SELECT Id FROM ProductItem WHERE ProductItemNumber = 'PI-0001'];
    insert new ProductConsumed(WorkOrderId = res.workOrderId, ProductItemId = compressor.Id, QuantityConsumed = 1);
    WorkOrder wo = [SELECT WorkOrderNumber, Status, fmTotalCharge__c, fmNeedsApproval__c FROM WorkOrder WHERE Id = :res.workOrderId];
    System.debug(LoggingLevel.WARN, 'B3 승인 시연 출동 ' + wo.WorkOrderNumber + ' ' + wo.Status + ' 총 청구액 ' + wo.fmTotalCharge__c + ' 승인 필요 ' + wo.fmNeedsApproval__c);
  }
}
