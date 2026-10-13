// D7 ERP 연동 7번: ERP 재전송 Batch를 매시 정각에 예약
// 같은 이름의 예약 작업이 이미 있으면 중복 예약하지 않음
// 예약 해제: 설정 → 예약된 작업(Scheduled Jobs)에서 삭제하거나 System.abortJob(CronTrigger Id)
// 참고: ErpRetrySchedulable은 Batch를 클래스 이름으로 만들어서, 예약 중에도 ERP 코드 배포가 막히지 않음
String JOB_NAME = 'HG ERP 재전송';
String CRON_HOURLY = '0 0 * * * ?';   // 초 분 시 일 월 요일 → 매시 0분 0초

List<CronTrigger> existing = [
    SELECT Id, State, NextFireTime
    FROM CronTrigger
    WHERE CronJobDetail.Name = :JOB_NAME
];
if (!existing.isEmpty()) {
    System.debug(LoggingLevel.WARN, '이미 예약됨  ' + JOB_NAME + '  상태=' + existing[0].State + '  다음 실행=' + existing[0].NextFireTime + '  (새로 예약하지 않음)');
} else {
    String jobId = System.schedule(JOB_NAME, CRON_HOURLY, new ErpRetrySchedulable());
    CronTrigger scheduled = [SELECT NextFireTime FROM CronTrigger WHERE Id = :jobId];
    System.debug(LoggingLevel.WARN, '예약 완료  ' + JOB_NAME + '  Id=' + jobId + '  다음 실행=' + scheduled.NextFireTime);
}
