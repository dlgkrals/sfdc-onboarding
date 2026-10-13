/**
 * @description ERP 재전송 Batch를 예약 실행 (매시 정각, scripts/apex/d7_erp_retry_schedule.apex로 예약)
 * @layer       Schedulable
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 7번)
 * ----------------------------------------------------------------------------
 * @see ErpRetryBatch
 */
public with sharing class ErpRetrySchedulable implements Schedulable {
  // DESC: 한 번에 처리할 건수 = ERP 한 번 요청 상한(200)과 같게
  public static final Integer BATCH_SIZE = 200;

  public void execute(SchedulableContext context) {
    // WARN: 클래스 이름으로 생성 → 예약 작업이 Batch·ErpInventoryService를 직접 참조하지 않아,
    //       예약 중에도 ERP 코드 배포가 "보류 중인 작업" 오류로 막히지 않음 (반복 고장 예약 작업에서 겪은 문제)
    Database.Batchable<Id> batch = (Database.Batchable<Id>) Type.forName(
        'ErpRetryBatch'
      )
      .newInstance();
    Database.executeBatch(batch, BATCH_SIZE);
  }
}
