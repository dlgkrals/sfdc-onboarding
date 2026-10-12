// D6 실습: 장비 반복 고장 재계산 Batch를 매일 02:00에 예약
// 같은 이름의 예약 작업이 이미 있으면 중복 예약하지 않음
// 예약 해제: 설정 → 예약된 작업(Scheduled Jobs)에서 삭제하거나 System.abortJob(CronTrigger Id)
String JOB_NAME = 'HG 반복 고장 재계산';
String CRON_DAILY_2AM = '0 0 2 * * ?';   // 초 분 시 일 월 요일

List<CronTrigger> existing = [
    SELECT Id, State, NextFireTime
    FROM CronTrigger
    WHERE CronJobDetail.Name = :JOB_NAME
];
if (!existing.isEmpty()) {
    System.debug(LoggingLevel.WARN, '이미 예약됨  ' + JOB_NAME + '  상태=' + existing[0].State + '  다음 실행=' + existing[0].NextFireTime + '  (새로 예약하지 않음)');
} else {
    String jobId = System.schedule(JOB_NAME, CRON_DAILY_2AM, new AssetRepeatFailureSchedulable());
    CronTrigger scheduled = [SELECT NextFireTime FROM CronTrigger WHERE Id = :jobId];
    System.debug(LoggingLevel.WARN, '예약 완료  ' + JOB_NAME + '  Id=' + jobId + '  다음 실행=' + scheduled.NextFireTime);
}
