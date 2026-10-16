// 한빛물류 출동 이력 데이터(시연용 과거 이력) — 2026-10-16 (Edwin 승인: 방법 A, 생성일 과거)
// 장비 3대(평택 2창고 HG24AH300-0002·HG-HAC500-2403-0015, 서울 본사 HG25AH300-0004)에 [이력] 접수 1건씩 + 완료 출동 6건 + 유상 사용 부품 9건
// 재고·ERP 무영향: 사용 부품은 재고(ProductItem)가 아니라 가격표 항목(PricebookEntry)에 연결 → 표준 재고 차감 없음.
//   사용 부품 트리거는 이 실행에서만 우회 → ERP 전송 없음, ERP 상태 비움 = "연동 전 기존 데이터"(decision-log ERP 13). 유·무상 판정 필드는 직접 채움
// 생성일 과거: 실행 전 "레코드 생성 시 감사 필드 설정"(UserInterfaceSettings.enableAuditFieldsInactiveOwner) + 실행 사용자 CreateAuditFields 권한 필요(끝나면 원래대로)
// 서울 본사 출동 담당 = 관리자(서울 기사 사용자 없음 — Developer Edition 라이선스 한도)
// 가격표: 표준 가격표(비활성)에 먼저 등록해야 하는 규칙 → 표준 + 활성 가격표 "Standard"에 항목 생성, 출동은 "Standard" 가격표
// 제외(실습 중): 접수 00001028, 인천 물류센터 장비 HG23PK100-0003, 최민호 차량 재고
// 평택 2창고는 긴급 용도 → 접수 생성 시 긴급 알림 Flow가 센터장에게 알림·메일을 보낼 수 있음
Boolean APPLY = false;
String TAG = '[이력] ';
Decimal VISIT_FEE = 30000;
String NOTE = '과거 출동 이력(시연 데이터, 2026-10-16 입력). 사용 부품은 가격표 항목 기준(재고·ERP 반영 없음).';

Map<String, Product2> productsByCode = new Map<String, Product2>();
for (Product2 p : [SELECT Id, Name, Family, ErpPartCode__c, ErpUnitPrice__c FROM Product2 WHERE ErpPartCode__c IN ('HG-P-FM50','HG-P-CB7','HG-P-R410A','HG-P-DP4','HG-P-FT10','HG-P-EV12','HG-P-TS2','HG-P-FM30')]) {
  productsByCode.put(p.ErpPartCode__c, p);
}
Map<String, Asset> assetsBySerial = new Map<String, Asset>();
for (Asset a : [SELECT Id, SerialNumber FROM Asset WHERE SerialNumber IN ('HG24AH300-0002','HG-HAC500-2403-0015','HG25AH300-0004')]) {
  assetsBySerial.put(a.SerialNumber, a);
}
Pricebook2 stdBook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
Pricebook2 activeBook = [SELECT Id FROM Pricebook2 WHERE Name = 'Standard' AND IsActive = true AND IsStandard = false LIMIT 1];
Integer existingHistory = [SELECT COUNT() FROM Case WHERE Subject LIKE '[이력]%'];
Decimal whQty = (Decimal) [SELECT SUM(QuantityOnHand) q FROM ProductItem WHERE Location.ErpLocationCode__c = 'WH-GS-001'][0].get('q');
Decimal vanQty = (Decimal) [SELECT SUM(QuantityOnHand) q FROM ProductItem WHERE Location.ErpLocationCode__c = 'VAN-GS-001'][0].get('q');
System.debug(LoggingLevel.WARN, 'HIST 부품 ' + productsByCode.size() + '/8 · 장비 ' + assetsBySerial.size() + '/3 · 기존 [이력] 접수 ' + existingHistory + ' · 재고 합계 창고 ' + whQty + ' 차량 ' + vanQty + ' · APPLY=' + APPLY);
System.debug(LoggingLevel.WARN, 'HIST 만들 것: 가격표 항목 최대 16(표준 8 + Standard 8, 있으면 건너뜀) · 접수 3 · 출동 6 · 사용 부품 9');
if (!APPLY || existingHistory > 0 || productsByCode.size() != 8 || assetsBySerial.size() != 3) {
  return;
}

