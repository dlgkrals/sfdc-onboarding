/**
 * @description 사용 부품(ProductConsumed) 트리거 핸들러
 *              before insert : 전부 유·무상 자동 판정 (판정은 insert 시점 스냅샷)
 *              최종 판정(ChargeType__c)은 비어 있을 때만 채움 (WarrantyService)
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 실습: 유·무상 자동 판정 트리거)
 * 1.1    2026-10-11    Edwin     before update 재판정 제거 (출동·제품 항목·부품은 생성 후 수정 불가)
 * ----------------------------------------------------------------------------
 * @see ProductConsumedTrigger, WarrantyService, TriggerHandler
 */
// NOTE: WorkOrderId·ProductItemId·Product2Id는 생성 후 수정할 수 없으므로 판정 근거가 바뀌는 update가 없음.
//       부품을 바꾸려면 삭제 후 다시 입력 → 새 insert에서 다시 판정됨
public with sharing class ProductConsumedTriggerHandler extends TriggerHandler {
  protected override void beforeInsert() {
    WarrantyService.judgeChargeTypes((List<ProductConsumed>) Trigger.new);
  }
}
