/**
 * @description 출동(WorkOrder) 트리거 핸들러
 *              after insert/update/delete/undelete : 장비·고객사·사업장 누적 청구액(TotalWorkOrderCharge__c) 다시 계산
 *              after update는 장비·고객사·사업장·방문 여부(상태)·방문비·유상 부품비가 바뀐 출동의 상위 레코드만
 *              (사용 부품 추가·삭제 → 유상 부품비 Roll-Up 변경 → 출동 update로 이 핸들러가 불림)
 *              출동의 장비·고객사·사업장 채우기는 저장 전 Flow WorkOrder_BeforeSave_FillAsset (같은 레코드 필드 채우기)
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (장비 화면 누적 청구액)
 * 1.1    2026-10-16    Edwin     고객사·사업장 누적 청구액도 계산(바뀌면 이전·새 상위 둘 다)
 * ----------------------------------------------------------------------------
 * @see WorkOrderTrigger, WorkOrderChargeService, TriggerHandler
 */
public with sharing class WorkOrderTriggerHandler extends TriggerHandler {
  // DESC: 재귀 방지용. 출동별로 마지막으로 계산한 상태(장비·고객사·사업장 + 방문 여부 + 방문비 + 유상 부품비)
  //       같은 상태로 다시 불리면 건너뛰고, 같은 트랜잭션이라도 값이 또 바뀌면 다시 계산 (CaseTriggerHandler 1.1과 같은 방식)
  private static Map<Id, String> processedStatesByWorkOrderId = new Map<Id, String>();

  protected override void afterInsert() {
    recalculateVisited((List<WorkOrder>) Trigger.new);
  }

  protected override void afterUpdate() {
    Map<Id, WorkOrder> oldById = (Map<Id, WorkOrder>) Trigger.oldMap;
    ParentIds parents = new ParentIds();
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
      // DESC: 장비·고객사·사업장이 바뀌면 이전 상위와 새 상위 둘 다
      parents.add(oldWo);
      parents.add(newWo);
    }
    parents.recalculate();
  }

  protected override void afterDelete() {
    recalculateVisited((List<WorkOrder>) Trigger.old);
  }

  protected override void afterUndelete() {
    recalculateVisited((List<WorkOrder>) Trigger.new);
  }

  // DESC: 합계에 영향을 주는 값만 묶은 상태 문자열
  private static String stateOf(WorkOrder wo) {
    return String.valueOf(wo.AssetId) +
      '|' +
      String.valueOf(wo.AccountId) +
      '|' +
      String.valueOf(wo.CustomerSite__c) +
      '|' +
      WorkOrderChargeService.VISITED_STATUSES.contains(wo.Status) +
      '|' +
      String.valueOf(wo.VisitFee__c) +
      '|' +
      String.valueOf(wo.ruPaidPartsTotal__c);
  }

  // DESC: 방문하지 않은 출동의 생성·삭제는 합계를 바꾸지 않으므로 방문한 출동의 상위만
  private static void recalculateVisited(List<WorkOrder> workOrders) {
    ParentIds parents = new ParentIds();
    for (WorkOrder wo : workOrders) {
      if (WorkOrderChargeService.VISITED_STATUSES.contains(wo.Status)) {
        parents.add(wo);
      }
    }
    parents.recalculate();
  }

  // DESC: 다시 계산할 상위 레코드 Id 모음 (장비·고객사·사업장)
  private class ParentIds {
    private Set<Id> assetIds = new Set<Id>();
    private Set<Id> accountIds = new Set<Id>();
    private Set<Id> siteIds = new Set<Id>();

    private void add(WorkOrder wo) {
      assetIds.add(wo.AssetId);
      accountIds.add(wo.AccountId);
      siteIds.add(wo.CustomerSite__c);
    }

    private void recalculate() {
      assetIds.remove(null);
      accountIds.remove(null);
      siteIds.remove(null);
      if (assetIds.isEmpty() && accountIds.isEmpty() && siteIds.isEmpty()) {
        return;
      }
      WorkOrderChargeService.recalculateParentTotals(
        assetIds,
        accountIds,
        siteIds
      );
    }
  }
}
