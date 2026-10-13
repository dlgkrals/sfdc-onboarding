/**
 * @description ERP 전송 비동기 작업 — 트리거에서는 콜아웃을 할 수 없어 저장 직후 이 작업으로 넘김
 *              사용 부품(IF-03)·재고 이동(IF-06)을 ErpInventoryService로 전송
 *              저장(DML) 뒤에는 콜아웃을 할 수 없으므로 두 종류를 모두 보낸 다음 결과를 한꺼번에 저장
 * @layer       Queueable
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 5번)
 * 1.1    2026-10-13    Edwin     재고 이동(IF-06) 추가, 콜아웃 모두 끝낸 뒤 저장
 * ----------------------------------------------------------------------------
 * @see ErpInventoryService
 */
// DESC: 비동기 4종 중 Queueable — 콜아웃 필요(Database.AllowsCallouts), Id 집합을 넘김, 저장 직후 바로 실행
public with sharing class ErpSyncQueueable implements Queueable, Database.AllowsCallouts {
  private final Set<Id> consumedIds;
  private final Set<Id> transferIds;
  private final Boolean isRetry;

  public ErpSyncQueueable(Set<Id> consumedIds, Boolean isRetry) {
    this(consumedIds, new Set<Id>(), isRetry);
  }

  public ErpSyncQueueable(
    Set<Id> consumedIds,
    Set<Id> transferIds,
    Boolean isRetry
  ) {
    this.consumedIds = consumedIds == null ? new Set<Id>() : consumedIds;
    this.transferIds = transferIds == null ? new Set<Id>() : transferIds;
    this.isRetry = isRetry == true;
  }

  public void execute(QueueableContext context) {
    List<ProductConsumed> consumedUpdates = ErpInventoryService.buildConsumedUpdates(
      consumedIds,
      isRetry
    );
    List<ProductTransfer> transferUpdates = ErpInventoryService.buildTransferUpdates(
      transferIds,
      isRetry
    );
    ErpInventoryService.save(consumedUpdates);
    ErpInventoryService.save(transferUpdates);
  }
}