// 1) 가격표 항목
Map<Id, Id> activeEntryIdByProduct = new Map<Id, Id>();
Set<String> existingKeys = new Set<String>();
for (PricebookEntry e : [SELECT Id, Pricebook2Id, Product2Id FROM PricebookEntry WHERE Product2Id IN :productsByCode.values()]) {
  existingKeys.add(e.Pricebook2Id + '|' + e.Product2Id);
  if (e.Pricebook2Id == activeBook.Id) {
    activeEntryIdByProduct.put(e.Product2Id, e.Id);
  }
}
List<PricebookEntry> stdEntries = new List<PricebookEntry>();
List<PricebookEntry> activeEntries = new List<PricebookEntry>();
for (Product2 p : productsByCode.values()) {
  if (!existingKeys.contains(stdBook.Id + '|' + p.Id)) {
    stdEntries.add(new PricebookEntry(Pricebook2Id = stdBook.Id, Product2Id = p.Id, UnitPrice = p.ErpUnitPrice__c, IsActive = true));
  }
  if (!existingKeys.contains(activeBook.Id + '|' + p.Id)) {
    activeEntries.add(new PricebookEntry(Pricebook2Id = activeBook.Id, Product2Id = p.Id, UnitPrice = p.ErpUnitPrice__c, IsActive = true));
  }
}
insert stdEntries;
insert activeEntries;
for (PricebookEntry e : activeEntries) {
  activeEntryIdByProduct.put(e.Product2Id, e.Id);
}
System.debug(LoggingLevel.WARN, 'HIST 가격표 항목 표준 ' + stdEntries.size() + ' · Standard ' + activeEntries.size());

// 2) 접수 3건(처리 중으로 만들고 끝에 종결). 생성일 = 첫 출동일 오전
Id techId = [SELECT Id FROM User WHERE Username = 'minho.choi@hangyeol-as.dev'].Id;
Id adminId = UserInfo.getUserId();
Database.DMLOptions dmo = new Database.DMLOptions();
dmo.assignmentRuleHeader.useDefaultRule = true;
Map<String, Datetime> createdBySerial = new Map<String, Datetime>{
  'HG24AH300-0002' => Datetime.newInstance(2026, 7, 8, 9, 10, 0),
  'HG-HAC500-2403-0015' => Datetime.newInstance(2026, 5, 12, 9, 0, 0),
  'HG25AH300-0004' => Datetime.newInstance(2026, 4, 14, 9, 0, 0)
};
List<String> serials = new List<String>{ 'HG24AH300-0002', 'HG-HAC500-2403-0015', 'HG25AH300-0004' };
Map<String, Case> casesBySerial = new Map<String, Case>{
  'HG24AH300-0002' => new Case(Subject = TAG + '송풍 불량·소음 · 평택 2창고', SymptomType__c = 'Noise'),
  'HG-HAC500-2403-0015' => new Case(Subject = TAG + '냉방 약함·배수 불량 · 평택 2창고', SymptomType__c = 'Leak'),
  'HG25AH300-0004' => new Case(Subject = TAG + '냉방 불량 반복 · 서울 본사', SymptomType__c = 'NoCooling')
};
for (String serial : serials) {
  Case c = casesBySerial.get(serial);
  c.AssetId = assetsBySerial.get(serial).Id;
  c.Origin = 'Phone';
  c.Status = 'InProgress';
  c.Description = NOTE;
  c.setOptions(dmo);
  // DESC: 생성일은 put으로(감사 필드 권한이 없을 때도 미리 보기가 컴파일되도록)
  c.put('CreatedDate', createdBySerial.get(serial));
}
insert casesBySerial.values();

