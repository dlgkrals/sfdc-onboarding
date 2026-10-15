/**
 * @description TriggerHandler(트리거 핸들러 공통 부모) 테스트
 *              실제 트리거는 선언한 이벤트를 모두 하위 핸들러가 재정의해 부모 기본 동작이 실행되지 않음
 *              → 테스트용 하위 클래스로 기본 동작(아무것도 안 함)·트리거 밖 실행·스위치 대체값을 직접 확인
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (커버리지 보강: 부모 기본 동작·트리거 밖 실행)
 * ----------------------------------------------------------------------------
 * @see TriggerHandler, CaseTriggerHandlerTest
 */
@isTest
private class TriggerHandlerTest {
  // DESC: 이벤트를 하나도 재정의하지 않은 핸들러 — 부모 기본 동작만 사용
  private class PlainHandler extends TriggerHandler {
    Integer dispatched = 0;

    void runAllEvents() {
      beforeInsert();
      beforeUpdate();
      beforeDelete();
      afterInsert();
      afterUpdate();
      afterDelete();
      afterUndelete();
      dispatched = 7;
    }

    String handlerName() {
      return getHandlerName();
    }
  }

  // 정상: 재정의하지 않은 이벤트는 아무것도 하지 않음(예외·DML 없음), 핸들러 이름은 클래스 이름
  @isTest
  static void normalDefaultEventsDoNothing() {
    PlainHandler handler = new PlainHandler();
    Integer dmlBefore = Limits.getDmlStatements();

    Test.startTest();
    handler.runAllEvents();
    Test.stopTest();

    Assert.areEqual(7, handler.dispatched);
    Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'DML 없음');
    Assert.isTrue(
      handler.handlerName().endsWith('PlainHandler'),
      '핸들러 이름: ' + handler.handlerName()
    );
  }

  // 불허: 트리거 밖(예: 익명 Apex·테스트)에서 run()을 부르면 바로 끝남
  @isTest
  static void rejectRunOutsideTrigger() {
    PlainHandler handler = new PlainHandler();

    Test.startTest();
    handler.run();
    Test.stopTest();

    Assert.areEqual(0, handler.dispatched, '트리거 밖에서는 분기하지 않음');
  }

  // 정상: 스위치 — 테스트 대체값이 우선, 레코드가 없는 오브젝트는 활성
  @isTest
  static void normalSwitchOverrideAndDefault() {
    Test.startTest();
    TriggerHandler.activeOverridesByObject.put('Case', false);
    Boolean caseActive = TriggerHandler.isTriggerActive('Case');
    Boolean unknownActive = TriggerHandler.isTriggerActive(
      'HG_NoSettingObject__c'
    );
    Test.stopTest();

    Assert.isFalse(caseActive, '대체값 false가 우선');
    Assert.isTrue(unknownActive, '설정 레코드가 없으면 활성');
  }
}
