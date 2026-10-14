/**
 * @description 사업장(CustomerSite__c) 트리거 핸들러 — 서비스센터 완전 자동 지정
 *              before insert·update: 행정구역 코드(주소 검색 결과) → ServiceCenterMapping__mdt로 서비스센터 채움
 *              주소 검색 없이 저장·매핑 없는 주소·센터 직접 변경은 거부 (CustomerSiteAddressService.applyServiceCenters)
 * @layer       TriggerHandler
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 서비스센터 완전 자동)
 * ----------------------------------------------------------------------------
 * @see CustomerSiteTrigger, CustomerSiteAddressService, TriggerHandler
 */
// NOTE: before 단계 값 지정이라 추가 저장 없음. 필드 권한(읽기 전용)과 무관하게 채워짐
public with sharing class CustomerSiteTriggerHandler extends TriggerHandler {
  protected override void beforeInsert() {
    CustomerSiteAddressService.applyServiceCenters(
      (List<CustomerSite__c>) Trigger.new,
      null
    );
  }

  protected override void beforeUpdate() {
    CustomerSiteAddressService.applyServiceCenters(
      (List<CustomerSite__c>) Trigger.new,
      (Map<Id, CustomerSite__c>) Trigger.oldMap
    );
  }
}