// 3) 출동 6건(완료). {시리얼, 월, 일, 담당, 승인됨 여부}
List<Object[]> plan = new List<Object[]>{
  new Object[]{ 'HG24AH300-0002', 7, 8, techId, false },
  new Object[]{ 'HG24AH300-0002', 8, 19, techId, true },
  new Object[]{ 'HG-HAC500-2403-0015', 5, 12, techId, false },
  new Object[]{ 'HG25AH300-0004', 4, 14, adminId, false },
  new Object[]{ 'HG25AH300-0004', 6, 23, adminId, false },
  new Object[]{ 'HG25AH300-0004', 9, 2, adminId, false }
};
List<WorkOrder> workOrders = new List<WorkOrder>();
Map<String, Integer> visitBySerial = new Map<String, Integer>();
for (Object[] row : plan) {
  String serial = (String) row[0];
  Integer m = (Integer) row[1];
  Integer day = (Integer) row[2];
  Integer visit = (visitBySerial.containsKey(serial) ? visitBySerial.get(serial) : 0) + 1;
  visitBySerial.put(serial, visit);
  Case c = casesBySerial.get(serial);
  Boolean seoul = serial == 'HG25AH300-0004';
  WorkOrder wo = new WorkOrder(
    CaseId = c.Id,
    AssetId = c.AssetId,
    Subject = c.Subject + (visit > 1 ? ' (재방문 ' + visit + '회차)' : ''),
    OwnerId = (Id) row[3],
    Status = 'Completed',
    Purpose__c = 'Repair',
    VisitNumber__c = visit,
    VisitFee__c = VISIT_FEE,
    Pricebook2Id = activeBook.Id,
    StartDate = Datetime.newInstance(2026, m, day, 13, 0, 0),
    ArrivalDateTime__c = Datetime.newInstance(2026, m, day, 13, 30, 0),
    CompletedDateTime__c = Datetime.newInstance(2026, m, day, 16, 0, 0),
    Description = NOTE + (seoul ? ' 담당 = 관리자(서울 기사 사용자 없음, 라이선스 한도).' : '')
  );
  wo.put('CreatedDate', Datetime.newInstance(2026, m, day, 10, 0, 0));
  if ((Boolean) row[4]) {
    wo.ApprovalStatus__c = 'Approved';
  }
  workOrders.add(wo);
}
insert workOrders;

// 4) 사용 부품 9건(유상, 가격표 항목) — 사용 부품 트리거 우회(ERP 전송·재고 검사·판정 없음)
// {출동 순번, 부품 코드, 수량}
List<Object[]> parts = new List<Object[]>{
  new Object[]{ 0, 'HG-P-FM50', 1 },
  new Object[]{ 1, 'HG-P-CB7', 1 },
  new Object[]{ 1, 'HG-P-R410A', 3 },
  new Object[]{ 2, 'HG-P-DP4', 1 },
  new Object[]{ 2, 'HG-P-FT10', 2 },
  new Object[]{ 3, 'HG-P-R410A', 4 },
  new Object[]{ 4, 'HG-P-EV12', 1 },
  new Object[]{ 4, 'HG-P-TS2', 1 },
  new Object[]{ 5, 'HG-P-FM30', 1 }
};
List<ProductConsumed> consumed = new List<ProductConsumed>();
for (Object[] row : parts) {
  WorkOrder wo = workOrders[(Integer) row[0]];
  Product2 p = productsByCode.get((String) row[1]);
  ProductConsumed pc = new ProductConsumed(
    WorkOrderId = wo.Id,
    PricebookEntryId = activeEntryIdByProduct.get(p.Id),
    QuantityConsumed = (Integer) row[2],
    AutoChargeType__c = 'Paid',
    ChargeType__c = 'Paid',
    UnitPriceAtUse__c = p.ErpUnitPrice__c,
    PartCategoryAtUse__c = p.Family
  );
  pc.put('CreatedDate', wo.ArrivalDateTime__c.addHours(1));
  consumed.add(pc);
}
TriggerHandler.bypassedHandlers.add('ProductConsumedTriggerHandler');
insert consumed;
// WARN: ERP 상태 선택 목록 기본값(Pending)이 들어감 → 그대로 두면 매시 재전송(10분 넘은 Pending)이 ERP로 보냄. 반드시 비움(2026-10-16 실행 때 발견, 바로 비움)
for (ProductConsumed pc : consumed) {
  pc.ErpSyncStatus__c = null;
}
update consumed;
TriggerHandler.bypassedHandlers.remove('ProductConsumedTriggerHandler');

// 5) 접수 종결
for (Case c : casesBySerial.values()) {
  c.Status = 'Closed';
}
update casesBySerial.values();

Decimal whAfter = (Decimal) [SELECT SUM(QuantityOnHand) q FROM ProductItem WHERE Location.ErpLocationCode__c = 'WH-GS-001'][0].get('q');
Decimal vanAfter = (Decimal) [SELECT SUM(QuantityOnHand) q FROM ProductItem WHERE Location.ErpLocationCode__c = 'VAN-GS-001'][0].get('q');
System.debug(LoggingLevel.WARN, 'HIST 생성 접수 ' + casesBySerial.size() + ' · 출동 ' + workOrders.size() + ' · 사용 부품 ' + consumed.size() + ' · ERP 상태 있는 부품 ' + [SELECT COUNT() FROM ProductConsumed WHERE Id IN :consumed AND ErpSyncStatus__c != null]);
System.debug(LoggingLevel.WARN, 'HIST 재고 합계 창고 ' + whQty + ' → ' + whAfter + ' · 차량 ' + vanQty + ' → ' + vanAfter);
