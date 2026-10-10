/**
 * @description 사용 부품(ProductConsumed) 트리거 핸들러
 *              1) before insert : 전부 유·무상 자동 판정
 *              2) before update : 부품(Product2Id·ProductItemId)이나 출동(WorkOrderId)이 바뀐 레코드만 다시 판정
 *              최종 판정(ChargeType__c)은 비어 있을 때만 채움 (WarrantyService)
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 실습: 유·무상 자동 판정 트리거)
 * ----------------------------------------------------------------------------
 * @see ProductConsumedTrigger, WarrantyService, TriggerHandler
 */
public with sharing class ProductConsumedTriggerHandler extends TriggerHandler {

    protected override void beforeInsert() {
        WarrantyService.judgeChargeTypes((List<ProductConsumed>) Trigger.new);
    }

    protected override void beforeUpdate() {
        Map<Id, ProductConsumed> oldPartsById = (Map<Id, ProductConsumed>) Trigger.oldMap;
        List<ProductConsumed> partsToJudge = new List<ProductConsumed>();
        for (ProductConsumed part : (List<ProductConsumed>) Trigger.new) {
            ProductConsumed oldPart = oldPartsById.get(part.Id);
            // DESC: 수량·사유·최종 판정만 바꾼 수정은 다시 판정하지 않음
            if (part.Product2Id != oldPart.Product2Id
                || part.ProductItemId != oldPart.ProductItemId
                || part.WorkOrderId != oldPart.WorkOrderId) {
                partsToJudge.add(part);
            }
        }
        if (!partsToJudge.isEmpty()) {
            WarrantyService.judgeChargeTypes(partsToJudge);
        }
    }
}