/**
 * @description AddressSearchController 테스트 (HttpCalloutMock: 정상·결과 없음·API 오류 코드·서버 오류)
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (도로명주소 검색 API 연동)
 * ----------------------------------------------------------------------------
 * @see AddressSearchController
 */
@isTest
private class AddressSearchControllerTest {
  private static final String OK_BODY =
    '{"results":{"common":{"errorMessage":"정상","countPerPage":"10","totalCount":"2","errorCode":"0","currentPage":"1"},' +
    '"juso":[' +
    '{"roadAddr":"경기도 평택시 평택로 32 (평택동)","roadAddrPart1":"경기도 평택시 평택로 32","roadAddrPart2":" (평택동)",' +
    '"jibunAddr":"경기도 평택시 평택동 185-1","zipNo":"17901","siNm":"경기도","sggNm":"평택시","emdNm":"평택동","admCd":"4122010100","bdNm":"평택시청"},' +
    '{"roadAddr":"경기도 평택시 평택로 34","roadAddrPart1":"경기도 평택시 평택로 34","roadAddrPart2":"",' +
    '"jibunAddr":"경기도 평택시 평택동 186","zipNo":"17901","siNm":"경기도","sggNm":"평택시","emdNm":"평택동","admCd":"4122010100","bdNm":""}' +
    ']}}';
  private static final String EMPTY_BODY = '{"results":{"common":{"errorMessage":"정상","totalCount":"0","errorCode":"0","currentPage":"1"},"juso":[]}}';

  // DESC: 정해 둔 상태 코드·본문을 돌려주고, 보낸 요청을 기록하는 가짜 API
  private class JusoMock implements HttpCalloutMock {
    Integer statusCode;
    String body;
    Boolean throwError = false;
    HttpRequest lastRequest;

    JusoMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      lastRequest = request;
      if (throwError) {
        throw new CalloutException('Read timed out');
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setHeader('Content-Type', 'application/json');
      response.setBody(body);
      return response;
    }
  }

  private static String errorBody(String code, String message) {
    return '{"results":{"common":{"errorMessage":"' +
      message +
      '","totalCount":"0","errorCode":"' +
      code +
      '"},"juso":null}}';
  }

