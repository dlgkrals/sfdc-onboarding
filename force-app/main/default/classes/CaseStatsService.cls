/**
 * @description 접수(Case) 집계·일괄 처리 서비스
 *              1) 장비별 누적 접수 수·최근 접수일 재계산
 *                 (장비 → 접수가 Lookup이라 Roll-Up Summary를 쓸 수 없어 Apex로 대체)
 *              2) 최근 N일 같은 장비 접수가 기준 횟수 이상이면 반복 고장 표시 (BR-14)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-07
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-07    Edwin     최초 작성 (D4 실습: 벌크 안전 집계·일괄 처리)
 * 1.1    2026-10-08    Edwin     markRepeatFailures 대상에서 종결·취소 접수 제외 (Case.Closed_Lock 충돌 방지)
 * ----------------------------------------------------------------------------
 * @see CaseTriggerHandler (D5 예정: after insert/update/delete/undelete에서 호출)
 */
// DESC: 집계는 실행 사용자의 공유 범위와 상관없이 장비의 "전체" 접수를 세야 정확하므로 without sharing
public without sharing class CaseStatsService {

    private static final String STATUS_CANCELED = 'Canceled';
    private static final String STATUS_CLOSED = 'Closed';
    private static final Integer DEFAULT_REPEAT_DAYS = 90;
    private static final Integer DEFAULT_REPEAT_COUNT = 3;

    /**
     * @description 장비별 누적 접수 수(TotalCaseCount__c)와 최근 접수일(LastCaseDate__c)을 다시 계산해 저장
     *              취소된 접수는 제외. 접수가 하나도 없는 장비는 0 / null로 되돌림
     * @param assetIds 재계산할 장비 Id 집합 (여러 건을 한 번에)
     * @return 저장에 성공한 장비 수
     */
    public static Integer recalculateAssetCaseStats(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return 0;
        }
        Set<Id> targetIds = new Set<Id>(assetIds);
        targetIds.remove(null);
        if (targetIds.isEmpty()) {
            return 0;
        }

        Map<Id, Integer> caseCountsByAsset = new Map<Id, Integer>();
        Map<Id, Datetime> lastCaseDatesByAsset = new Map<Id, Datetime>();

        // PERF: 집계 쿼리 1회 (장비 수와 상관없이)
        for (AggregateResult ar : [
            SELECT AssetId assetId, COUNT(Id) cnt, MAX(CreatedDate) lastDt
            FROM Case
            WHERE AssetId IN :targetIds
              AND Status != :STATUS_CANCELED
            GROUP BY AssetId
        ]) {
            Id assetId = (Id) ar.get('assetId');
            caseCountsByAsset.put(assetId, (Integer) ar.get('cnt'));
            lastCaseDatesByAsset.put(assetId, (Datetime) ar.get('lastDt'));
        }

        // DESC: 집계 결과가 아니라 입력 집합 기준으로 돌아야 접수가 모두 지워진 장비도 0으로 되돌릴 수 있음
        List<Asset> assetsToUpdate = new List<Asset>();
        for (Id assetId : targetIds) {
            Datetime lastDt = lastCaseDatesByAsset.get(assetId);
            assetsToUpdate.add(new Asset(
                Id = assetId,
                TotalCaseCount__c = caseCountsByAsset.containsKey(assetId) ? caseCountsByAsset.get(assetId) : 0,
                LastCaseDate__c = (lastDt == null) ? null : lastDt.date()
            ));
        }

        // PERF: DML 1회
        // WARN: allOrNone = false. 일부 장비가 Validation Rule 등으로 실패해도 나머지는 저장하고 실패는 로그로 남김
        return countSuccess(Database.update(assetsToUpdate, false), 'recalculateAssetCaseStats');
    }

    /**
     * @description 메모리에 있는 접수들의 반복 고장 플래그를 계산해 세팅 (DML 없음)
     *              최근 N일(기준값), 취소 제외, 같은 장비 접수가 기준 횟수 이상이면 true
     *              D5 before insert 트리거에서도 그대로 재사용하기 위해 저장과 분리
     * @param cases 대상 접수 (AssetId, RepeatFailure__c 필드가 채워져 있어야 함)
     * @return 값이 실제로 바뀐 접수만 담은 리스트
     */
    public static List<Case> applyRepeatFailureFlags(List<Case> cases) {
        List<Case> changedCases = new List<Case>();
        if (cases == null || cases.isEmpty()) {
            return changedCases;
        }

        // DESC: Custom Metadata getInstance()는 SOQL 한도를 쓰지 않음
        Integer days = getSettingInt('RepeatFailureDays', DEFAULT_REPEAT_DAYS);
        Integer threshold = getSettingInt('RepeatFailureCount', DEFAULT_REPEAT_COUNT);
        // DESC: LAST_N_DAYS 리터럴에는 변수를 넣을 수 없어 기준 시각을 계산해 바인드
        Datetime since = System.now().addDays(-days);

        Set<Id> assetIds = new Set<Id>();
        for (Case c : cases) {
            if (c.AssetId != null) {
                assetIds.add(c.AssetId);
            }
        }

        Map<Id, Integer> recentCountsByAsset = new Map<Id, Integer>();
        if (!assetIds.isEmpty()) {
            // PERF: 집계 쿼리 1회
            for (AggregateResult ar : [
                SELECT AssetId assetId, COUNT(Id) cnt
                FROM Case
                WHERE AssetId IN :assetIds
                  AND CreatedDate >= :since
                  AND Status != :STATUS_CANCELED
                GROUP BY AssetId
            ]) {
                recentCountsByAsset.put((Id) ar.get('assetId'), (Integer) ar.get('cnt'));
            }
        }

        // WARN: before insert에서 호출하면 새 접수는 아직 DB에 없어 집계에 빠짐 → D5에서 이번 묶음의 같은 장비 건수를 더해야 정확
        for (Case c : cases) {
            Integer recentCount = (c.AssetId != null && recentCountsByAsset.containsKey(c.AssetId))
                ? recentCountsByAsset.get(c.AssetId) : 0;
            Boolean isRepeat = recentCount >= threshold;
            if (c.RepeatFailure__c != isRepeat) {
                c.RepeatFailure__c = isRepeat;
                changedCases.add(c);
            }
        }
        return changedCases;
    }

    /**
     * @description 이미 저장된 접수들의 반복 고장 플래그를 일괄로 다시 계산해 저장
     *              종결·취소된 접수는 대상에서 제외 (값을 바꾸지 않음)
     * @param caseIds 대상 접수 Id 집합
     * @return 플래그가 바뀌어 저장에 성공한 접수 수
     */
    public static Integer markRepeatFailures(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return 0;
        }
        // WARN: 종결·취소 접수는 Case.Closed_Lock 검증 규칙 때문에 수정하면 실패하므로 조회 단계에서 제외
        // PERF: 대상 조회 1회 + applyRepeatFailureFlags 안의 집계 1회
        List<Case> cases = [
            SELECT Id, AssetId, RepeatFailure__c
            FROM Case
            WHERE Id IN :caseIds
              AND Status NOT IN (:STATUS_CLOSED, :STATUS_CANCELED)
        ];
        List<Case> changedCases = applyRepeatFailureFlags(cases);
        if (changedCases.isEmpty()) {
            return 0;
        }
        // PERF: 바뀐 것만 DML 1회
        return countSuccess(Database.update(changedCases, false), 'markRepeatFailures');
    }

    // DESC: 기준값을 정수로 읽기. 레코드가 없으면 기본값
    private static Integer getSettingInt(String developerName, Integer defaultValue) {
        ServiceSetting__mdt setting = ServiceSetting__mdt.getInstance(developerName);
        return (setting == null || setting.Value__c == null) ? defaultValue : setting.Value__c.intValue();
    }

    // DESC: 부분 저장 결과에서 성공 건수를 세고 실패는 WARN 로그로 남김
    private static Integer countSuccess(List<Database.SaveResult> results, String context) {
        Integer successCount = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                successCount++;
                continue;
            }
            for (Database.Error err : result.getErrors()) {
                System.debug(LoggingLevel.WARN, context + ' 저장 실패: ' + err.getStatusCode() + ' ' + err.getMessage());
            }
        }
        return successCount;
    }
}