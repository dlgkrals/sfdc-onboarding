// D6 실습 시연: 장비 반복 고장 재계산 Batch 즉시 실행
// 실행 후 설정 → Apex 작업(Apex Jobs)에서 완료·처리 배치 수 확인. 처리 건수는 Batch finish의 Debug Log(WARN)에 남음
Integer repeatBefore = [SELECT COUNT() FROM Asset WHERE RepeatFailure__c = true];
Integer targetBefore = [SELECT COUNT() FROM Asset WHERE RecentCaseCount__c > 0 OR RepeatFailure__c = true];

Id jobId = Database.executeBatch(new AssetRepeatFailureBatch(), AssetRepeatFailureSchedulable.BATCH_SIZE);

System.debug(LoggingLevel.WARN, 'Batch 시작  작업 Id=' + jobId + '  대상 장비=' + targetBefore + '대  실행 전 반복 고장 장비=' + repeatBefore + '대');