  private static String searchExpectingError(String keyword) {
    try {
      AddressSearchController.searchAddresses(keyword, 1);
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
    Assert.fail('오류가 나야 함');
    return null;
  }

  // 정상: 결과 2건 → 화면에 넘길 값으로 변환, 요청은 Named Credential·merge field·인코딩된 검색어
  @isTest
  static void normalReturnsMappedAddresses() {
    JusoMock mock = new JusoMock(200, OK_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AddressSearchController.AddressPage page = AddressSearchController.searchAddresses(
      '  평택로 32 ',
      1
    );
    Test.stopTest();

    Assert.areEqual(2, page.totalCount, '전체 건수');
    Assert.areEqual(2, page.rows.size(), '행 2건');
    AddressSearchController.AddressResult first = page.rows[0];
    Assert.areEqual(
      '경기도 평택시 평택로 32 (평택동)',
      first.roadAddress,
      '도로명주소'
    );
    Assert.areEqual(
      '경기도 평택시 평택로 32',
      first.roadAddressPart1,
      '도로명주소(참고항목 제외)'
    );
    Assert.areEqual('(평택동)', first.roadAddressNote, '참고항목');
    Assert.areEqual('17901', first.postalCode, '우편번호');
    Assert.areEqual('경기도', first.sido, '시도');
    Assert.areEqual('평택시', first.sigungu, '시군구');
    Assert.areEqual('4122010100', first.adminDistrictCode, '행정구역 코드');
    Assert.areEqual(
      'GyeonggiSouth',
      first.serviceCenter,
      '행정구역 코드로 찾은 서비스센터'
    );
    Assert.isNull(page.rows[1].roadAddressNote, '참고항목 없으면 null');

    Assert.areEqual(
      'callout:HG_JusoApi/addrlink/addrLinkApi.do',
      mock.lastRequest.getEndpoint(),
      'Named Credential 사용'
    );
    Assert.areEqual('POST', mock.lastRequest.getMethod(), 'POST');
    String body = mock.lastRequest.getBody();
    Assert.isTrue(
      body.contains('confmKey={!$Credential.HG_JusoApi.ConfmKey}'),
      '승인키는 merge field로만'
    );
    Assert.isTrue(
      body.contains('keyword=' + EncodingUtil.urlEncode('평택로 32', 'UTF-8')),
      '앞뒤 공백 제거 후 인코딩'
    );
    Assert.isTrue(body.contains('resultType=json'), 'JSON 응답 요청');
  }

  // 정상: 결과 없음 → 빈 목록 (오류 아님)
  @isTest
  static void normalNoResultReturnsEmpty() {
    Test.setMock(HttpCalloutMock.class, new JusoMock(200, EMPTY_BODY));

    Test.startTest();
    AddressSearchController.AddressPage page = AddressSearchController.searchAddresses(
      '없는도로명',
      1
    );
    Test.stopTest();

    Assert.areEqual(0, page.totalCount, '0건');
    Assert.isTrue(page.rows.isEmpty(), '행 없음');
  }

  // 정상: 상담원 사용자로 실행 (화면 실제 사용자)
  @isTest
  static void normalCallCenterUserSearches() {
    User callCenter;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      callCenter = TestDataFactory.createUser('HG_CallCenter', false);
    }
    Test.setMock(HttpCalloutMock.class, new JusoMock(200, OK_BODY));
    AddressSearchController.AddressPage page;

    Test.startTest();
    System.runAs(callCenter) {
      page = AddressSearchController.searchAddresses('평택로', 2);
    }
    Test.stopTest();

    Assert.areEqual(2, page.rows.size(), '상담원도 검색 가능');
    Assert.areEqual(2, page.pageNumber, '요청한 페이지');
  }

  // 정상: 거부 문자 제거·길이 제한
  @isTest
  static void normalKeywordCleaned() {
    Assert.areEqual(
      '평택로 32',
      AddressSearchController.cleanKeyword('평택로%32;'),
      '특수문자는 공백으로'
    );
    Assert.areEqual(
      80,
      AddressSearchController.cleanKeyword('가'.repeat(100)).length(),
      '80자 제한'
    );
    Assert.areEqual(
      '',
      AddressSearchController.cleanKeyword(null),
      'null은 빈 문자열'
    );
  }

  // 불허: 2글자 미만 → API를 부르지 않고 안내
  @isTest
  static void rejectShortKeywordWithoutCallout() {
    JusoMock mock = new JusoMock(200, OK_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String message = searchExpectingError(' 평 ');
    Test.stopTest();

    Assert.areEqual(
      System.Label.MSG_ADDRESS_KEYWORD_SHORT,
      message,
      '짧은 검색어 안내'
    );
    Assert.isNull(mock.lastRequest, 'API 호출 없음');
  }

  // 불허: 승인키 오류(E0001)·만료(E0014) → 관리자 문의 안내
  @isTest
  static void rejectKeyErrorsShowAdminMessage() {
    Test.startTest();
    Test.setMock(
      HttpCalloutMock.class,
      new JusoMock(200, errorBody('E0001', '승인되지 않은 KEY 입니다.'))
    );
    String notApproved = searchExpectingError('평택로');
    Test.setMock(
      HttpCalloutMock.class,
      new JusoMock(
        200,
        errorBody(
          'E0014',
          '개발승인키 기간이 만료되어 서비스를 이용하실 수 없습니다.'
        )
      )
    );
    String expired = searchExpectingError('평택로');
    Test.stopTest();

    Assert.isTrue(
      notApproved.startsWith(System.Label.MSG_ADDRESS_KEY_ERROR),
      '미승인 키 안내'
    );
    Assert.isTrue(notApproved.contains('E0001'), '오류 코드 포함');
    Assert.isTrue(expired.contains('E0014'), '만료 코드 포함');
  }

  // 불허: 검색어 오류(E0006 등) → API 메시지 그대로 사용자에게
  @isTest
  static void rejectKeywordErrorShowsApiMessage() {
    Test.setMock(
      HttpCalloutMock.class,
      new JusoMock(
        200,
        errorBody('E0006', '주소를 상세히 입력해 주시기 바랍니다.')
      )
    );

    Test.startTest();
    String message = searchExpectingError('경기도');
    Test.stopTest();

    Assert.isTrue(message.contains('주소를 상세히 입력해'), 'API 메시지');
    Assert.isTrue(message.contains('E0006'), '오류 코드');
  }

  // 불허: 서버 오류(HTTP 500)·연결 실패·응답 형식 오류 → 서버 오류 안내
  @isTest
  static void rejectServerErrors() {
    JusoMock failing = new JusoMock(200, OK_BODY);
    failing.throwError = true;

    Test.startTest();
    Test.setMock(
      HttpCalloutMock.class,
      new JusoMock(500, 'Internal Server Error')
    );
    String http500 = searchExpectingError('평택로');
    Test.setMock(HttpCalloutMock.class, failing);
    String timeout = searchExpectingError('평택로');
    Test.setMock(
      HttpCalloutMock.class,
      new JusoMock(200, '<html>점검 중</html>')
    );
    String notJson = searchExpectingError('평택로');
    Test.setMock(HttpCalloutMock.class, new JusoMock(200, '{"results":{}}'));
    String noCommon = searchExpectingError('평택로');
    Test.stopTest();

    Assert.isTrue(
      http500.startsWith(System.Label.MSG_ADDRESS_SERVER_ERROR),
      'HTTP 오류'
    );
    Assert.isTrue(http500.contains('500'), '상태 코드 포함');
    Assert.isTrue(
      timeout.startsWith(System.Label.MSG_ADDRESS_SERVER_ERROR),
      '연결 실패'
    );
    Assert.areEqual(
      System.Label.MSG_ADDRESS_SERVER_ERROR,
      notJson,
      'JSON 아님'
    );
    Assert.areEqual(
      System.Label.MSG_ADDRESS_SERVER_ERROR,
      noCommon,
      'common 없음'
    );
  }
}
