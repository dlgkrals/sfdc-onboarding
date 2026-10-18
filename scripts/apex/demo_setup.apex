// 발표 시연 데이터 준비 — 2026-10-18 (Edwin 요청: 시나리오 1~10 각 2벌, 이름 "[시연/시나리오명]")
// APPLY = false: 만들 대상·이미 있는 대상·차량 보충 수량만 출력 / true: 저장. 같은 제목이 이미 있으면 그 벌은 건너뜀(다시 실행해도 안전)
// 1) 최민호 차량 보충: 경기남부 창고 → 차량 재고 이동(수령) → IF-06으로 ERP도 같은 이동
// 2) 기존 [시연] 3건 이름 맞추기: 00001974 → 기사 배정 1벌, 00001975(출동 00000042) → 유상 50만 초과 1벌, 00001976 → 중복 접수 1벌
// 3) 나머지 접수 생성(할당 규칙 → 경기남부·인천센터 접수 Queue) + [기사 배정](DispatchService, 최민호)으로 출동 + 시나리오별 상태
// 4) 유상 50만 초과 2벌: 압축기 50HP 1대 사용(IF-03) — 1벌(00000042)과 같은 시작 상태
//    WARN: 차량 보충과 같은 실행에서 넣으면 ERP 전송 순서가 뒤바뀌어 "재고 부족"(2026-10-18 PC-269) → 보충한 실행에서는 건너뛰고, 한 번 더 실행하면 넣음
// 끝나면 docs/demo_checklist.md 기준 시각·재고 기준값을 demo_reset.apex에 반영
Boolean APPLY = false;
String TECH_USERNAME = 'minho.choi@hangyeol-as.dev';
String VAN = 'VAN-GS-001';
String WAREHOUSE = 'WH-GS-001';

// DESC: 차량 보충 (ERP 부품 코드 → 보낼 수량)
Map<String, Decimal> refillByPart = new Map<String, Decimal>{
  'CMP-404-50' => 4, // 압축기 50HP: 유상 50만 초과 2벌 1대 + 연습 여유
  'HG-P-FM30' => 6, // 팬모터 FM-30: 보증 내 무상
  'HG-P-EV12' => 6, // 팽창밸브 EV-12: 유상 50만 이하
  'HG-P-CB7' => 6, // 제어보드 CB-7: 예외 무상·승인 반려
  'HG-P-DP4' => 1, // 배수펌프 DP-4: 재고 부족 1벌(차량 1개, 2개 사용 시도)
  'HG-P-FT10' => 1 // 필터 FT-10: 재고 부족 2벌(차량 1개, 2개 사용 시도)
};

