/**
 * @description 재고 이동(ProductTransfer) 트리거 핸들러 — 수령 시 ERP 재고 이동 전송 (IF-06)
 *              before insert·update : 이번 저장에서 수령된 건(IsReceived false → true, 또는 수령 상태로 생성)을 대기(Pending)로 표시
 *              after insert·update  : 수령된 건만 ERP 전송 예약 (Queueable 비동기 — 트리거에서는 콜아웃 불가)
 *              수령 시 창고 −·차량 + 는 Salesforce 표준이 처리, Apex는 수량을 건드리지 않음
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 6번)
 * ----------------------------------------------------------------------------
 * @see ProductTransferTrigger, ErpInventoryService, ErpSyncQueueable, TriggerHandler
 */
// NOTE: Queueable이 결과를 저장할 때도 after update가 돌지만, 이미 수령된 건(이전 값도 true)이라 다시 예약하지 않음
public with sharing class ProductTransferTriggerHandler extends TriggerHandler {
  protected override void beforeInsert() {
    markPending(newlyReceived((List<ProductTransfer>) Trigger.new, null));
  }

  protected override void beforeUpdate() {
    markPending(
      newlyReceived(
        (List<ProductTransfer>) Trigger.new,
        (Map<Id, ProductTransfer>) Trigger.oldMap
      )
    );
  }

  protected override void afterInsert() {
    ErpInventoryService.enqueueTransfers(
      idsOf(newlyReceived((List<ProductTransfer>) Trigger.new, null))
    );
  }

  protected override void afterUpdate() {
    ErpInventoryService.enqueueTransfers(
      idsOf(
        newlyReceived(
          (List<ProductTransfer>) Trigger.new,
          (Map<Id, ProductTransfer>) Trigger.oldMap
        )
      )
    );
  }

  // DESC: 이번 저장에서 수령된 건 (insert는 oldById = null)
  private static List<ProductTransfer> newlyReceived(
    List<ProductTransfer> transfers,
    Map<Id, ProductTransfer> oldById
  ) {
    List<ProductTransfer> received = new List<ProductTransfer>();
    for (ProductTransfer pt : transfers) {
      Boolean wasReceived =
        oldById != null &&
        oldById.get(pt.Id).IsReceived == true;
      if (pt.IsReceived == true && !wasReceived) {
        received.add(pt);
      }
    }
    return received;
  }

  // DESC: before 단계 값 지정이라 추가 저장 없음. 사용자에게 읽기 전용인 ERP 필드도 트리거에서는 채울 수 있음
  private static void markPending(List<ProductTransfer> received) {
    for (ProductTransfer pt : received) {
      pt.ErpSyncStatus__c = ErpInventoryService.STATUS_PENDING;
      pt.ErpRetryCount__c = 0;
    }
  }

  private static Set<Id> idsOf(List<ProductTransfer> transfers) {
    Set<Id> ids = new Set<Id>();
    for (ProductTransfer pt : transfers) {
      ids.add(pt.Id);
    }
    return ids;
  }
}
