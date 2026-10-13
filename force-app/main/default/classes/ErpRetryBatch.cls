/**
 * @description ERP 재전송 Batch — 사용 부품(IF-03)·재고 이동(IF-06) 중 아직 ERP에 반영되지 않은 건을 다시 보냄
 *              대상 ① 실패(Failed) + 재시도 횟수 < 상한(ServiceSetting ErpMaxRetry) → 재전송(실패 시 횟수 + 1, 상한 도달 시 확인 필요)
 *                   ② 대기(Pending)로 일정 시간 넘게 남은 건 (Queueable 한도 초과 등으로 전송되지 않음) → 첫 전송으로 보냄
 *              확인 필요·완료·재시도 초과는 대상 아님. ERP는 같은 refId(레코드 Id)를 중복 처리하지 않으므로 겹쳐 보내도 재고가 두 번 빠지지 않음
 * @layer       Batch
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 7번)
 * ----------------------------------------------------------------------------
 * @see ErpRetrySchedulable, ErpInventoryService, scripts/apex/d7_erp_retry_schedule.apex
 */
// DESC: 두 오브젝트를 한 번에 돌리려고 Id 목록(Iterable<Id>)으로 시작. 묶음 200건 = 오브젝트·종류별 콜아웃 최대 1번씩
public with sharing class ErpRetryBatch implements Database.Batchable<Id>, Database.AllowsCallouts, Database.Stateful {
  // DESC: 대기 건은 이 시간(분)이 지나야 재전송 (방금 저장돼 Queueable이 처리 중인 건과 겹치지 않게)
  @TestVisible
  private static Integer pendingGraceMinutes = 10;

  private Integer processedCount = 0;

  public Iterable<Id> start(Database.BatchableContext context) {
    Integer maxRetry = ErpInventoryService.getMaxRetry();
    Datetime pendingBefore = Datetime.now().addMinutes(-pendingGraceMinutes);
    List<Id> ids = new List<Id>();
    // PERF: 오브젝트별 1회 조회, Id만 넘김 (실제 값은 execute에서 최신으로 다시 조회)
    for (ProductConsumed pc : [
      SELECT Id
      FROM ProductConsumed
      WHERE
        (ErpSyncStatus__c = :ErpInventoryService.STATUS_FAILED
        AND ErpRetryCount__c < :maxRetry)
        OR (ErpSyncStatus__c = :ErpInventoryService.STATUS_PENDING
        AND LastModifiedDate < :pendingBefore)
      WITH SYSTEM_MODE
    ]) {
      ids.add(pc.Id);
    }
    for (ProductTransfer pt : [
      SELECT Id
      FROM ProductTransfer
      WHERE
        (ErpSyncStatus__c = :ErpInventoryService.STATUS_FAILED
        AND ErpRetryCount__c < :maxRetry)
        OR (ErpSyncStatus__c = :ErpInventoryService.STATUS_PENDING
        AND LastModifiedDate < :pendingBefore)
      WITH SYSTEM_MODE
    ]) {
      ids.add(pt.Id);
    }
    return ids;
  }

  public void execute(Database.BatchableContext context, List<Id> scope) {
    Set<Id> scopeIds = new Set<Id>(scope);
    // DESC: 실패 건은 재전송(횟수 증가), 대기 건은 첫 전송. 오브젝트별로 상태를 다시 읽어 나눔
    Set<Id> failedConsumedIds = new Set<Id>();
    Set<Id> pendingConsumedIds = new Set<Id>();
    for (ProductConsumed pc : [
      SELECT Id, ErpSyncStatus__c
      FROM ProductConsumed
      WHERE Id IN :scopeIds
      WITH SYSTEM_MODE
    ]) {
      if (pc.ErpSyncStatus__c == ErpInventoryService.STATUS_FAILED) {
        failedConsumedIds.add(pc.Id);
      } else {
        pendingConsumedIds.add(pc.Id);
      }
    }
    Set<Id> failedTransferIds = new Set<Id>();
    Set<Id> pendingTransferIds = new Set<Id>();
    for (ProductTransfer pt : [
      SELECT Id, ErpSyncStatus__c
      FROM ProductTransfer
      WHERE Id IN :scopeIds
      WITH SYSTEM_MODE
    ]) {
      if (pt.ErpSyncStatus__c == ErpInventoryService.STATUS_FAILED) {
        failedTransferIds.add(pt.Id);
      } else {
        pendingTransferIds.add(pt.Id);
      }
    }

    // WARN: 저장(DML) 뒤에는 콜아웃 불가 → 모두 보낸 다음 한꺼번에 저장
    List<SObject> updates = new List<SObject>();
    updates.addAll(
      ErpInventoryService.buildConsumedUpdates(failedConsumedIds, true)
    );
    updates.addAll(
      ErpInventoryService.buildConsumedUpdates(pendingConsumedIds, false)
    );
    List<SObject> transferUpdates = new List<SObject>();
    transferUpdates.addAll(
      ErpInventoryService.buildTransferUpdates(failedTransferIds, true)
    );
    transferUpdates.addAll(
      ErpInventoryService.buildTransferUpdates(pendingTransferIds, false)
    );
    ErpInventoryService.save(updates);
    ErpInventoryService.save(transferUpdates);
    processedCount += updates.size() + transferUpdates.size();
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.INFO,
      'ERP 재전송 완료: ' +
        processedCount +
        '건 처리 (Job ' +
        context.getJobId() +
        ')'
    );
  }
}
