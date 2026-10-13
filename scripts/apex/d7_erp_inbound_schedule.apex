// D7 ERP 연동 IF-02 역방향: 15분마다 예약 (Salesforce cron은 "15분마다"를 한 줄로 못 써서 00·15·30·45분 4개)
// 같은 이름이 있으면 건너뜀. 해제: 설정 → 예약된 작업에서 "HG ERP 재고 동기화 :MM" 삭제
// 기준점(d7_erp_inbound_baseline.apex)을 먼저 정해야 함 — 없으면 Batch가 아무것도 가져오지 않고 끝남
List<String> minutes = new List<String>{ '00', '15', '30', '45' };
Set<String> existing = new Set<String>();
for (CronTrigger ct : [SELECT CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE 'HG ERP 재고 동기화%']) {
    existing.add(ct.CronJobDetail.Name);
}
for (String mm : minutes) {
    String name = 'HG ERP 재고 동기화 :' + mm;
    if (existing.contains(name)) {
        System.debug(LoggingLevel.WARN, 'SCHEDULE 이미 있음 ' + name);
        continue;
    }
    String jobId = System.schedule(name, '0 ' + mm + ' * * * ?', new ErpStockSyncSchedulable());
    System.debug(LoggingLevel.WARN, 'SCHEDULE 예약 ' + name + ' Id=' + jobId);
}
