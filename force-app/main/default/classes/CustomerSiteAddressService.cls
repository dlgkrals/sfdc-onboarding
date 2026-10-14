/**
 * @description 사업장 주소 저장 + 서비스센터 완전 자동 지정
 *              - 서비스센터는 사람이 고르지 않음: 누가 등록·수정하든 행정구역 코드(주소 검색 결과) → ServiceCenterMapping__mdt로
 *                트리거(before insert·update)가 채움. 트리거 안의 값 지정은 필드 권한과 무관 → 센터는 모든 권한 집합에서 읽기 전용
 *              - 주소 검색 없이 주소를 바꾸거나(행정구역 코드 없음·주소만 바뀜) 매핑 없는 주소면 저장 거부
 *              - 센터를 직접 다른 값으로 바꾸려 하면 거부 (예외 지역은 관리자가 매핑을 고친 뒤 d8_site_center_reapply.apex)
 *              - 주소 저장(빠른 작업 "주소 검색"): 주소 필드만 실행 사용자 권한(USER_MODE)으로 저장, 센터는 트리거가 채움
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (상담원 주소 저장 시 센터 자동 반영 결정)
 * 1.1    2026-10-14    Edwin     센터 완전 자동(applyServiceCenters, 트리거), 센터장·관리자 직접 선택 삭제 (D8 결정)
 * ----------------------------------------------------------------------------
 * @see CustomerSiteTriggerHandler, AddressSearchController.saveSiteAddress, ServiceCenterMappingService, addressEditAction, customerSiteNew
 */
public with sharing class CustomerSiteAddressService {
  // DESC: 사업장 참고항목 필드 길이 (RoadAddressNote__c Text(100))
  private static final Integer NOTE_MAX_LENGTH = 100;

  // DESC: 주소 검색이 채우는 필드. 이 중 하나라도 바뀌었는데 행정구역 코드가 그대로면 손으로 고친 주소로 봄
  //       상세주소(DetailAddress__c)·참고항목은 센터와 무관해 자유롭게 고칠 수 있음
  private static final List<Schema.SObjectField> SEARCHED_FIELDS = new List<Schema.SObjectField>{
    CustomerSite__c.RoadAddress__c,
    CustomerSite__c.PostalCode__c,
    CustomerSite__c.Sido__c,
    CustomerSite__c.Sigungu__c
  };

  /**
   * @description 서비스센터 자동 지정 (트리거 before insert·update에서 호출, 벌크)
   * @param sites    Trigger.new
   * @param oldById  Trigger.oldMap (insert는 null)
   */
  public static void applyServiceCenters(
    List<CustomerSite__c> sites,
    Map<Id, CustomerSite__c> oldById
  ) {
    for (CustomerSite__c site : sites) {
      CustomerSite__c old = oldById == null ? null : oldById.get(site.Id);
      if (String.isBlank(site.AdminDistrictCode__c)) {
        site.addError(System.Label.MSG_ADDRESS_SEARCH_REQUIRED);
        continue;
      }
      if (old != null && isManualAddressEdit(site, old)) {
        site.addError(System.Label.MSG_ADDRESS_SEARCH_REQUIRED);
        continue;
      }
      // PERF: 매핑은 getAll() 캐시라 루프 안에서 불러도 SOQL 없음
      String mapped = ServiceCenterMappingService.resolveServiceCenter(
        site.AdminDistrictCode__c
      );
      if (mapped == null) {
        site.addError(System.Label.MSG_CENTER_NO_MAPPING);
        continue;
      }
      // DESC: 센터를 직접 다른 값으로 바꾸려는 경우(관리자 API 포함) 거부. 주소가 같고 센터만 바뀐 경우
      if (
        old != null &&
        site.ServiceCenter__c != old.ServiceCenter__c &&
        site.ServiceCenter__c != mapped &&
        site.AdminDistrictCode__c == old.AdminDistrictCode__c
      ) {
        site.ServiceCenter__c.addError(System.Label.MSG_CENTER_AUTO_ONLY);
        continue;
      }
      site.ServiceCenter__c = mapped;
    }
  }

  // DESC: 주소 검색 결과 필드가 바뀌었는데 행정구역 코드는 그대로 → 주소 검색을 거치지 않은 수정
  private static Boolean isManualAddressEdit(
    CustomerSite__c site,
    CustomerSite__c old
  ) {
    if (site.AdminDistrictCode__c != old.AdminDistrictCode__c) {
      return false;
    }
    for (Schema.SObjectField field : SEARCHED_FIELDS) {
      if (site.get(field) != old.get(field)) {
        return true;
      }
    }
    return false;
  }

  /**
   * @description 사업장 주소 저장 (빠른 작업 "주소 검색"). 센터는 트리거가 주소 기준으로 채움
   * @param siteId  사업장 Id
   * @param address 화면에서 선택·입력한 주소 (serviceCenter 값은 쓰지 않음)
   * @return 저장된 서비스센터 API 값
   */
  public static String save(Id siteId, SiteAddress address) {
    if (
      siteId == null ||
      address == null ||
      String.isBlank(address.roadAddress)
    ) {
      throw new IllegalArgumentException('사업장과 주소가 필요합니다.');
    }
    CustomerSite__c site = new CustomerSite__c(
      Id = siteId,
      RoadAddress__c = address.roadAddress,
      RoadAddressNote__c = String.isBlank(address.roadAddressNote)
        ? null
        : address.roadAddressNote.left(NOTE_MAX_LENGTH),
      DetailAddress__c = String.isBlank(address.detailAddress)
        ? null
        : address.detailAddress.trim(),
      PostalCode__c = address.postalCode,
      Sido__c = address.sido,
      Sigungu__c = address.sigungu,
      AdminDistrictCode__c = address.adminDistrictCode
    );
    // DESC: 주소는 본인 권한으로 저장 (권한 없는 필드가 있으면 오류). 센터는 트리거가 매핑으로 채움
    Database.update(site, AccessLevel.USER_MODE);
    return [
      SELECT ServiceCenter__c
      FROM CustomerSite__c
      WHERE Id = :siteId
      WITH USER_MODE
    ]
    .ServiceCenter__c;
  }

  /**
   * @description 화면에서 넘어오는 사업장 주소 (LWC → Apex 인자)
   */
  public class SiteAddress {
    @AuraEnabled
    public String roadAddress { get; set; }
    @AuraEnabled
    public String roadAddressNote { get; set; }
    @AuraEnabled
    public String detailAddress { get; set; }
    @AuraEnabled
    public String postalCode { get; set; }
    @AuraEnabled
    public String sido { get; set; }
    @AuraEnabled
    public String sigungu { get; set; }
    @AuraEnabled
    public String adminDistrictCode { get; set; }
    // DESC: 예전 화면 호환용. 서버는 쓰지 않음 (센터는 매핑으로만)
    @AuraEnabled
    public String serviceCenter { get; set; }
  }
}
