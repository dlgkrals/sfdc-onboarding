// D7 ERP 연동 IF-02 역방향: 기준점 설정 (운영 시작 1회)
// ERP의 현재 최신 이력 번호를 "마지막으로 가져온 번호"로 저장 → 그 이전(초기 적재·과거 사용 기록)은 반영하지 않음
// 이미 기준점이 있으면 바꾸지 않음. 다시 정하려면 FORCE = true (그 사이 ERP 변동은 반영되지 않으니 주의)
Boolean FORCE = false;
Long current = ErpStockSyncService.getLastMovementId();
Long latest = ErpStockSyncService.fetchLatestId();
if (current != null && !FORCE) {
    System.debug(LoggingLevel.WARN, 'BASELINE 이미 있음: ' + current + ' (ERP 최신 ' + latest + ') — 바꾸지 않음');
} else {
    ErpStockSyncService.saveLastMovementId(latest == null ? 0 : latest);
    System.debug(LoggingLevel.WARN, 'BASELINE 저장: ' + current + ' → ' + latest);
}
