// B2 Developer Edition 샘플 고객사 삭제 — 2026-10-16 (Edwin 승인 A안)
// 대상 = 레코드 유형이 없는 고객사(한결공조 고객사는 모두 Corporation·SoleProprietor·Individual·Dealer). 접수·장비·사업장·출동이 있으면 중단
// 함께 삭제: 영업 기회·권리(먼저 직접 삭제 — 수주 마감 영업 기회·권리가 있으면 고객사 삭제 거부), 연락처(표준 연쇄 삭제). 휴지통에서 15일 안에 되돌릴 수 있음
Boolean APPLY = false;
List<Account> targets = [SELECT Id, Name FROM Account WHERE RecordTypeId = null];
Integer linked = [SELECT COUNT() FROM Case WHERE AccountId IN :targets] + [SELECT COUNT() FROM Asset WHERE AccountId IN :targets] + [SELECT COUNT() FROM CustomerSite__c WHERE Account__c IN :targets] + [SELECT COUNT() FROM WorkOrder WHERE AccountId IN :targets];
System.debug(LoggingLevel.WARN, 'B2 대상 고객사 ' + targets.size() + ' · 연락처 ' + [SELECT COUNT() FROM Contact WHERE AccountId IN :targets] + ' · 영업 기회 ' + [SELECT COUNT() FROM Opportunity WHERE AccountId IN :targets] + ' · 한결 데이터 연결 ' + linked + ' · APPLY=' + APPLY);
for (Account a : targets) { System.debug(LoggingLevel.WARN, 'B2 - ' + a.Name); }
if (APPLY && linked == 0 && targets.size() == 13) {
  // DESC: 수주 마감된 영업 기회가 있으면 고객사 삭제가 거부됨(표준) → 영업 기회 먼저 삭제(승인 범위 31건)
  List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId IN :targets];
  delete opps;
  System.debug(LoggingLevel.WARN, 'B2 영업 기회 삭제 ' + opps.size());
  // DESC: 권리가 연결된 고객사도 삭제 거부(표준) → 권리 먼저 삭제(승인 범위 1건)
  List<Entitlement> ents = [SELECT Id FROM Entitlement WHERE AccountId IN :targets];
  delete ents;
  System.debug(LoggingLevel.WARN, 'B2 권리 삭제 ' + ents.size());
  delete targets; System.debug(LoggingLevel.WARN, 'B2 삭제 ' + targets.size()); }
