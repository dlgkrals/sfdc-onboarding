/**
 * @description 장비 반복 고장 재계산 Batch를 예약 실행 (매일 02:00, scripts/apex/d6_schedule.apex로 예약)
 * @layer       Schedulable
 * @author      Edwin
 * @date        2026-10-12
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-12    Edwin     최초 작성 (D6 실습)
 * ----------------------------------------------------------------------------
 * @see AssetRepeatFailureBatch
 */
public with sharing class AssetRepeatFailureSchedulable implements Schedulable {
  // DESC: 한 번에 처리할 장비 수. 트리거 묶음 크기와 같은 200
  public static final Integer BATCH_SIZE = 200;

  public void execute(SchedulableContext context) {
    Database.executeBatch(new AssetRepeatFailureBatch(), BATCH_SIZE);
  }
}
