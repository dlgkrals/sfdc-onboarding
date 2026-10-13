// D7 ERP 연동 IF-02 역방향 시연: 15분을 기다리지 않고 지금 동기화 Batch 실행
// 먼저 d7_erp_inbound_preview.apex로 건수 확인. 결과: 재고 수량 · ERP 재고 동기화 기록(IL-) · Apex 작업
Id jobId = Database.executeBatch(new ErpStockSyncBatch(), ErpStockSyncSchedulable.BATCH_SIZE);
System.debug(LoggingLevel.WARN, 'RUN Batch 시작 Job Id=' + jobId + '  현재 기준 이력 번호=' + ErpStockSyncService.getLastMovementId());
