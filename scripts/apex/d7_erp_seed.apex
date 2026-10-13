// D7 ERP 4번: Salesforce 현재 재고(창고·기사 차량)를 ERP(Mock)에 한 번 적재 — 처음부터 수량이 다르면 전부 불일치가 되므로
// - 대상: ERP 위치 코드가 있는 재고 위치 + 그 위치의 재고(ERP 부품 코드가 있는 것)
// - reset = true: ERP의 재고·이력·처리 기록을 비우고 다시 채움 (시연 전 초기화에도 사용)
// - 호출: Named Credential HG_ErpMock (키는 External Credential, 이 스크립트·로그에 없음)
// WARN: 재적재하면 ERP의 중복 방지 기록이 사라짐 + Salesforce 재고(이미 차감된 값)가 그대로 ERP 값이 됨
//       → 아직 ERP에 안 간 대기·실패 건이 있으면 나중에 재전송될 때 ERP에서 한 번 더 빠짐 (2026-10-13 PC-245 이중 차감)
//       확인과 재적재를 따로 하면 그 사이에 저장된 건을 놓치므로, 같은 실행 안에서 확인하고 있으면 멈춤
Integer unsentParts = [SELECT COUNT() FROM ProductConsumed WHERE ErpSyncStatus__c IN ('Pending', 'Failed')];
Integer unsentTransfers = [SELECT COUNT() FROM ProductTransfer WHERE ErpSyncStatus__c IN ('Pending', 'Failed')];
if (unsentParts + unsentTransfers > 0) {
    throw new IllegalArgumentException('SEED 중단: ERP에 아직 안 간 대기·실패 건이 있습니다 (사용 부품 ' + unsentParts
        + ', 재고 이동 ' + unsentTransfers + '). 재전송(d7_erp_retry_run.apex)으로 먼저 보내거나 정리한 뒤 다시 실행하세요.');
}
Map<String, String> erpTypeByLocationType = new Map<String, String>{ 'Warehouse' => 'WAREHOUSE', 'Van' => 'VAN' };

List<Map<String, Object>> locations = new List<Map<String, Object>>();
Set<Id> locationIds = new Set<Id>();
for (Schema.Location l : [SELECT Id, Name, LocationType, ErpLocationCode__c FROM Location WHERE ErpLocationCode__c != null AND IsInventoryLocation = true]) {
    if (!erpTypeByLocationType.containsKey(l.LocationType)) {
        continue;
    }
    locationIds.add(l.Id);
    locations.add(new Map<String, Object>{ 'code' => l.ErpLocationCode__c, 'name' => l.Name, 'type' => erpTypeByLocationType.get(l.LocationType) });
}
List<Map<String, Object>> stock = new List<Map<String, Object>>();
// DESC: 수량 단위는 재고의 단위 그대로 (Each, kg). 비어 있으면 부품 단위
for (ProductItem p : [SELECT Location.ErpLocationCode__c, Product2.ErpPartCode__c, Product2.QuantityUnitOfMeasure, QuantityOnHand, QuantityUnitOfMeasure FROM ProductItem WHERE LocationId IN :locationIds AND Product2.ErpPartCode__c != null]) {
    String unit = String.isNotBlank(p.QuantityUnitOfMeasure) ? p.QuantityUnitOfMeasure : p.Product2.QuantityUnitOfMeasure;
    stock.add(new Map<String, Object>{ 'locationCode' => p.Location.ErpLocationCode__c, 'partCode' => p.Product2.ErpPartCode__c, 'quantity' => p.QuantityOnHand, 'unit' => unit });
}

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:HG_ErpMock/api/admin/seed');
req.setMethod('POST');
req.setTimeout(60000);
req.setHeader('Content-Type', 'application/json; charset=utf-8');
req.setBody(JSON.serialize(new Map<String, Object>{ 'reset' => true, 'locations' => locations, 'stock' => stock }));
HttpResponse res = new Http().send(req);
System.debug(LoggingLevel.WARN, 'SEED 보냄 위치 ' + locations.size() + '곳, 재고 ' + stock.size() + '건 → ERP 응답 HTTP ' + res.getStatusCode() + ' ' + res.getBody().left(200));
