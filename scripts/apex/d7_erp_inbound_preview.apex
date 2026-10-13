// D7 ERP 연동 IF-02 역방향: 미리 보기 (반영하지 않음)
// 실제 org에서 동기화를 처음 돌리거나 시연 전에, 가져올 ERP 변동 건수를 먼저 확인 (7번 사고 교훈)
ErpStockSyncService.SyncResult r = ErpStockSyncService.preview();
System.debug(LoggingLevel.WARN, 'PREVIEW 현재 기준 이력 번호=' + r.fromId + ' (null이면 기준점 없음 → 0부터 조회한 결과)'
    + '  ERP 최신 번호=' + r.latestId);
System.debug(LoggingLevel.WARN, 'PREVIEW 가져올 이력 ' + r.fetched + '건 = 반영 대상(ERP 입고·조정) ' + r.erpChanges
    + '건 + 건너뜀(Salesforce 사용·이동·초기 적재) ' + r.skipped + '건' + (r.hasMore ? '  ※ 10쪽 넘음, 일부만 셈' : ''));
