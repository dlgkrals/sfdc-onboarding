/**
 * @description ErpCallLogger 테스트 — ERP 통신 기록(ErpCallLog__c): 보내기(IF-03)·가져오기(IF-02-R, 0건·실패)·받기 푸시(IF-02-P), 긴 본문 자르기
 *              HttpCalloutMock으로 ERP 응답을 흉내 냄. 헤더(토큰)는 기록하지 않는지 확인
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-19
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-19    Edwin     최초 작성 (모의 발표 피드백: ERP 통신 기록)
 * ----------------------------------------------------------------------------
 * @see ErpCallLogger, ErpInventoryService, ErpStockSyncService, ErpMovementResource
 */
@isTest
private class ErpCallLoggerTest {
  private static final String VAN_CODE = 'VAN-LOG';

  // DESC: 보내기 응답 — 첫 건 OK, 나머지 거부 / 또는 HTTP 오류
  private class ConsumeMock implements HttpCalloutMock {
    Integer statusCode = 200;

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      if (statusCode != 200) {
        response.setBody('{"error":"MAINTENANCE","message":"점검 중"}');
        return response;
      }
      List<Object> items = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
          request.getBody()
        ))
        .get('items');
      List<Object> results = new List<Object>();
      for (Integer i = 0; i < items.size(); i++) {
        String refId = String.valueOf(
          ((Map<String, Object>) items[i]).get('refId')
        );
        results.add(
          i == 0
            ? new Map<String, Object>{
                'refId' => refId,
                'status' => 'OK',
                'remainingQty' => 9
              }
            : new Map<String, Object>{
                'refId' => refId,
                'status' => 'REJECTED',
                'code' => 'INSUFFICIENT_STOCK',
                'message' => '재고가 부족합니다.'
              }
        );
      }
      response.setBody(
        JSON.serialize(new Map<String, Object>{ 'results' => results })
      );
      return response;
    }
  }

  // DESC: 가져오기 응답 — 0건 / HTTP 오류
  private class MovementsMock implements HttpCalloutMock {
    Integer statusCode = 200;

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(
        statusCode == 200
          ? '{"items":[],"lastId":5,"hasMore":false,"latestId":5}'
          : '{"error":"MAINTENANCE"}'
      );
      return response;
    }
  }

  @TestSetup
  static void setupData() {
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-LOG-',
      1
    );
    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    Map<String, ProductItem> itemsByFamily = TestDataFactory.createVanStock(
      TestDataFactory.createProducts(),
      300
    );
    update new Schema.Location(
      Id = itemsByFamily.values()[0].LocationId,
      ErpLocationCode__c = VAN_CODE
    );
  }

  private static Set<Id> insertParts(Integer count) {
    WorkOrder wo = [SELECT Id FROM WorkOrder LIMIT 1];
    ProductItem item = [
      SELECT Id
      FROM ProductItem
      WHERE Product2.Family = 'General'
      LIMIT 1
    ];
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < count; i++) {
      parts.add(
        new ProductConsumed(
          WorkOrderId = wo.Id,
          ProductItemId = item.Id,
          QuantityConsumed = 1
        )
      );
    }
    insert parts;
    return new Map<Id, ProductConsumed>(parts).keySet();
  }

  private static ErpCallLog__c onlyLog() {
    List<ErpCallLog__c> logs = [
      SELECT
        Direction__c,
        Interface__c,
        Source__c,
        Endpoint__c,
        HttpMethod__c,
        RequestBody__c,
        ResponseBody__c,
        StatusCode__c,
        DurationMs__c,
        ItemCount__c,
        Result__c,
        ErrorMessage__c,
        RelatedNumbers__c,
        RefIds__c,
        Truncated__c
      FROM ErpCallLog__c
    ];
    Assert.areEqual(1, logs.size(), '호출 1번 = 기록 1줄');
    return logs[0];
  }

  // 정상: 보내기(IF-03) 2건 묶음 → 기록 1줄, 요청·응답 JSON, 거부 포함 + 첫 거부 사유, 관련 출동 번호·refId
  @isTest
  static void normalOutboundLoggedWithRejection() {
    Set<Id> ids = insertParts(2);
    Test.setMock(HttpCalloutMock.class, new ConsumeMock());

    Test.startTest();
    ErpInventoryService.save(
      ErpInventoryService.buildConsumedUpdates(ids, false)
    );
    Test.stopTest();

    ErpCallLog__c log = onlyLog();
    Assert.areEqual(ErpCallLogger.DIRECTION_OUTBOUND, log.Direction__c);
    Assert.areEqual('IF-03', log.Interface__c);
    Assert.areEqual('POST', log.HttpMethod__c);
    Assert.areEqual(200, log.StatusCode__c);
    Assert.areEqual(2, log.ItemCount__c);
    Assert.areEqual(ErpCallLogger.RESULT_REJECTED, log.Result__c);
    Assert.isTrue(log.ErrorMessage__c.startsWith('[INSUFFICIENT_STOCK]'));
    Assert.isTrue(log.RequestBody__c.contains('"items"'), '요청 JSON');
    Assert.isTrue(log.ResponseBody__c.contains('REJECTED'), '응답 JSON');
    Assert.isNotNull(log.RelatedNumbers__c, '출동 번호');
    for (Id id : ids) {
      Assert.isTrue(log.RefIds__c.contains(String.valueOf(id)), 'refId');
    }
    Assert.isNotNull(log.DurationMs__c);
  }

  // 불허: 보내기 HTTP 503 → 실패 기록(상태 503, 응답 본문), 본 처리(사용 부품 실패 상태 저장)는 그대로
  @isTest
  static void rejectOutboundHttpErrorLogged() {
    Set<Id> ids = insertParts(1);
    ConsumeMock mock = new ConsumeMock();
    mock.statusCode = 503;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    ErpInventoryService.save(
      ErpInventoryService.buildConsumedUpdates(ids, false)
    );
    Test.stopTest();

    ErpCallLog__c log = onlyLog();
    Assert.areEqual(ErpCallLogger.RESULT_FAILED, log.Result__c);
    Assert.areEqual(503, log.StatusCode__c);
    Assert.isTrue(log.ResponseBody__c.contains('MAINTENANCE'));
    Assert.areEqual(
      ErpInventoryService.STATUS_FAILED,
      [SELECT ErpSyncStatus__c FROM ProductConsumed WHERE Id IN :ids]
      .ErpSyncStatus__c,
      '사용 부품은 실패로 저장(기록과 무관)'
    );
  }

  // 정상: 가져오기(IF-02-R) 0건 호출도 기록 1줄 (GET, 조회 조건, 건수 0, 성공)
  @isTest
  static void normalPullZeroItemsLogged() {
    ErpStockSyncService.saveLastMovementId(5);
    Test.setMock(HttpCalloutMock.class, new MovementsMock());

    Test.startTest();
    ErpStockSyncService.syncNextPage();
    Test.stopTest();

    ErpCallLog__c log = onlyLog();
    Assert.areEqual(ErpCallLogger.DIRECTION_PULL, log.Direction__c);
    Assert.areEqual('IF-02-R', log.Interface__c);
    Assert.areEqual('GET', log.HttpMethod__c);
    Assert.areEqual(0, log.ItemCount__c);
    Assert.areEqual(ErpCallLogger.RESULT_SUCCESS, log.Result__c);
    Assert.isTrue(log.RequestBody__c.contains('"after":5'));
  }

  // 불허: 가져오기 HTTP 503 → 예외가 나도 실패 기록은 남음
  @isTest
  static void rejectPullHttpErrorLogged() {
    ErpStockSyncService.saveLastMovementId(5);
    MovementsMock mock = new MovementsMock();
    mock.statusCode = 503;
    Test.setMock(HttpCalloutMock.class, mock);
    String failure;

    Test.startTest();
    try {
      ErpStockSyncService.syncNextPage();
    } catch (Exception e) {
      failure = e.getMessage();
    }
    Test.stopTest();

    Assert.isTrue(failure.startsWith('[HTTP_503]'));
    ErpCallLog__c log = onlyLog();
    Assert.areEqual(ErpCallLogger.RESULT_FAILED, log.Result__c);
    Assert.areEqual(503, log.StatusCode__c);
  }

  // 정상: 받기 푸시(IF-02-P) → 받은 본문·돌려준 본문 기록, 헤더(키·토큰)는 기록 안 함, 없는 코드는 거부 포함
  @isTest
  static void normalPushLoggedWithoutToken() {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/hg/erp/movements';
    req.httpMethod = 'POST';
    req.addHeader('x-api-key', 'SECRET-TOKEN');
    req.requestBody = Blob.valueOf(
      '{"movements":[{"id":999,"type":"RECEIPT","origin":"ERP","locationCode":"NOPE","partCode":"NOPE",' +
      '"quantityChange":1,"unit":"Each","createdAt":"2026-10-19T00:00:00Z"}]}'
    );
    RestContext.request = req;
    RestContext.response = new RestResponse();

    Test.startTest();
    ErpMovementResource.receive();
    Test.stopTest();

    ErpCallLog__c log = onlyLog();
    Assert.areEqual(ErpCallLogger.DIRECTION_PUSH, log.Direction__c);
    Assert.areEqual('IF-02-P', log.Interface__c);
    Assert.areEqual('ApexRest', log.Source__c);
    Assert.areEqual(200, log.StatusCode__c);
    Assert.areEqual(1, log.ItemCount__c);
    Assert.areEqual(ErpCallLogger.RESULT_REJECTED, log.Result__c);
    Assert.isTrue(log.RequestBody__c.contains('"id":999'));
    Assert.isTrue(log.RefIds__c.contains('999'));
    Assert.isFalse(
      (log.RequestBody__c + log.ResponseBody__c).contains('SECRET-TOKEN'),
      '토큰 기록 안 함'
    );
  }

  // 경계: 한도를 넘는 본문은 잘라 표시하고 "잘림" 체크
  @isTest
  static void normalLongBodyClipped() {
    String longBody = 'x'.repeat(ErpCallLogger.BODY_MAX + 10);
    ErpCallLogger.Entry e = new ErpCallLogger.Entry();
    e.direction = ErpCallLogger.DIRECTION_OUTBOUND;
    e.interfaceCode = 'IF-03';
    e.requestBody = longBody;
    e.result = ErpCallLogger.RESULT_SUCCESS;

    Test.startTest();
    ErpCallLogger.add(e);
    ErpCallLogger.flush();
    Test.stopTest();

    ErpCallLog__c log = onlyLog();
    Assert.isTrue(log.Truncated__c);
    Assert.areEqual(ErpCallLogger.BODY_MAX, log.RequestBody__c.length());
    Assert.isTrue(log.RequestBody__c.contains('잘림'));
    Assert.areEqual(0, ErpCallLogger.pendingCount(), '저장 뒤 비움');
  }
}
