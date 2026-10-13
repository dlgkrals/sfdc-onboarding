// D7 ERP 4번: Salesforce 현재 재고(창고·기사 차량)를 ERP(Mock)에 한 번 적재 — 처음부터 수량이 다르면 전부 불일치가 되므로
// - 대상: ERP 위치 코드가 있는 재고 위치 + 그 위치의 제품 항목(ERP 부품 코드가 있는 것)
// - reset = true: ERP의 재고·이력·처리 기록을 비우고 다시 채움 (시연 전 초기화에도 사용)
// - 호출: Named Credential HG_ErpMock (키는 External Credential, 이 스크립트·로그에 없음)
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
for (ProductItem p : [SELECT Location.ErpLocationCode__c, Product2.ErpPartCode__c, QuantityOnHand FROM ProductItem WHERE LocationId IN :locationIds AND Product2.ErpPartCode__c != null]) {
    stock.add(new Map<String, Object>{ 'locationCode' => p.Location.ErpLocationCode__c, 'partCode' => p.Product2.ErpPartCode__c, 'quantity' => p.QuantityOnHand });
}

HttpRequest req = new HttpRequest();
req.setEndpoint('callout:HG_ErpMock/api/admin/seed');
req.setMethod('POST');
req.setTimeout(60000);
req.setHeader('Content-Type', 'application/json; charset=utf-8');
req.setBody(JSON.serialize(new Map<String, Object>{ 'reset' => true, 'locations' => locations, 'stock' => stock }));
HttpResponse res = new Http().send(req);
System.debug(LoggingLevel.WARN, 'SEED 보냄 위치 ' + locations.size() + '곳, 재고 ' + stock.size() + '건 → ERP 응답 HTTP ' + res.getStatusCode() + ' ' + res.getBody().left(200));
