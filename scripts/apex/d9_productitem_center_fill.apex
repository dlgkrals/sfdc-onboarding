// 재고 서비스센터·창고 재고 채우기 — 2026-10-16 (재고 공유 규칙 조건 기준 전환)
// 빈 update → 저장 전 Flow ProductItem_BeforeSave_FillFromLocation이 위치에서 채움
// 기본 대상 = 창고 재고(위치 유형 Warehouse). 차량 재고는 EXCLUDE_VAN = false로 따로(2026-10-16 최민호 실습 중이라 제외)
Boolean APPLY = false;
Boolean EXCLUDE_VAN = true;
List<ProductItem> targets = EXCLUDE_VAN
  ? [SELECT Id FROM ProductItem WHERE Location.LocationType = 'Warehouse' AND ServiceCenter__c = null]
  : [SELECT Id FROM ProductItem WHERE ServiceCenter__c = null];
System.debug(LoggingLevel.WARN, 'FILL 대상 재고 ' + targets.size() + ' · 차량 제외 ' + EXCLUDE_VAN + ' · APPLY=' + APPLY);
if (APPLY && !targets.isEmpty()) {
  List<ProductItem> touch = new List<ProductItem>();
  for (ProductItem pi : targets) { touch.add(new ProductItem(Id = pi.Id)); }
  update touch;
  System.debug(LoggingLevel.WARN, 'FILL 저장 ' + touch.size() + ' · 남은 빈 센터(창고) ' + [SELECT COUNT() FROM ProductItem WHERE Location.LocationType = 'Warehouse' AND ServiceCenter__c = null]);
}
