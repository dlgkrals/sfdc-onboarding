/**
 * @description 사용 부품(ProductConsumed) 트리거 핸들러
 *              before insert : 전부 유·무상 자동 판정 (판정은 insert 시점 스냅샷)
 *              최종 판정(ChargeType__c)은 비어 있을 때만 채움 (WarrantyService)
 *              after insert  : ERP 재고 차감 전송 예약 (IF-03, Queueable 비동기 — 트리거에서는 콜아웃 불가)
 *              before delete : ERP에 반영됐거나 반영 여부를 모르는 사용 기록은 삭제 거부 (ERP 되돌림 API 없음)
 *              after delete  : 삭제가 허용된 건(ERP 미반영 확실)만 그 수량만큼 Salesforce 재고 되돌림
 *              after undelete: 휴지통 복원 거부 (잘못 지웠으면 새로 입력)
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 실습: 유·무상 자동 판정 트리거)
 * 1.1    2026-10-11    Edwin     before update 재판정 제거 (출동·제품 항목·부품은 생성 후 수정 불가)
 * 1.2    2026-10-13    Edwin     after insert ERP 전송 예약, before delete 삭제 규칙 (D7 ERP 연동)
 * 1.3    2026-10-13    Edwin     after delete 재고 되돌림, after undelete 복원 거부 (decision-log 11 A안)
 * ----------------------------------------------------------------------------
 * @see ProductConsumedTrigger, WarrantyService, ErpInventoryService, TriggerHandler
 */
// NOTE: WorkOrderId·ProductItemId·Product2Id는 생성 후 수정할 수 없으므로 판정 근거가 바뀌는 update가 없음.
//       부품을 바꾸려면 삭제 후 다시 입력 → 새 insert에서 다시 판정됨 (단, ERP 반영 전·실패한 것만 삭제 가능)
public with sharing class ProductConsumedTriggerHandler extends TriggerHandler {
  protected override void beforeInsert() {
    WarrantyService.judgeChargeTypes((List<ProductConsumed>) Trigger.new);
  }

  protected override void afterInsert() {
    ErpInventoryService.enqueueConsumed(Trigger.newMap.keySet());
  }

  protected override void beforeDelete() {
    for (ProductConsumed pc : (List<ProductConsumed>) Trigger.old) {
      if (!ErpInventoryService.canDelete(pc)) {
        pc.addError(System.Label.MSG_ERP_DELETE_BLOCKED);
      }
    }
  }

  // DESC: before delete에서 거부된 건은 여기 오지 않음 → 삭제가 확정된 건만 재고 되돌림
  protected override void afterDelete() {
    ErpInventoryService.restoreStockForDeleted(
      (List<ProductConsumed>) Trigger.old
    );
  }

  // WARN: 복원하면 재고·ERP 상태가 삭제 전 기준과 어긋나므로 막음. 잘못 지웠으면 새로 입력 (새 insert에서 판정·ERP 전송)
  protected override void afterUndelete() {
    for (ProductConsumed pc : (List<ProductConsumed>) Trigger.new) {
      pc.addError(System.Label.MSG_ERP_UNDELETE_BLOCKED);
    }
  }
}
