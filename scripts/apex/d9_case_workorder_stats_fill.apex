// 접수 열린·완료 출동 수 채우기 — 2026-10-16 (CaseWorkOrderStatsService 도입 전 데이터 1회). 종결·취소 접수는 대상 아님(잠김)
// APPLY = false: 대상 건수·상태가 바뀔 접수만 / true: 저장(처리 중 + 열린 0 + 완료 1+ → 완료, 완료 + 열린 1+ → 처리 중 규칙도 같이 적용)
Boolean APPLY = false;
Set<String> openSt = CaseWorkOrderStatsService.OPEN_STATUSES;
List<Case> targets = [SELECT Id, CaseNumber, Status FROM Case WHERE Status NOT IN ('Closed', 'Canceled')];
Map<Id, Integer> openBy = new Map<Id, Integer>();
Map<Id, Integer> doneBy = new Map<Id, Integer>();
for (AggregateResult ar : [SELECT CaseId cid, Status st, COUNT(Id) n FROM WorkOrder WHERE CaseId IN :targets GROUP BY CaseId, Status]) {
  Id cid = (Id) ar.get('cid'); String st = (String) ar.get('st'); Integer n = (Integer) ar.get('n');
  if (openSt.contains(st)) openBy.put(cid, (openBy.containsKey(cid) ? openBy.get(cid) : 0) + n);
  if (st == 'Completed') doneBy.put(cid, (doneBy.containsKey(cid) ? doneBy.get(cid) : 0) + n);
}
List<String> statusChanges = new List<String>();
for (Case c : targets) {
  Integer o = openBy.containsKey(c.Id) ? openBy.get(c.Id) : 0;
  Integer d = doneBy.containsKey(c.Id) ? doneBy.get(c.Id) : 0;
  if (c.Status == 'InProgress' && o == 0 && d > 0) statusChanges.add(c.CaseNumber + ' 처리 중→완료');
  if (c.Status == 'Completed' && o > 0) statusChanges.add(c.CaseNumber + ' 완료→처리 중');
}
System.debug(LoggingLevel.WARN, 'STATS 대상 접수 ' + targets.size() + ' · 상태가 바뀔 접수 ' + statusChanges.size() + ' ' + statusChanges + ' · APPLY=' + APPLY);
if (APPLY) {
  Set<Id> ids = new Map<Id, Case>(targets).keySet();
  Integer saved = CaseWorkOrderStatsService.recalculate(ids);
  System.debug(LoggingLevel.WARN, 'STATS 저장 ' + saved);
}
