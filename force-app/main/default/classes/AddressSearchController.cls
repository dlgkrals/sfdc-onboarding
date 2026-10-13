/**
 * @description 도로명주소 검색 컨트롤러 (행정안전부 도로명주소 검색 API, 공통 LWC addressSearch에서 호출)
 *              검색어 → 도로명주소·우편번호·시도·시군구·행정구역 코드 목록
 *              승인키는 Named Credential HG_JusoApi → External Credential HG_JusoApi의 인증 매개변수 ConfmKey
 *              (코드·Git·로그에 키 없음. 요청 본문 merge field로만 들어감)
 * @layer       Controller
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (도로명주소 검색 API 연동)
 * ----------------------------------------------------------------------------
 * @see addressSearch (LWC), docs/interface_juso_address.md
 */
// DESC: 외부 API만 호출하고 Salesforce 데이터는 읽지 않음. 화면 컨트롤러 규칙대로 with sharing
public with sharing class AddressSearchController {
  public static final Integer PAGE_SIZE = 10;
  private static final Integer MIN_KEYWORD_LENGTH = 2;
  private static final Integer MAX_KEYWORD_LENGTH = 80;
  private static final Integer TIMEOUT_MS = 10000;
  private static final String ENDPOINT = 'callout:HG_JusoApi/addrlink/addrLinkApi.do';
  private static final String CODE_OK = '0';
  // DESC: 승인키 문제(미승인·만료·기간 외)는 사용자가 아니라 관리자가 고쳐야 하므로 별도 안내
  private static final Set<String> KEY_ERROR_CODES = new Set<String>{
    'E0001',
    'E0014',
    'E0015'
  };
  // DESC: API가 거부하는 SQL 예약어·특수문자 (E0013 방지). 공백으로 바꿔서 보냄
  private static final String BLOCKED_CHARS_PATTERN = '[%=><\\[\\]\\(\\);\'"\\\\]';

  /**
   * @description 주소 검색 (한 페이지 10건)
   * @param keyword    도로명·건물명·지번 등 2글자 이상
   * @param pageNumber 1부터
   * @return 결과 목록 + 전체 건수
   */
  @AuraEnabled(cacheable=true)
  public static AddressPage searchAddresses(
    String keyword,
    Integer pageNumber
  ) {
    String cleaned = cleanKeyword(keyword);
    if (cleaned.length() < MIN_KEYWORD_LENGTH) {
      throw newAuraException(System.Label.MSG_ADDRESS_KEYWORD_SHORT);
    }
    Integer page = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;

    HttpRequest request = new HttpRequest();
    request.setEndpoint(ENDPOINT);
    request.setMethod('POST');
    request.setTimeout(TIMEOUT_MS);
    request.setHeader(
      'Content-Type',
      'application/x-www-form-urlencoded; charset=UTF-8'
    );
    // WARN: 승인키는 merge field로만. 이 문자열을 로그로 남기지 말 것 (실행 시 키로 바뀜)
    request.setBody(
      'confmKey={!$Credential.HG_JusoApi.ConfmKey}' +
        '&resultType=json' +
        '&countPerPage=' +
        PAGE_SIZE +
        '&currentPage=' +
        page +
        '&keyword=' +
        EncodingUtil.urlEncode(cleaned, 'UTF-8')
    );

    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (Exception e) {
      // DESC: 시간 초과·연결 실패·Named Credential 권한 없음 등
      throw newAuraException(
        System.Label.MSG_ADDRESS_SERVER_ERROR + ' (' + e.getMessage() + ')'
      );
    }
    if (response.getStatusCode() != 200) {
      throw newAuraException(
        System.Label.MSG_ADDRESS_SERVER_ERROR +
          ' (HTTP ' +
          response.getStatusCode() +
          ')'
      );
    }
    return parseResponse(response.getBody(), page);
  }

  /**
   * @description 사업장 주소 저장 (상담원도 서비스센터 자동 반영, 직접 변경은 센터장·관리자만)
   * @param siteId  사업장 Id
   * @param address 선택·입력한 주소
   * @return 저장된 서비스센터 API 값 (바뀌지 않았으면 null)
   */
  @AuraEnabled
  public static String saveSiteAddress(
    Id siteId,
    CustomerSiteAddressService.SiteAddress address
  ) {
    try {
      return CustomerSiteAddressService.save(siteId, address);
    } catch (DmlException e) {
      // DESC: 검증 규칙 메시지만 화면에 (첫 번째 오류)
      throw newAuraException(e.getDmlMessage(0));
    } catch (Exception e) {
      throw newAuraException(e.getMessage());
    }
  }

  // DESC: 앞뒤 공백 제거, 거부 문자 제거, 길이 제한
  @TestVisible
  private static String cleanKeyword(String keyword) {
    if (String.isBlank(keyword)) {
      return '';
    }
    String cleaned = keyword.replaceAll(BLOCKED_CHARS_PATTERN, ' ')
      .normalizeSpace();
    return cleaned.left(MAX_KEYWORD_LENGTH);
  }

  // DESC: API는 오류여도 HTTP 200 + results.common.errorCode로 알려 줌
  private static AddressPage parseResponse(String body, Integer page) {
    JusoResponse parsed;
    try {
      parsed = (JusoResponse) JSON.deserialize(body, JusoResponse.class);
    } catch (Exception e) {
      throw newAuraException(System.Label.MSG_ADDRESS_SERVER_ERROR);
    }
    JusoCommon common = parsed?.results?.common;
    if (common == null) {
      throw newAuraException(System.Label.MSG_ADDRESS_SERVER_ERROR);
    }
    if (common.errorCode != CODE_OK) {
      if (KEY_ERROR_CODES.contains(common.errorCode)) {
        throw newAuraException(
          System.Label.MSG_ADDRESS_KEY_ERROR + ' (' + common.errorCode + ')'
        );
      }
      // DESC: 검색어 문제(E0005~E0013)는 API 메시지가 사용자에게 바로 도움이 됨
      throw newAuraException(
        common.errorMessage + ' (' + common.errorCode + ')'
      );
    }

    AddressPage result = new AddressPage();
    result.pageNumber = page;
    result.totalCount = String.isBlank(common.totalCount)
      ? 0
      : Integer.valueOf(common.totalCount);
    if (parsed.results.juso != null) {
      for (JusoItem item : parsed.results.juso) {
        result.rows.add(new AddressResult(item));
      }
    }
    return result;
  }

  private static AuraHandledException newAuraException(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  /**
   * @description 검색 결과 한 페이지
   */
  public class AddressPage {
    @AuraEnabled
    public List<AddressResult> rows = new List<AddressResult>();
    @AuraEnabled
    public Integer totalCount = 0;
    @AuraEnabled
    public Integer pageNumber = 1;
    @AuraEnabled
    public Integer pageSize = PAGE_SIZE;
  }

  /**
   * @description 주소 한 건 (화면이 레코드 필드에 그대로 옮길 수 있는 값)
   */
  public class AddressResult {
    @AuraEnabled
    public String roadAddress;
    @AuraEnabled
    public String roadAddressPart1;
    @AuraEnabled
    public String roadAddressNote;
    @AuraEnabled
    public String jibunAddress;
    @AuraEnabled
    public String postalCode;
    @AuraEnabled
    public String sido;
    @AuraEnabled
    public String sigungu;
    @AuraEnabled
    public String eupMyeonDong;
    @AuraEnabled
    public String adminDistrictCode;
    @AuraEnabled
    public String buildingName;
    // DESC: 행정구역 코드로 찾은 서비스센터 API 값 (매핑 없으면 null → 사용자가 선택)
    @AuraEnabled
    public String serviceCenter;

    AddressResult(JusoItem item) {
      this.roadAddress = item.roadAddr;
      this.roadAddressPart1 = item.roadAddrPart1;
      this.roadAddressNote = String.isBlank(item.roadAddrPart2)
        ? null
        : item.roadAddrPart2.trim();
      this.jibunAddress = item.jibunAddr;
      this.postalCode = item.zipNo;
      this.sido = item.siNm;
      this.sigungu = item.sggNm;
      this.eupMyeonDong = item.emdNm;
      this.adminDistrictCode = item.admCd;
      this.buildingName = item.bdNm;
      this.serviceCenter = ServiceCenterMappingService.resolveServiceCenter(
        item.admCd
      );
    }
  }

  // DESC: API 응답 구조 (JSON 이름 그대로)
  private class JusoResponse {
    JusoResults results;
  }
  private class JusoResults {
    JusoCommon common;
    List<JusoItem> juso;
  }
  private class JusoCommon {
    String errorCode;
    String errorMessage;
    String totalCount;
  }
  private class JusoItem {
    String roadAddr;
    String roadAddrPart1;
    String roadAddrPart2;
    String jibunAddr;
    String zipNo;
    String siNm;
    String sggNm;
    String emdNm;
    String admCd;
    String bdNm;
  }
}
