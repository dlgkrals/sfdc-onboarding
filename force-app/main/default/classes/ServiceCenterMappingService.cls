/**
 * @description 행정구역 코드 → 서비스센터 (ServiceCenterMapping__mdt)
 *              시군구 5자리를 먼저 찾고, 없으면 시도 2자리. 둘 다 없으면 null (사용자가 직접 선택)
 *              예: 4115010100(의정부) → 41150 → 경기북부, 4122010100(평택) → 41220 없음 → 41 → 경기남부·인천
 * @layer       Service
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (도로명주소 검색 시 사업장 센터 자동 지정)
 * ----------------------------------------------------------------------------
 * @see AddressSearchController, ServiceCenterMapping__mdt
 */
public with sharing class ServiceCenterMappingService {
  private static final Integer SIGUNGU_LENGTH = 5;
  private static final Integer SIDO_LENGTH = 2;

  // DESC: Custom Metadata getAll()은 SOQL 한도를 쓰지 않음. 트랜잭션 안에서 한 번만 만들어 재사용
  private static Map<String, String> centersByPrefix;

  /**
   * @description 행정구역 코드(10자리)로 서비스센터 API 값 찾기
   * @param adminDistrictCode 도로명주소 API의 admCd
   * @return 서비스센터 API 값 (예: GyeonggiNorth), 매핑 없으면 null
   */
  public static String resolveServiceCenter(String adminDistrictCode) {
    if (
      String.isBlank(adminDistrictCode) ||
      adminDistrictCode.length() < SIDO_LENGTH
    ) {
      return null;
    }
    Map<String, String> mapping = getCentersByPrefix();
    String sigungu = adminDistrictCode.left(SIGUNGU_LENGTH);
    if (
      adminDistrictCode.length() >= SIGUNGU_LENGTH &&
      mapping.containsKey(sigungu)
    ) {
      return mapping.get(sigungu);
    }
    return mapping.get(adminDistrictCode.left(SIDO_LENGTH));
  }

  private static Map<String, String> getCentersByPrefix() {
    if (centersByPrefix == null) {
      centersByPrefix = new Map<String, String>();
      for (
        ServiceCenterMapping__mdt row : ServiceCenterMapping__mdt.getAll()
          .values()
      ) {
        centersByPrefix.put(row.AdminDistrictPrefix__c, row.ServiceCenter__c);
      }
    }
    return centersByPrefix;
  }
}
