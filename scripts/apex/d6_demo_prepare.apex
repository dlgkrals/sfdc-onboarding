// D6 시연 준비: 접수가 없는 장비를 "반복 고장인데 최근 접수 5건"으로 일부러 틀리게 만듦
// → 이어서 d6_run_batch.apex를 실행하면 Batch가 반복 고장 해제 · 최근 접수 0으로 바로잡음
// 시연 장비: HG-HAC300-2201-0018 ((주)금강물산, 접수 0건)
// WARN: 익명 Apex는 SYSTEM_MODE를 쓸 수 없음. 필드 권한 오류가 나면 터미널에서 API 66.0(기본 system mode)으로 실행
//       sf apex run -f scripts/apex/d6_demo_prepare.apex -o devorg --api-version 66.0
String DEMO_SERIAL = 'HG-HAC300-2201-0018';

Asset demo = [
    SELECT Id, RecentCaseCount__c, RepeatFailure__c
    FROM Asset
    WHERE SerialKey__c = :DEMO_SERIAL
];
System.debug(LoggingLevel.WARN, '변경 전  ' + DEMO_SERIAL + '  최근 90일 접수=' + demo.RecentCaseCount__c + '  반복 고장=' + demo.RepeatFailure__c);

demo.RecentCaseCount__c = 5;
demo.RepeatFailure__c = true;
Database.SaveResult result = Database.update(demo, false);

if (result.isSuccess()) {
    System.debug(LoggingLevel.WARN, '변경 후  ' + DEMO_SERIAL + '  최근 90일 접수=5  반복 고장=true  (잘못된 상태, Batch가 바로잡을 대상)');
} else {
    System.debug(LoggingLevel.WARN, '저장 실패  ' + result.getErrors()[0].getMessage() + '  → 터미널에서 --api-version 66.0 으로 다시 실행');
}
