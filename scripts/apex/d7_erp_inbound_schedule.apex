// IF-02 역방향 가져오기(Pull) 예약 — 2026-10-15부터 푸시(Push)가 주 경로, 가져오기는 매시 30분 1개 안전망
// (D7에는 15분마다 00·15·30·45분 4개였음 → 이 스크립트가 4개를 지우고 1개로 바꿈)
// APPLY = false: 지울 예약·만들 예약만 보여 줌 / true: 실제로 바꿈
// 기준점(d7_erp_inbound_baseline.apex)을 먼저 정해야 함 — 없으면 Batch가 아무것도 가져오지 않고 끝남
Boolean APPLY = false;
String targetName = 'HG ERP 재고 동기화 :30 (매시, 푸시 안전망)';
List<CronTrigger> olds = [
  SELECT Id, CronJobDetail.Name, CronExpression
  FROM CronTrigger
  WHERE CronJobDetail.Name LIKE 'HG ERP 재고 동기화%'
];
Boolean hasTarget = false;
for (CronTrigger ct : olds) {
  if (ct.CronJobDetail.Name == targetName) {
    hasTarget = true;
    System.debug(
      LoggingLevel.WARN,
      'SCHEDULE 유지 ' + ct.CronJobDetail.Name + ' (' + ct.CronExpression + ')'
    );
    continue;
  }
  System.debug(
    LoggingLevel.WARN,
    'SCHEDULE 해제 대상 ' +
      ct.CronJobDetail.Name +
      ' (' +
      ct.CronExpression +
      ')'
  );
  if (APPLY) {
    System.abortJob(ct.Id);
  }
}
if (!hasTarget) {
  System.debug(
    LoggingLevel.WARN,
    'SCHEDULE 새로 예약 ' + targetName + ' (0 30 * * * ?)'
  );
  if (APPLY) {
    System.debug(
      LoggingLevel.WARN,
      'SCHEDULE 예약 Id=' +
      System.schedule(targetName, '0 30 * * * ?', new ErpStockSyncSchedulable())
    );
  }
}
System.debug(LoggingLevel.WARN, 'SCHEDULE APPLY=' + APPLY);
