// D5 실습: 사용 부품 N건을 insert만 하고, 트리거(ProductConsumedTrigger)가 유·무상 자동 판정을 하는지 확인
// 20건과 200건으로 각각 실행해 insert 구간의 SOQL·DML "횟수"가 같은지 비교 (행 수만 늘어야 정상)
// 생성 방식: ProductItemId 방식 (표준 가격표가 비활성이라 PricebookEntryId 방식 불가). 필수 값 WorkOrderId, QuantityConsumed, ProductItemId
// 정리: d5_cleanup.apex (출동 제목 접두사 [BULK5], 위치 이름 'BULK5 차량')
Integer N = 200;   // 비교용으로 20도 실행

// 0. 준비 ① 벌크 전용 위치 + 부품 12종 재고(각 10,000). 최민호 차량 등 기존 재고는 건드리지 않음
Schema.Location bulkVan = new Schema.Location(
    Name = 'BULK5 차량',
    LocationType = 'Van',
    IsInventoryLocation = true
);
insert bulkVan;

// DESC: 압축기가 섞이도록 분류 순으로 12종 (Compressor 먼저)
List<Product2> products = [
    SELECT Id, Family FROM Product2
    WHERE Family IN ('Compressor', 'General') AND IsActive = true
    ORDER BY Family, Name
    LIMIT 12
];
List<ProductItem> items = new List<ProductItem>();
for (Product2 p : products) {
    items.add(new ProductItem(LocationId = bulkVan.Id, Product2Id = p.Id, QuantityOnHand = 10000));
}
insert items;

// 0. 준비 ② 진행 중 접수 10건에 출동 1건씩 (긴급 사업장 제외, 장비 있는 접수)
List<Case> openCases = [
    SELECT Id, AssetId, AccountId FROM Case
    WHERE Status IN ('New', 'InProgress') AND AssetId != null
      AND CustomerSite__r.UsageType__c NOT IN ('ColdStorage', 'ServerRoom')
      AND (NOT Subject LIKE '[BULK5]%')
    ORDER BY CreatedDate
    LIMIT 10
];
List<WorkOrder> workOrders = new List<WorkOrder>();
for (Integer i = 0; i < openCases.size(); i++) {
    Case c = openCases[i];
    workOrders.add(new WorkOrder(
        CaseId = c.Id,
        AssetId = c.AssetId,
        AccountId = c.AccountId,
        Subject = '[BULK5] 부품 벌크 출동 ' + i,
        Status = 'Assigned'
    ));
}
insert workOrders;
System.debug(LoggingLevel.WARN, '0.준비  부품 ' + items.size() + '종(Compressor ' + [SELECT COUNT() FROM Product2 WHERE Id IN :new Map<Id, Product2>(products).keySet() AND Family = 'Compressor']
    + '), 출동 ' + workOrders.size() + '건  SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows());

// 1. 사용 부품 N건 (출동·부품을 돌아가며, 수량 1) → insert 1회
List<ProductConsumed> parts = new List<ProductConsumed>();
for (Integer i = 0; i < N; i++) {
    parts.add(new ProductConsumed(
        WorkOrderId = workOrders[Math.mod(i, workOrders.size())].Id,
        ProductItemId = items[Math.mod(i, items.size())].Id,
        QuantityConsumed = 1
    ));
}
Integer soqlBefore = Limits.getQueries();
Integer dmlBefore = Limits.getDmlStatements();
Integer rowsBefore = Limits.getDmlRows();
insert parts;
System.debug(LoggingLevel.WARN, '1.insert 구간  SOQL +' + (Limits.getQueries() - soqlBefore)
    + '  DML +' + (Limits.getDmlStatements() - dmlBefore) + '  Rows +' + (Limits.getDmlRows() - rowsBefore)
    + '  (누적 SOQL=' + Limits.getQueries() + ' DML=' + Limits.getDmlStatements() + ' Rows=' + Limits.getDmlRows() + ')');

// 2. 결과 확인: 자동 판정 분포, 판정 만료일 채움 여부, 최종 판정 = 자동 판정 여부
Set<Id> partIds = new Map<Id, ProductConsumed>(parts).keySet();
for (AggregateResult ar : [
    SELECT PartCategoryAtUse__c category, AutoChargeType__c auto, COUNT(Id) cnt
    FROM ProductConsumed WHERE Id IN :partIds
    GROUP BY PartCategoryAtUse__c, AutoChargeType__c
]) {
    System.debug(LoggingLevel.WARN, '2.분포  ' + ar.get('category') + ' / ' + ar.get('auto') + ' = ' + ar.get('cnt'));
}
Integer withEndDate = [SELECT COUNT() FROM ProductConsumed WHERE Id IN :partIds AND WarrantyEndDateAtJudgment__c != null];
Integer notJudged = [SELECT COUNT() FROM ProductConsumed WHERE Id IN :partIds AND (AutoChargeType__c = null OR ChargeType__c = null)];
System.debug(LoggingLevel.WARN, '2.결과  판정 만료일 있음 ' + withEndDate + '/' + N + ', 판정 누락 ' + notJudged + '건');