// DESC: 시나리오 정의 — 시나리오명, 벌, 장비 시리얼, 증상, 접수 상태 목표, 출동 상태(null = 출동 없음), 기존 접수 번호(이름 맞추기)
List<List<String>> specs = new List<List<String>>{
  new List<String>{ '기사 배정', '1', 'HG-HAC500-2309-0025', 'NoCooling', 'New', null, '00001974' },
  new List<String>{ '기사 배정', '2', 'HG-HAC300-2201-0018', 'Leak', 'New', null, null },
  new List<String>{ '보증 내 무상', '1', 'HG-HAC300-2202-0047', 'Noise', 'InProgress', 'Arrived', null },
  new List<String>{ '보증 내 무상', '2', 'HG-HAC300-2409-0010', 'Noise', 'InProgress', 'Arrived', null },
  new List<String>{ '유상 50만 이하', '1', 'HG-HAC300-2401-0051', 'NoCooling', 'InProgress', 'Arrived', null },
  new List<String>{ '유상 50만 이하', '2', 'HG-HAC300-2503-0052', 'NoCooling', 'InProgress', 'Arrived', null },
  new List<String>{ '유상 50만 초과', '1', 'HG-HAC500-2206-0053', 'NoCooling', 'InProgress', 'Arrived', '00001975' },
  new List<String>{ '유상 50만 초과', '2', 'HG-HAC500-2301-0020', 'NoCooling', 'InProgress', 'Arrived', null },
  new List<String>{ '예외 무상', '1', 'HG-HAC300-2508-0064', 'ErrorCode', 'InProgress', 'Arrived', null },
  new List<String>{ '예외 무상', '2', 'HG-HAC300-2601-0044', 'ErrorCode', 'InProgress', 'Arrived', null },
  new List<String>{ '승인 반려', '1', 'HG-HAC500-2604-0055', 'ErrorCode', 'InProgress', 'Arrived', null },
  new List<String>{ '승인 반려', '2', 'HG-HAC500-2611-0065', 'ErrorCode', 'InProgress', 'Arrived', null },
  new List<String>{ '기사 거절', '1', 'HG-HAC300-2203-0030', 'Noise', 'InProgress', 'Assigned', null },
  new List<String>{ '기사 거절', '2', 'HG-HAC300-2412-0057', 'Noise', 'InProgress', 'Assigned', null },
  new List<String>{ '재고 부족', '1', 'HG-HAC800-2407-0034', 'Leak', 'InProgress', 'Arrived', null },
  new List<String>{ '재고 부족', '2', 'HG-HAC800-2504-0062', 'Leak', 'InProgress', 'Arrived', null },
  new List<String>{ '중복 접수', '1', 'HG25CH500-0001', 'Noise', 'InProgress', null, '00001976' },
  new List<String>{ '중복 접수', '2', 'HG-HAC800-2212-0042', 'Noise', 'InProgress', null, null },
  new List<String>{ '종결 대기', '1', 'HG-HAC800-2502-0026', 'NoCooling', 'Completed', 'Completed', null },
  new List<String>{ '종결 대기', '2', 'HG-HAC300-2607-0060', 'NoCooling', 'Completed', 'Completed', null }
};
Map<String, String> symptomLabels = new Map<String, String>{ 'NoCooling' => '냉방 불가', 'Noise' => '소음', 'Leak' => '누수', 'ErrorCode' => '에러코드' };
Map<String, String> purposeByScenario = new Map<String, String>{ '기사 거절' => 'Diagnosis', '종결 대기' => 'Repair' };

Set<String> serials = new Set<String>();
Set<String> renameNumbers = new Set<String>();
for (List<String> s : specs) {
  serials.add(s[2]);
  if (s[6] != null) {
    renameNumbers.add(s[6]);
  }
}
Map<String, Asset> assetsBySerial = new Map<String, Asset>();
for (Asset a : [SELECT Id, SerialNumber, CustomerSite__r.Name, fmWarrantyStatus__c FROM Asset WHERE SerialNumber IN :serials]) {
  assetsBySerial.put(a.SerialNumber, a);
}
Map<String, Case> renameCasesByNumber = new Map<String, Case>();
for (Case c : [SELECT Id, CaseNumber, Subject, (SELECT Id FROM WorkOrders) FROM Case WHERE CaseNumber IN :renameNumbers]) {
  renameCasesByNumber.put(c.CaseNumber, c);
}
Set<String> existing = new Set<String>();
for (Case c : [SELECT Subject FROM Case WHERE Subject LIKE '[시연/%']) {
  existing.add(c.Subject);
}

// DESC: 제목 = [시연/시나리오] 증상 · 사업장 (벌)
List<String> subjects = new List<String>();
List<String> toCreate = new List<String>();
List<String> toRename = new List<String>();
for (List<String> s : specs) {
  Asset a = assetsBySerial.get(s[2]);
  if (a == null) {
    throw new IllegalArgumentException('장비 없음: ' + s[2]);
  }
  String subject = '[시연/' + s[0] + '] ' + symptomLabels.get(s[3]) + ' · ' + a.CustomerSite__r.Name + ' (' + s[1] + ')';
  subjects.add(subject);
  if (existing.contains(subject)) {
    continue;
  }
  if (s[6] != null) {
    toRename.add(s[6] + ' → ' + subject);
  } else {
    toCreate.add(subject + ' [' + a.fmWarrantyStatus__c + ', 출동 ' + s[5] + ']');
  }
}

