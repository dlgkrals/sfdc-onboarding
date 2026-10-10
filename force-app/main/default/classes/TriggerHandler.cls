/**
 * @description 트리거 핸들러 공통 부모 (1 오브젝트 1 트리거 + 핸들러 패턴)
 *              1) 오브젝트별 비활성화 스위치(TriggerSetting__mdt) 확인
 *              2) Trigger.operationType으로 이벤트별 가상 메서드 분기
 *              3) 테스트·스크립트용 정적 우회(bypassedHandlers)
 *              4) 재귀 방지: 같은 트랜잭션에서 같은 레코드를 같은 단계로 두 번 처리하지 않게 함
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-08
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-08    Edwin     최초 작성 (D5 실습: 핸들러 패턴 공통 부모)
 * ----------------------------------------------------------------------------
 * @see CaseTriggerHandler, ProductConsumedTriggerHandler, TriggerSetting__mdt
 */
public virtual class TriggerHandler {

    // DESC: 핸들러 클래스 이름을 넣으면 그 핸들러는 실행되지 않음 (데이터 이관 스크립트·테스트용)
    public static Set<String> bypassedHandlers = new Set<String>();

    // DESC: 테스트에서는 Custom Metadata 레코드를 넣을 수 없으므로 스위치 값을 대신 지정
    @TestVisible
    private static Map<String, Boolean> activeOverridesByObject = new Map<String, Boolean>();

    // DESC: 재귀 방지용. 키 = 핸들러 이름 + ':' + 단계, 값 = 이미 처리한 레코드 Id
    private static Map<String, Set<Id>> processedIdsByKey = new Map<String, Set<Id>>();

    /**
     * @description 트리거 본문에서 호출하는 진입점. 스위치·우회 확인 후 이벤트별 메서드로 분기
     */
    public void run() {
        if (!Trigger.isExecuting) {
            return;
        }
        if (bypassedHandlers.contains(getHandlerName()) || !isTriggerActive(getSObjectName())) {
            return;
        }
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeInsert();
            }
            when BEFORE_UPDATE {
                beforeUpdate();
            }
            when BEFORE_DELETE {
                beforeDelete();
            }
            when AFTER_INSERT {
                afterInsert();
            }
            when AFTER_UPDATE {
                afterUpdate();
            }
            when AFTER_DELETE {
                afterDelete();
            }
            when AFTER_UNDELETE {
                afterUndelete();
            }
        }
    }

    // DESC: 하위 핸들러가 필요한 이벤트만 재정의
    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}

    /**
     * @description 오브젝트의 트리거 스위치 확인. 레코드가 없으면 활성으로 간주
     * @param sObjectName 오브젝트 API 이름 (= TriggerSetting__mdt.DeveloperName)
     * @return 실행해야 하면 true
     */
    public static Boolean isTriggerActive(String sObjectName) {
        if (activeOverridesByObject.containsKey(sObjectName)) {
            return activeOverridesByObject.get(sObjectName);
        }
        // DESC: Custom Metadata getInstance()는 SOQL 한도를 쓰지 않음
        TriggerSetting__mdt setting = TriggerSetting__mdt.getInstance(sObjectName);
        return setting == null || setting.IsActive__c;
    }

    /**
     * @description 아직 이 단계에서 처리하지 않은 레코드만 돌려주고, 돌려준 레코드는 처리됨으로 기록
     *              Id가 없는 레코드(before insert)는 항상 포함
     * @param records 후보 레코드
     * @param stage   처리 단계 이름 (예: 'afterUpdate')
     * @return 처리해야 할 레코드
     */
    protected List<SObject> filterUnprocessed(List<SObject> records, String stage) {
        String key = getHandlerName() + ':' + stage;
        if (!processedIdsByKey.containsKey(key)) {
            processedIdsByKey.put(key, new Set<Id>());
        }
        Set<Id> processedIds = processedIdsByKey.get(key);
        List<SObject> result = new List<SObject>();
        for (SObject record : records) {
            if (record.Id == null) {
                result.add(record);
            } else if (!processedIds.contains(record.Id)) {
                processedIds.add(record.Id);
                result.add(record);
            }
        }
        return result;
    }

    // DESC: 'CaseTriggerHandler:[...]' 형태의 문자열에서 클래스 이름만 추출
    protected String getHandlerName() {
        return String.valueOf(this).substringBefore(':');
    }

    // DESC: 삭제 이벤트는 Trigger.new가 없으므로 Trigger.old에서 오브젝트 이름을 얻음
    private String getSObjectName() {
        List<SObject> records = (Trigger.new != null) ? Trigger.new : Trigger.old;
        return records.getSObjectType().getDescribe().getName();
    }
}