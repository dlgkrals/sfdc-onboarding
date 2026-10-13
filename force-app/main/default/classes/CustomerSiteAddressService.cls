/**
 * @description 사업장 주소 저장 + 서비스센터 반영 (빠른 작업 "주소 검색"에서 호출)
 *              - 주소 필드: 실행 사용자 권한(USER_MODE)으로 저장 → 사용자가 고칠 수 있는 필드만
 *              - 서비스센터: 센터 수정 권한이 있으면(센터장·관리자) 사용자가 고른 값을 USER_MODE로,
 *                없으면(상담원) 행정구역 코드로 서버가 다시 찾은 매핑 값을 SYSTEM_MODE로 반영 (매핑 없으면 그대로)
 *                → 상담원은 센터를 직접 고를 수 없고 Apex만 씀 (D6 원칙: 사용자가 못 고치는 값은 Apex가 시스템 모드로)
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (상담원 주소 저장 시 센터 자동 반영 결정)
 * ----------------------------------------------------------------------------
 * @see AddressSearchController.saveSiteAddress, ServiceCenterMappingService, addressEditAction
 */
public with sharing class CustomerSiteAddressService {
  // DESC: 사업장 참고항목 필드 길이 (RoadAddressNote__c Text(100))
  private static final Integer NOTE_MAX_LENGTH = 100;

  /**
   * @description 사업장 주소 저장
   * @param siteId  사업장 Id
   * @param address 화면에서 선택·입력한 주소 (serviceCenter는 센터 수정 권한이 있을 때만 사용)
   * @return 실제로 저장된 서비스센터 API 값 (바뀌지 않았으면 null)
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

    Boolean canEditCenter = Schema.SObjectType.CustomerSite__c.fields.ServiceCenter__c.isUpdateable();
    if (canEditCenter) {
      // DESC: 센터장·관리자 — 화면에서 고른 값(매핑으로 미리 채워진 값을 바꿨을 수도 있음)을 본인 권한으로
      if (String.isNotBlank(address.serviceCenter)) {
        site.ServiceCenter__c = address.serviceCenter;
      }
      Database.update(site, AccessLevel.USER_MODE);
      return site.ServiceCenter__c;
    }

    // DESC: 상담원 — 주소는 본인 권한으로 저장 (권한 없는 필드가 있으면 여기서 오류)
    Database.update(site, AccessLevel.USER_MODE);
    // DESC: 센터는 화면 값을 믿지 않고 서버에서 다시 매핑 → 시스템 모드로만 반영
    String mapped = ServiceCenterMappingService.resolveServiceCenter(
      address.adminDistrictCode
    );
    if (mapped == null) {
      return null;
    }
    Database.update(
      new CustomerSite__c(Id = siteId, ServiceCenter__c = mapped),
      AccessLevel.SYSTEM_MODE
    );
    return mapped;
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
    @AuraEnabled
    public String serviceCenter { get; set; }
  }
}