User tech = [SELECT Id FROM User WHERE Username = :TECH_USERNAME];
Map<String, ProductItem> warehouseByPart = new Map<String, ProductItem>();
for (ProductItem p : [SELECT Id, Product2Id, Product2.ErpPartCode__c, QuantityOnHand, QuantityUnitOfMeasure FROM ProductItem WHERE Location.ErpLocationCode__c = :WAREHOUSE AND Product2.ErpPartCode__c IN :refillByPart.keySet()]) {
  warehouseByPart.put(p.Product2.ErpPartCode__c, p);
}
Schema.Location vanLoc = [SELECT Id FROM Location WHERE ErpLocationCode__c = :VAN];
Map<String, Decimal> vanQtyByPart = new Map<String, Decimal>();
for (ProductItem p : [SELECT Product2.ErpPartCode__c, QuantityOnHand FROM ProductItem WHERE LocationId = :vanLoc.Id]) {
  vanQtyByPart.put(p.Product2.ErpPartCode__c, p.QuantityOnHand);
}
Boolean refillDone = vanQtyByPart.containsKey('HG-P-FM30');

System.debug(LoggingLevel.WARN, 'SETUP APPLY=' + APPLY + ' · 이름 맞추기 ' + toRename.size() + ' · 새로 만들 접수 ' + toCreate.size() + ' · 차량 보충 ' + (refillDone ? '이미 함' : refillByPart.size() + '종'));
for (String s : toRename) {
  System.debug(LoggingLevel.WARN, '  이름 ' + s);
}
for (String s : toCreate) {
  System.debug(LoggingLevel.WARN, '  생성 ' + s);
}
for (String code : refillByPart.keySet()) {
  ProductItem w = warehouseByPart.get(code);
  System.debug(LoggingLevel.WARN, '  보충 ' + code + ' ' + refillByPart.get(code) + ' (창고 ' + (w == null ? null : w.QuantityOnHand) + ' → 차량 지금 ' + vanQtyByPart.get(code) + ')');
}
if (!APPLY) {
  return;
}

// 1) 차량 보충: 이동 생성 → 수령 (수령 시 트리거가 IF-06 전송 예약)
if (!refillDone) {
  List<ProductTransfer> transfers = new List<ProductTransfer>();
  for (String code : refillByPart.keySet()) {
    ProductItem w = warehouseByPart.get(code);
    transfers.add(new ProductTransfer(SourceProductItemId = w.Id, Product2Id = w.Product2Id, DestinationLocationId = vanLoc.Id, QuantitySent = refillByPart.get(code), QuantityUnitOfMeasure = w.QuantityUnitOfMeasure, Description = '[시연] 발표 연습용 차량 보충', OwnerId = tech.Id));
  }
  insert transfers;
  for (ProductTransfer t : transfers) {
    t.IsReceived = true;
    t.QuantityReceived = t.QuantitySent;
  }
  update transfers;
  // DESC: 수령으로 새로 생긴 차량 재고는 실행 사용자(관리자) 소유 → 재고가 비공개라 기사에게 안 보이고 [부품 추가]에도 없음(2026-10-18 연습 중 발견)
  //       차량 재고 소유자 = 차량 위치 소유자(기사)
  List<ProductItem> vanItems = new List<ProductItem>();
  for (ProductItem p : [SELECT Id, OwnerId, Location.OwnerId FROM ProductItem WHERE LocationId = :vanLoc.Id]) {
    if (p.OwnerId != p.Location.OwnerId) {
      vanItems.add(new ProductItem(Id = p.Id, OwnerId = p.Location.OwnerId));
    }
  }
  update vanItems;
  System.debug(LoggingLevel.WARN, 'SETUP 차량 보충 이동 ' + transfers.size() + '건 수령 · 차량 재고 소유자 맞춤 ' + vanItems.size());
}

// 2) 이름 맞추기 (기존 출동 제목도 같이)
List<Case> renamed = new List<Case>();
List<WorkOrder> renamedWos = new List<WorkOrder>();
for (Integer i = 0; i < specs.size(); i++) {
  List<String> s = specs[i];
  if (s[6] == null || existing.contains(subjects[i])) {
    continue;
  }
  Case c = renameCasesByNumber.get(s[6]);
  renamed.add(new Case(Id = c.Id, Subject = subjects[i]));
  for (WorkOrder wo : c.WorkOrders) {
    renamedWos.add(new WorkOrder(Id = wo.Id, Subject = subjects[i]));
  }
}
update renamed;
update renamedWos;

