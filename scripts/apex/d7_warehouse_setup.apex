// D7 ERP 4번: 경기남부 창고·창고 재고 생성 + 기존 차량 재고 수량 단위 채우기 (여러 번 실행해도 중복 생성 안 함)
// - 창고 Location: WH-GS-001 경기남부 창고 (Warehouse, 서비스센터 경기남부, 소유자 = 실행한 관리자)
// - 창고 재고: 부품(압축기·일반) 14종. 시작 수량 압축기 5개(CMP-404-50만 10개), 일반 20개, 냉매(kg) 50kg
// - 단위(QuantityUnitOfMeasure)는 부품의 단위와 같게 (다르면 재고 이동 생성이 거부됨 — 0번 확인)
String WH_CODE = 'WH-GS-001';

// 1) 기존 재고 중 단위가 빈 것 채우기 (차량 재고 2건)
List<ProductItem> noUnit = [SELECT Id, Product2.QuantityUnitOfMeasure FROM ProductItem WHERE QuantityUnitOfMeasure = null];
for (ProductItem item : noUnit) {
    item.QuantityUnitOfMeasure = item.Product2.QuantityUnitOfMeasure;
}
update noUnit;
System.debug(LoggingLevel.WARN, 'SETUP 단위 채움 ' + noUnit.size() + '건');

// 2) 창고 위치
List<Schema.Location> existing = [SELECT Id FROM Location WHERE ErpLocationCode__c = :WH_CODE];
Schema.Location wh;
if (existing.isEmpty()) {
    wh = new Schema.Location(
        Name = '경기남부 창고',
        LocationType = 'Warehouse',
        IsInventoryLocation = true,
        ErpLocationCode__c = WH_CODE,
        ServiceCenter__c = 'GyeonggiSouth'
    );
    insert wh;
    System.debug(LoggingLevel.WARN, 'SETUP 창고 생성 ' + wh.Id);
} else {
    wh = existing[0];
    System.debug(LoggingLevel.WARN, 'SETUP 창고 이미 있음 ' + wh.Id);
}

// 3) 창고 재고 (없는 부품만)
Set<Id> stocked = new Set<Id>();
for (ProductItem item : [SELECT Product2Id FROM ProductItem WHERE LocationId = :wh.Id]) {
    stocked.add(item.Product2Id);
}
List<ProductItem> toInsert = new List<ProductItem>();
for (Product2 part : [SELECT Id, ErpPartCode__c, Family, QuantityUnitOfMeasure FROM Product2 WHERE Family IN ('Compressor', 'General') AND ErpPartCode__c != null]) {
    if (stocked.contains(part.Id)) {
        continue;
    }
    Decimal quantity = part.Family == 'Compressor' ? (part.ErpPartCode__c == 'CMP-404-50' ? 10 : 5) : (part.QuantityUnitOfMeasure == 'kg' ? 50 : 20);
    toInsert.add(new ProductItem(
        LocationId = wh.Id,
        Product2Id = part.Id,
        QuantityOnHand = quantity,
        QuantityUnitOfMeasure = part.QuantityUnitOfMeasure,
        ErpStockKey__c = WH_CODE + '|' + part.ErpPartCode__c
    ));
}
insert toInsert;
System.debug(LoggingLevel.WARN, 'SETUP 창고 재고 생성 ' + toInsert.size() + '건, 기존 ' + stocked.size() + '건');
