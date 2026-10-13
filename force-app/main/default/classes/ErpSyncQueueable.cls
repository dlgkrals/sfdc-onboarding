/**
 * @description ERP 전송 비동기 작업 — 트리거에서는 콜아웃을 할 수 없어 저장 직후 이 작업으로 넘김
 *              사용 부품(IF-03)을 ErpInventoryService로 전송 (재고 이동 IF-06은 6번에서 추가)
 * @layer       Queueable
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 5번)
 * ----------------------------------------------------------------------------
 * @see ErpInventoryService
 */
// DESC: 비동기 4종 중 Queueable — 콜아웃 필요(Database.AllowsCallouts), Id 집합을 넘김, 저장 직후 바로 실행
public with sharing class ErpSyncQueueable implements Queueable, Database.AllowsCallouts {
  private final Set<Id> consumedIds;
  private final Boolean isRetry;

  public ErpSyncQueueable(Set<Id> consumedIds, Boolean isRetry) {
    this.consumedIds = consumedIds == null ? new Set<Id>() : consumedIds;
    this.isRetry = isRetry == true;
  }

  public void execute(QueueableContext context) {
    ErpInventoryService.sendConsumed(consumedIds, isRetry);
  }
}
