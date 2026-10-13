/**
 * @description ERP 재고 역방향 동기화 Batch를 예약 실행 (15분마다: 00·15·30·45분에 예약 4개, scripts/apex/d7_erp_inbound_schedule.apex)
 * @layer       Schedulable
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 IF-02 역방향)
 * ----------------------------------------------------------------------------
 * @see ErpStockSyncBatch
 */
public with sharing class ErpStockSyncSchedulable implements Schedulable {
  // DESC: 한 묶음 = ERP 이력 한 쪽 (콜아웃 1번)
  public static final Integer BATCH_SIZE = 1;

  public void execute(SchedulableContext context) {
    // WARN: 클래스 이름으로 생성 → 예약 중에도 ERP 코드 배포가 "보류 중인 작업"으로 막히지 않음 (ErpRetrySchedulable과 같은 방식)
    Database.Batchable<Integer> batch = (Database.Batchable<Integer>) Type.forName(
        'ErpStockSyncBatch'
      )
      .newInstance();
    Database.executeBatch(batch, BATCH_SIZE);
  }
}
