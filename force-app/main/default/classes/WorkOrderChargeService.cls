/**
 * @description 출동 총 청구액(fmTotalCharge__c) 합계를 상위 레코드에 저장 — 지금은 장비 누적 청구액(Asset.TotalWorkOrderCharge__c)
 *              합계 대상 = 실제로 방문한 출동(도착·승인 대기·완료). 배정·수락·거절은 방문비가 생기지 않아 제외
 *              장비 → 출동은 Lookup이라 Roll-Up Summary 불가 → 출동 트리거가 이 서비스를 부름
 *              묶는 필드(출동의 조회 필드)와 대상 필드를 인자로 받아 고객사(AccountId)·사업장(CustomerSite__c)도 같은 메서드로 늘릴 수 있음
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-16
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-16    Edwin     최초 작성 (장비 화면 누적 청구액)
 * ----------------------------------------------------------------------------
 * @see WorkOrderTriggerHandler, CaseStatsService(같은 집계 패턴), scripts/apex/d9_asset_charge_backfill.apex
 */
// DESC: 합계는 실행 사용자의 공유 범위와 상관없이 그 장비의 "전체" 출동을 더해야 정확하므로 without sharing + SYSTEM_MODE
//       (누적 청구액은 사용자에게 읽기 전용이라 USER_MODE 저장은 필드 권한 오류 — CaseStatsService 1.5와 같은 이유)
public without sharing class WorkOrderChargeService {
  // DESC: 실제로 방문한 출동 상태 (Edwin 결정 2026-10-16)
  public static final Set<String> VISITED_STATUSES = new Set<String>{
    'Arrived',
    'PendingApproval',
    'Completed'
  };

  /**
   * @description 장비 누적 청구액 다시 계산 (출동이 없거나 방문한 출동이 없으면 0)
   * @param assetIds 다시 계산할 장비 Id
   * @return 값이 바뀌어 저장한 장비 수
   */
  public static Integer recalculateAssetTotals(Set<Id> assetIds) {
    return recalculateTotals(
      assetIds,
      WorkOrder.AssetId,
      Asset.TotalWorkOrderCharge__c
    );
  }

  /**
   * @description 출동의 조회 필드(groupField)로 묶은 방문 출동 총 청구액 합계를 상위 오브젝트 필드(targetField)에 저장
   * @param parentIds   다시 계산할 상위 레코드 Id
   * @param groupField  출동의 조회 필드 (예: WorkOrder.AssetId, WorkOrder.AccountId)
   * @param targetField 상위 오브젝트의 통화 필드 (예: Asset.TotalWorkOrderCharge__c)
   * @return 값이 바뀌어 저장한 레코드 수
   */
  public static Integer recalculateTotals(
    Set<Id> parentIds,
    Schema.SObjectField groupField,
    Schema.SObjectField targetField
  ) {
    if (parentIds == null) {
      return 0;
    }
    Set<Id> targetIds = new Set<Id>(parentIds);
    targetIds.remove(null);
    if (targetIds.isEmpty()) {
      return 0;
    }
    Schema.DescribeFieldResult groupDescribe = groupField.getDescribe();
    if (groupDescribe.getType() != Schema.DisplayType.REFERENCE) {
      throw new IllegalArgumentException(
        '묶는 필드는 출동의 조회 필드여야 합니다: ' + groupDescribe.getName()
      );
    }
    String groupName = groupDescribe.getName();
    Schema.DescribeFieldResult targetDescribe = targetField.getDescribe();
    // DESC: 대상 오브젝트는 Id의 접두어로 판단 (한 번 호출에 한 오브젝트)
    Schema.SObjectType targetType = new List<Id>(targetIds)[0].getSObjectType();

    // PERF: 집계 쿼리 1회 (상위 레코드 수와 상관없이). 수식 필드 fmTotalCharge__c도 SUM 가능(2026-10-16 확인)
    // DESC: 필드 이름은 describe 결과만 쓰고 값은 바인드 → 인젝션 없음
    Map<Id, Decimal> totalsByParent = new Map<Id, Decimal>();
    for (
      SObject row : Database.queryWithBinds(
        'SELECT ' +
          groupName +
          ' parentId, SUM(fmTotalCharge__c) total FROM WorkOrder WHERE ' +
          groupName +
          ' IN :targetIds AND Status IN :statuses GROUP BY ' +
          groupName,
        new Map<String, Object>{
          'targetIds' => targetIds,
          'statuses' => VISITED_STATUSES
        },
        AccessLevel.SYSTEM_MODE
      )
    ) {
      AggregateResult ar = (AggregateResult) row;
      Decimal total = (Decimal) ar.get('total');
      totalsByParent.put((Id) ar.get('parentId'), total == null ? 0 : total);
    }

    // DESC: 값이 바뀐 레코드만 저장 (불필요한 저장으로 장비 Flow·검증 규칙이 도는 것을 줄임)
    String targetName = targetDescribe.getName();
    List<SObject> toUpdate = new List<SObject>();
    for (
      SObject current : Database.queryWithBinds(
        'SELECT Id, ' +
          targetName +
          ' FROM ' +
          targetType.getDescribe().getName() +
          ' WHERE Id IN :targetIds',
        new Map<String, Object>{ 'targetIds' => targetIds },
        AccessLevel.SYSTEM_MODE
      )
    ) {
      Decimal newTotal = totalsByParent.containsKey(current.Id)
        ? totalsByParent.get(current.Id)
        : 0;
      if ((Decimal) current.get(targetName) == newTotal) {
        continue;
      }
      SObject updated = targetType.newSObject(current.Id);
      updated.put(targetName, newTotal);
      toUpdate.add(updated);
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
          '누적 청구액 저장 실패 ' +
            toUpdate[i].Id +
            ': ' +
            results[i].getErrors()[0].getMessage()
        );
      }
    }
    return saved;
  }
}
