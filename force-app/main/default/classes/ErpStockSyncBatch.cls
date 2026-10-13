/**
 * @description ERP → Salesforce 재고 역방향 동기화 Batch (IF-02)
 *              한 묶음(scope 1) = ERP 이력 한 쪽(최대 200건). 쪽마다 별도 트랜잭션이라 한 쪽이 실패해도 앞 쪽 반영은 유지
 *              더 가져올 것이 없으면 남은 묶음은 바로 끝냄. 한 번 실행에 최대 MAX_PAGES쪽, 나머지는 다음 실행에서
 * @layer       Batch
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 IF-02 역방향)
 * ----------------------------------------------------------------------------
 * @see ErpStockSyncService, ErpStockSyncSchedulable, scripts/apex/d7_erp_inbound_*.apex
 */
public with sharing class ErpStockSyncBatch implements Database.Batchable<Integer>, Database.AllowsCallouts, Database.Stateful {
  // DESC: 15분마다 도는데 한 번에 200 × 10 = 2,000건이면 충분. 테스트는 1쪽(테스트에서는 execute 1번만 가능)
  @TestVisible
  private static Integer maxPages = 10;

  private Boolean done = false;
  private Integer applied = 0;
  private Integer errors = 0;
  private Integer skipped = 0;
  private String failure;

  public Iterable<Integer> start(Database.BatchableContext context) {
    List<Integer> pages = new List<Integer>();
    for (Integer i = 1; i <= maxPages; i++) {
      pages.add(i);
    }
    return pages;
  }

  public void execute(Database.BatchableContext context, List<Integer> scope) {
    if (done) {
      return;
    }
    try {
      ErpStockSyncService.SyncResult result = ErpStockSyncService.syncNextPage();
      applied += result.applied;
      errors += result.errors;
      skipped += result.skipped;
      done = !result.hasMore;
    } catch (Exception e) {
      // DESC: 통신 실패·기준점 없음·저장 실패 → 이 쪽은 전부 취소, 이력 번호를 올리지 않고 이번 실행 종료, 다음 실행에서 다시
      failure = e.getMessage();
      done = true;
    }
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.WARN,
      'ERP 재고 동기화(IF-02): 반영 ' +
        applied +
        ' · 오류 ' +
        errors +
        ' · 건너뜀 ' +
        skipped +
        (failure == null ? '' : ' · 중단 ' + failure) +
        ' · 마지막 이력 번호 ' +
        ErpStockSyncService.getLastMovementId()
    );
  }
}
