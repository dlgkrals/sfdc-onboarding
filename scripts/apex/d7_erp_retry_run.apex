// D7 ERP 연동 7번 시연: 정각을 기다리지 않고 ERP 재전송 Batch를 지금 바로 실행
// 실행 전 대상 건수를 보여 주고, 결과는 설정 → Apex 작업(Apex Jobs) 또는 각 레코드의 ERP 연동 상태에서 확인
Integer maxRetry = ErpInventoryService.getMaxRetry();
Integer failedParts = [SELECT COUNT() FROM ProductConsumed WHERE ErpSyncStatus__c = 'Failed' AND ErpRetryCount__c < :maxRetry];
Integer pendingParts = [SELECT COUNT() FROM ProductConsumed WHERE ErpSyncStatus__c = 'Pending'];
Integer failedTransfers = [SELECT COUNT() FROM ProductTransfer WHERE ErpSyncStatus__c = 'Failed' AND ErpRetryCount__c < :maxRetry];
Integer pendingTransfers = [SELECT COUNT() FROM ProductTransfer WHERE ErpSyncStatus__c = 'Pending'];
System.debug(LoggingLevel.WARN, '재전송 대상  사용 부품 실패 ' + failedParts + ' · 대기 ' + pendingParts
    + '  /  재고 이동 실패 ' + failedTransfers + ' · 대기 ' + pendingTransfers
    + '  (대기는 10분 지난 것만 보냄, 재시도 상한 ' + maxRetry + ')');
Id jobId = Database.executeBatch(new ErpRetryBatch(), ErpRetrySchedulable.BATCH_SIZE);
System.debug(LoggingLevel.WARN, 'Batch 시작  Job Id=' + jobId);
