// 단가 현실화 — 2026-10-16 (Edwin 승인: 공개 자료 기반 추정 + B2B 상업용 보정, decision-log 참고)
// 대상: 제품 ERP 단가(부품 14 + 장비 모델 8) · 가격표 항목 · 사용 부품 사용 시점 단가(수량 그대로, 트리거 우회 — ERP 재전송 없음) · 방문 출동(도착·승인 대기·완료) 출장비 50,000
// 출장비 기준값 ServiceSetting VisitFee는 메타데이터(50000)로 따로 배포. 재고·ERP 수량은 바꾸지 않음(ERP Mock에는 단가 없음 — 단가 원천 ERP, 초기 이관값을 제품 ERP 단가에 둠)
Boolean APPLY = false;
Decimal VISIT_FEE = 50000;
Map<String, Decimal> priceByCode = new Map<String, Decimal>{
  'RFG-404A' => 60000, 'HG-P-R410A' => 35000, 'HG-P-R32' => 30000,
  'CMP-404-50' => 6500000, 'HG-P-CP500' => 5500000, 'HG-P-CP350' => 4200000, 'HG-P-CP200' => 2800000,
  'HG-P-CB7' => 650000, 'HG-P-FM50' => 480000, 'HG-P-FM30' => 320000, 'HG-P-EV12' => 250000,
  'HG-P-DP4' => 180000, 'HG-P-TS2' => 45000, 'HG-P-FT10' => 35000,
  'HG-CH500' => 85000000, 'HG-M-HAC800' => 45000000, 'HG-CR800' => 38000000, 'HG-M-HAC500' => 32000000,
  'HG-AH300' => 28000000, 'HG-M-HAC300' => 22000000, 'HG-PK100' => 9500000, 'HG-SC050' => 6500000
};
List<Product2> products = [SELECT Id, Name, ErpPartCode__c, ErpUnitPrice__c FROM Product2 WHERE ErpPartCode__c IN :priceByCode.keySet()];
Map<Id, Decimal> priceByProduct = new Map<Id, Decimal>();
for (Product2 p : products) { priceByProduct.put(p.Id, priceByCode.get(p.ErpPartCode__c)); }
List<PricebookEntry> entries = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Product2Id IN :priceByProduct.keySet()];
List<ProductConsumed> parts = [SELECT Id, Product2Id, UnitPriceAtUse__c FROM ProductConsumed WHERE Product2Id IN :priceByProduct.keySet()];
List<WorkOrder> visited = [SELECT Id, VisitFee__c FROM WorkOrder WHERE Status IN ('Arrived', 'PendingApproval', 'Completed')];
Integer partsChanging = 0; for (ProductConsumed pc : parts) { if (pc.UnitPriceAtUse__c != priceByProduct.get(pc.Product2Id)) partsChanging++; }
Integer feeChanging = 0; for (WorkOrder w : visited) { if (w.VisitFee__c != VISIT_FEE) feeChanging++; }
System.debug(LoggingLevel.WARN, 'PRICE 제품 ' + products.size() + '/' + priceByCode.size() + ' · 가격표 항목 ' + entries.size() + ' · 사용 부품 ' + parts.size() + '(바뀔 ' + partsChanging + ') · 방문 출동 ' + visited.size() + '(출장비 바뀔 ' + feeChanging + ') · 전체 사용 부품 ' + [SELECT COUNT() FROM ProductConsumed] + ' · APPLY=' + APPLY);
if (!APPLY) { return; }
for (Product2 p : products) { p.ErpUnitPrice__c = priceByProduct.get(p.Id); }
update products;
for (PricebookEntry e : entries) { e.UnitPrice = priceByProduct.get(e.Product2Id); }
update entries;
for (ProductConsumed pc : parts) { pc.UnitPriceAtUse__c = priceByProduct.get(pc.Product2Id); }
TriggerHandler.bypassedHandlers.add('ProductConsumedTriggerHandler');
update parts;
TriggerHandler.bypassedHandlers.remove('ProductConsumedTriggerHandler');
for (WorkOrder w : visited) { w.VisitFee__c = VISIT_FEE; }
update visited;
System.debug(LoggingLevel.WARN, 'PRICE 저장 제품 ' + products.size() + ' · 가격표 ' + entries.size() + ' · 사용 부품 ' + parts.size() + ' · 출장비 ' + visited.size() + ' · ERP 대기·실패 ' + [SELECT COUNT() FROM ProductConsumed WHERE ErpSyncStatus__c IN ('Pending','Failed','NeedsReview')]);
