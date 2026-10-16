/**
 * @description 출동(WorkOrder) 트리거 핸들러
 *              after insert/update/delete/undelete : 장비 누적 청구액(Asset.TotalWorkOrderCharge__c) 다시 계산
 *              after update는 장비·방문 여부(상태)·방문비·유상 부품비가 바뀐 출동의 장비만
 *              (사용 부품 추가·삭제 → 유상 부품비 Roll-Up 변경 → 출동 update로 이 핸들러가 불림)
 *              출동의 장비 채우기는 저장 전 Flow WorkOrder_BeforeSave_FillAsset (같은 레코드 필드 채우기)
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (장비 화면 누적 청구액)
 * ----------------------------------------------------------------------------
 * @see WorkOrderTrigger, WorkOrderChargeService, TriggerHandler
 */
public with sharing class WorkOrderTriggerHandler extends TriggerHandler {
  // DESC: 재귀 방지용. 출동별로 마지막으로 계산한 상태(장비 + 방문 여부 + 방문비 + 유상 부품비)
  //       같은 상태로 다시 불리면 건너뛰고, 같은 트랜잭션이라도 값이 또 바뀌면 다시 계산 (CaseTriggerHandler 1.1과 같은 방식)
  private static Map<Id, String> processedStatesByWorkOrderId = new Map<Id, String>();

  protected override void afterInsert() {
    recalculate(collectVisitedAssetIds((List<WorkOrder>) Trigger.new));
  }

  protected override void afterUpdate() {
    Map<Id, WorkOrder> oldById = (Map<Id, WorkOrder>) Trigger.oldMap;
    Set<Id> assetIds = new Set<Id>();
    for (WorkOrder newWo : (List<WorkOrder>) Trigger.new) {
      WorkOrder oldWo = oldById.get(newWo.Id);
      String newState = stateOf(newWo);
      if (newState == stateOf(oldWo)) {
        continue;
      }
      if (processedStatesByWorkOrderId.get(newWo.Id) == newState) {
        continue;
      }
      processedStatesByWorkOrderId.put(newWo.Id, newState);
      // DESC: 장비가 바뀌면 이전 장비와 새 장비 둘 다
      if (oldWo.AssetId != null) {
        assetIds.add(oldWo.AssetId);
      }
      if (newWo.AssetId != null) {
        assetIds.add(newWo.AssetId);
      }
    }
    recalculate(assetIds);
  }

  protected override void afterDelete() {
    recalculate(collectVisitedAssetIds((List<WorkOrder>) Trigger.old));
  }

  protected override void afterUndelete() {
    recalculate(collectVisitedAssetIds((List<WorkOrder>) Trigger.new));
  }

  // DESC: 합계에 영향을 주는 값만 묶은 상태 문자열
  private static String stateOf(WorkOrder wo) {
    return String.valueOf(wo.AssetId) +
      '|' +
      WorkOrderChargeService.VISITED_STATUSES.contains(wo.Status) +
      '|' +
      String.valueOf(wo.VisitFee__c) +
      '|' +
      String.valueOf(wo.ruPaidPartsTotal__c);
  }

  // DESC: 방문하지 않은 출동의 생성·삭제는 합계를 바꾸지 않으므로 방문한 출동의 장비만
  private static Set<Id> collectVisitedAssetIds(List<WorkOrder> workOrders) {
    Set<Id> assetIds = new Set<Id>();
    for (WorkOrder wo : workOrders) {
      if (
        wo.AssetId != null &&
        WorkOrderChargeService.VISITED_STATUSES.contains(wo.Status)
      ) {
        assetIds.add(wo.AssetId);
      }
    }
    return assetIds;
  }

  private static void recalculate(Set<Id> assetIds) {
    if (!assetIds.isEmpty()) {
      WorkOrderChargeService.recalculateAssetTotals(assetIds);
    }
  }
}
