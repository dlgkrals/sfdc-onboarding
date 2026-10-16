/**
 * @description 접수별 출동 집계와 접수 자동 상태
 *              열린 출동 수(배정·수락·도착·승인 대기)·완료 출동 수를 접수에 저장하고,
 *              처리 중 접수가 열린 출동 0 + 완료 1건 이상이 되면 완료, 완료 접수에 열린 출동이 다시 생기면 처리 중
 *              종결·취소 접수는 건드리지 않음(Case.Closed_Lock)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (접수 자동 완료·종결 대기, BR-18 근거 필드)
 * ----------------------------------------------------------------------------
 * @see WorkOrderTriggerHandler, Case.OpenWorkOrders_BlockClose, scripts/apex/d9_case_workorder_stats_fill.apex
 */
// DESC: 접수의 "전체" 출동을 세야 하므로 without sharing + SYSTEM_MODE (기사는 접수 권한이 없고, 집계 필드는 사용자에게 읽기 전용)
public without sharing class CaseWorkOrderStatsService {
  public static final Set<String> OPEN_STATUSES = new Set<String>{
    'Assigned',
    'Accepted',
    'Arrived',
    'PendingApproval'
  };
  private static final String WO_COMPLETED = 'Completed';
  private static final String CASE_IN_PROGRESS = 'InProgress';
  private static final String CASE_COMPLETED = 'Completed';
  private static final Set<String> CASE_LOCKED = new Set<String>{
    'Closed',
    'Canceled'
  };

  /**
   * @description 접수별 열린·완료 출동 수를 다시 세고, 필요하면 접수 상태를 바꿔 저장 (값이 바뀐 접수만)
   * @param caseIds 다시 계산할 접수 Id
   * @return 저장한 접수 수
   */
  public static Integer recalculate(Set<Id> caseIds) {
    if (caseIds == null) {
      return 0;
    }
    Set<Id> targetIds = new Set<Id>(caseIds);
    targetIds.remove(null);
    if (targetIds.isEmpty()) {
      return 0;
    }
    // PERF: 집계 쿼리 1회
    Map<Id, Integer> openByCase = new Map<Id, Integer>();
    Map<Id, Integer> doneByCase = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT CaseId caseId, Status st, COUNT(Id) n
      FROM WorkOrder
      WHERE CaseId IN :targetIds
      WITH SYSTEM_MODE
      GROUP BY CaseId, Status
    ]) {
      Id caseId = (Id) ar.get('caseId');
      String st = (String) ar.get('st');
      Integer n = (Integer) ar.get('n');
      if (OPEN_STATUSES.contains(st)) {
        openByCase.put(caseId, valueOf(openByCase.get(caseId)) + n);
      } else if (st == WO_COMPLETED) {
        doneByCase.put(caseId, valueOf(doneByCase.get(caseId)) + n);
      }
    }

    List<Case> toUpdate = new List<Case>();
    for (Case c : [
      SELECT Id, Status, OpenWorkOrderCount__c, CompletedWorkOrderCount__c
      FROM Case
      WHERE Id IN :targetIds AND Status NOT IN :CASE_LOCKED
      WITH SYSTEM_MODE
    ]) {
      Integer open = valueOf(openByCase.get(c.Id));
      Integer done = valueOf(doneByCase.get(c.Id));
      String newStatus = c.Status;
      if (c.Status == CASE_IN_PROGRESS && open == 0 && done > 0) {
        newStatus = CASE_COMPLETED;
      } else if (c.Status == CASE_COMPLETED && open > 0) {
        // DESC: 재방문·재배정으로 열린 출동이 다시 생기면 처리 중으로 (어느 경로로 출동이 생겨도)
        newStatus = CASE_IN_PROGRESS;
      }
      if (
        c.OpenWorkOrderCount__c == open &&
        c.CompletedWorkOrderCount__c == done &&
        newStatus == c.Status
      ) {
        continue;
      }
      toUpdate.add(
        new Case(
          Id = c.Id,
          OpenWorkOrderCount__c = open,
          CompletedWorkOrderCount__c = done,
          Status = newStatus
        )
      );
    }
    if (toUpdate.isEmpty()) {
      return 0;
    }
    // WARN: 일부가 검증 규칙 등으로 실패해도 출동 저장은 막지 않음 (실패는 로그, 다음 계산·일괄 스크립트에서 다시 맞춤)
    Integer saved = 0;
    List<Database.SaveResult> results = Database.update(
      toUpdate,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        saved++;
      } else {
        System.debug(
          LoggingLevel.WARN,
          '접수 출동 집계 저장 실패 ' +
            toUpdate[i].Id +
            ': ' +
            results[i].getErrors()[0].getMessage()
        );
      }
    }
    return saved;
  }

  private static Integer valueOf(Integer n) {
    return n == null ? 0 : n;
  }
}
