/**
 * @description AssetRepeatFailureSchedulable 예약 실행 시 Batch가 큐에 들어가는지 검증하는 테스트 클래스
 * @testTarget  AssetRepeatFailureSchedulable
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-12
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-12    Edwin     최초 작성 (D6 실습)
 * ----------------------------------------------------------------------------
 * @see AssetRepeatFailureSchedulable, AssetRepeatFailureBatch
 */
@isTest
private class AssetRepeatFailureSchedulableTest {
  private static final String CRON_DAILY_2AM = '0 0 2 * * ?';

  // 정상: 매일 02:00으로 예약되고, 예약 작업이 실행되면 AssetRepeatFailureBatch가 Batch Apex로 큐에 들어감
  @isTest
  static void normalScheduleEnqueuesBatch() {
    Test.startTest();
    Id cronId = System.schedule(
      'HG 반복 고장 재계산 테스트',
      CRON_DAILY_2AM,
      new AssetRepeatFailureSchedulable()
    );
    CronTrigger scheduled = [
      SELECT CronExpression, State
      FROM CronTrigger
      WHERE Id = :cronId
    ];
    Test.stopTest();

    Assert.areEqual(CRON_DAILY_2AM, scheduled.CronExpression, '매일 02:00');
    Assert.areEqual('WAITING', scheduled.State, '예약 대기 상태');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          JobType = 'BatchApex'
          AND ApexClass.Name = 'AssetRepeatFailureBatch'
      ],
      '예약 실행 시 Batch가 큐에 들어감'
    );
  }
}
