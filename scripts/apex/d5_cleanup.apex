// D5 실습 정리: 테스트 사용 부품 → 출동 → 접수 순으로 삭제, BULK5 차량 위치와 제품 항목 삭제
// 장비 누적 접수 수는 접수 삭제 시 CaseTrigger(after delete)가 자동으로 재계산하는지 확인
// WARN: Description은 긴 텍스트 영역이라 SOQL 조건에 쓸 수 없어 Subject 접두어로 찾음
String MARK = '[BULK5]%';
String LOCATION_NAME = 'BULK5 차량';

// 1. 사용 부품 (BULK5 출동에 달린 것)
List<ProductConsumed> parts = [SELECT Id FROM ProductConsumed WHERE WorkOrder.Subject LIKE :MARK];
delete parts;

// 2. 출동
List<WorkOrder> workOrders = [SELECT Id FROM WorkOrder WHERE Subject LIKE :MARK];
delete workOrders;

// 3. 접수 (after delete 트리거가 장비 재계산)
List<Case> cases = [SELECT Id, AssetId FROM Case WHERE Subject LIKE :MARK];
Set<Id> assetIds = new Set<Id>();
for (Case c : cases) {
    assetIds.add(c.AssetId);
}
delete cases;

// 4. 벌크 전용 재고 위치와 제품 항목
List<ProductItem> items = [SELECT Id FROM ProductItem WHERE Location.Name = :LOCATION_NAME];
delete items;
List<Schema.Location> locations = [SELECT Id FROM Location WHERE Name = :LOCATION_NAME];
delete locations;

System.debug(LoggingLevel.WARN, '삭제  사용 부품 ' + parts.size() + ', 출동 ' + workOrders.size() + ', 접수 ' + cases.size()
    + ', 제품 항목 ' + items.size() + ', 위치 ' + locations.size());

// 5. 남은 건수 확인 (모두 0이어야 함)
Integer leftCases = [SELECT COUNT() FROM Case WHERE Subject LIKE :MARK];
Integer leftWorkOrders = [SELECT COUNT() FROM WorkOrder WHERE Subject LIKE :MARK];
Integer leftItems = [SELECT COUNT() FROM ProductItem WHERE Location.Name = :LOCATION_NAME];
Integer leftLocations = [SELECT COUNT() FROM Location WHERE Name = :LOCATION_NAME];
System.debug(LoggingLevel.WARN, '남은 건수  접수 ' + leftCases + ', 출동 ' + leftWorkOrders + ', 제품 항목 ' + leftItems + ', 위치 ' + leftLocations);

// 6. 재계산 확인: 삭제한 접수의 장비 중 TotalCaseCount__c가 실제 접수 수와 다른 장비 수
if (!assetIds.isEmpty()) {
    Map<Id, Integer> actualByAsset = new Map<Id, Integer>();
    for (AggregateResult ar : [SELECT AssetId assetId, COUNT(Id) cnt FROM Case WHERE AssetId IN :assetIds AND Status != 'Canceled' GROUP BY AssetId]) {
        actualByAsset.put((Id) ar.get('assetId'), (Integer) ar.get('cnt'));
    }
    Integer mismatch = 0;
    for (Asset a : [SELECT Id, TotalCaseCount__c FROM Asset WHERE Id IN :assetIds]) {
        Integer actual = actualByAsset.containsKey(a.Id) ? actualByAsset.get(a.Id) : 0;
        if (a.TotalCaseCount__c != actual) {
            mismatch++;
        }
    }
    System.debug(LoggingLevel.WARN, '재계산 확인  장비 ' + assetIds.size() + '대 중 불일치 ' + mismatch + '대');
}