// 3) 접수 생성 (할당 규칙)
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.assignmentRuleHeader.useDefaultRule = true;
List<Case> cases = new List<Case>();
List<List<String>> createdSpecs = new List<List<String>>();
for (Integer i = 0; i < specs.size(); i++) {
  List<String> s = specs[i];
  if (s[6] != null || existing.contains(subjects[i])) {
    continue;
  }
  Case c = new Case(AssetId = assetsBySerial.get(s[2]).Id, Subject = subjects[i], SymptomType__c = s[3], Origin = 'Phone', Status = s[4] == 'InProgress' && s[5] == null ? 'InProgress' : 'New', Description = '발표 시연용 [' + s[0] + '] ' + s[1] + '벌. 시작 위치는 docs/demo_checklist.md');
  c.setOptions(dmo);
  cases.add(c);
  createdSpecs.add(s);
}
insert cases;

// 4) [기사 배정]으로 출동 (최민호)
List<DispatchService.DispatchRequest> reqs = new List<DispatchService.DispatchRequest>();
List<List<String>> dispatchSpecs = new List<List<String>>();
for (Integer i = 0; i < cases.size(); i++) {
  List<String> s = createdSpecs[i];
  if (s[5] == null) {
    continue;
  }
  DispatchService.DispatchRequest req = new DispatchService.DispatchRequest();
  req.action = DispatchService.ACTION_DISPATCH;
  req.caseId = cases[i].Id;
  req.technicianId = tech.Id;
  req.purpose = purposeByScenario.containsKey(s[0]) ? purposeByScenario.get(s[0]) : 'PartReplacement';
  req.plannedStart = Datetime.now();
  req.instruction = '[시연/' + s[0] + '] ' + s[1] + '벌';
  reqs.add(req);
  dispatchSpecs.add(s);
}
List<DispatchService.DispatchResult> results = reqs.isEmpty() ? new List<DispatchService.DispatchResult>() : DispatchService.run(reqs);
List<WorkOrder> woUpdates = new List<WorkOrder>();
for (Integer i = 0; i < results.size(); i++) {
  DispatchService.DispatchResult r = results[i];
  List<String> s = dispatchSpecs[i];
  if (!r.success) {
    throw new IllegalArgumentException('배정 실패 ' + s[0] + ' ' + s[1] + ': ' + r.message);
  }
  if (s[5] == 'Arrived') {
    woUpdates.add(new WorkOrder(Id = r.workOrderId, Status = 'Arrived', ArrivalDateTime__c = Datetime.now()));
  } else if (s[5] == 'Completed') {
    woUpdates.add(new WorkOrder(Id = r.workOrderId, Status = 'Completed', ArrivalDateTime__c = Datetime.now().addHours(-1), CompletedDateTime__c = Datetime.now(), CompletionResult__c = 'Repaired'));
  }
}
update woUpdates;

// 5) 유상 50만 초과 2벌: 압축기 50HP 1대 (1벌 00000042와 같은 시작 상태)
List<WorkOrder> overLimitWos = [SELECT Id FROM WorkOrder WHERE Subject LIKE '[시연/유상 50만 초과]%(2)' AND Id NOT IN (SELECT WorkOrderId FROM ProductConsumed)];
if (refillDone && !overLimitWos.isEmpty()) {
  Id overLimitWoId = overLimitWos[0].Id;
  ProductItem compressor = [SELECT Id FROM ProductItem WHERE LocationId = :vanLoc.Id AND Product2.ErpPartCode__c = 'CMP-404-50'];
  insert new ProductConsumed(WorkOrderId = overLimitWoId, ProductItemId = compressor.Id, QuantityConsumed = 1);
}
if (!refillDone) {
  System.debug(LoggingLevel.WARN, 'SETUP 압축기 사용은 다음 실행에서 (ERP 차량 보충이 먼저 끝나야 함)');
}
System.debug(LoggingLevel.WARN, 'SETUP 완료 · 이름 ' + renamed.size() + '/' + renamedWos.size() + ' · 접수 ' + cases.size() + ' · 출동 ' + results.size() + ' · 기준 시각(UTC) ' + Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
