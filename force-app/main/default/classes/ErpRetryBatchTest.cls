/**
 * @description ErpRetryBatch · ErpRetrySchedulable 테스트 — 실패·멈춘 대기 건 재전송, 대상 아닌 건 제외, 상한 초과, 200건, 예약 실행
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 7번)
 * ----------------------------------------------------------------------------
 * @see ErpRetryBatch, ErpRetrySchedulable
 */
@isTest
private class ErpRetryBatchTest {
  private static final String WAREHOUSE_CODE = 'WH-TEST';
  private static final String VAN_CODE = 'VAN-TEST';

  // DESC: 가짜 ERP. 차감·이동 API를 주소로 구분해 응답하고 API별 호출 횟수를 셈
  private class ErpMock implements HttpCalloutMock {
    Integer statusCode = 200;
    Integer consumeCalls = 0;
    Integer transferCalls = 0;
    Integer lastItemCount = 0;

    public HttpResponse respond(HttpRequest request) {
      Boolean isTransfer = request.getEndpoint().endsWith('/transfer');
      if (isTransfer) {
        transferCalls++;
      } else {
        consumeCalls++;
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      if (statusCode != 200) {
        response.setBody('{"error":"MAINTENANCE"}');
        return response;
      }
      List<Object> items = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
          request.getBody()
        ))
        .get('items');
      lastItemCount = items.size();
      List<Object> results = new List<Object>();
      for (Object raw : items) {
        Map<String, Object> result = new Map<String, Object>{
          'refId' => ((Map<String, Object>) raw).get('refId'),
          'status' => 'OK'
        };
        if (isTransfer) {
          result.put('sourceRemainingQty', 1);
          result.put('destinationRemainingQty', 1);
        } else {
          result.put('remainingQty', 1);
        }
        results.add(result);
      }
      response.setBody(
        JSON.serialize(new Map<String, Object>{ 'results' => results })
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
      'TEST-RETRY-',
      1
    );
    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    Map<String, ProductItem> vanItemsByFamily = TestDataFactory.createVanStock(
      TestDataFactory.createProducts(),
      1000
    );
    ProductItem vanItem = vanItemsByFamily.get('General');
    update new Schema.Location(
      Id = vanItem.LocationId,
      ErpLocationCode__c = VAN_CODE
    );
    Schema.Location warehouse = new Schema.Location(
      Name = '테스트 창고',
      LocationType = 'Warehouse',
      IsInventoryLocation = true,
      ErpLocationCode__c = WAREHOUSE_CODE
    );
    insert warehouse;
    insert new ProductItem(
      LocationId = warehouse.Id,
      Product2Id = vanItem.Product2Id,
      QuantityOnHand = 1000
    );
  }

  private static List<ProductConsumed> insertParts(Integer count) {
    Id workOrderId = [SELECT Id FROM WorkOrder LIMIT 1].Id;
    Id itemId = [
      SELECT Id
      FROM ProductItem
      WHERE
        Location.ErpLocationCode__c = :VAN_CODE
        AND Product2.Family = 'General'
      LIMIT 1
    ]
    .Id;
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < count; i++) {
      parts.add(TestDataFactory.buildPart(workOrderId, itemId));
    }
    insert parts;
    return parts;
  }

  // DESC: 창고 → 차량 이동을 수령 상태로 생성 (트리거가 대기로 표시, 테스트에서는 Queueable 없음)
  private static ProductTransfer insertReceivedTransfer() {
    ProductItem source = [
      SELECT Id, Product2Id
      FROM ProductItem
      WHERE Location.ErpLocationCode__c = :WAREHOUSE_CODE
      LIMIT 1
    ];
    ProductTransfer transfer = new ProductTransfer(
      SourceProductItemId = source.Id,
      Product2Id = source.Product2Id,
      DestinationLocationId = [
        SELECT Id
        FROM Location
        WHERE ErpLocationCode__c = :VAN_CODE
      ]
      .Id,
      QuantitySent = 1,
      QuantityReceived = 1,
      IsReceived = true
    );
    insert transfer;
    return transfer;
  }

  // DESC: ERP 필드는 사용자에게 읽기 전용(Apex만 씀) → 테스트 데이터 준비도 시스템 모드
  private static void setState(
    SObject record,
    String status,
    Integer retries,
    String message
  ) {
    record.put('ErpSyncStatus__c', status);
    record.put('ErpRetryCount__c', retries);
    record.put('ErpSyncMessage__c', message);
  }

  private static void runBatch() {
    Test.startTest();
    Database.executeBatch(new ErpRetryBatch(), ErpRetrySchedulable.BATCH_SIZE);
    Test.stopTest();
  }

  // 정상: 실패 사용 부품·실패 재고 이동은 재전송, 멈춘 대기 사용 부품은 첫 전송 → 모두 완료
  @isTest
  static void normalRetriesFailedAndStuckPending() {
    List<ProductConsumed> parts = insertParts(2);
    ProductConsumed failed = parts[0];
    ProductConsumed stuck = parts[1];
    ProductTransfer failedTransfer = insertReceivedTransfer();
    setState(failed, 'Failed', 1, '[HTTP_503] 점검');
    setState(failedTransfer, 'Failed', 0, '[CONNECTION] 시간 초과');
    Database.update(failed, AccessLevel.SYSTEM_MODE);
    Database.update(failedTransfer, AccessLevel.SYSTEM_MODE);
    // DESC: 방금 저장된 대기 건도 "멈춘 건"으로 보도록 대기 시간 기준을 없앰
    ErpRetryBatch.pendingGraceMinutes = -1;
    ErpMock mock = new ErpMock();
    Test.setMock(HttpCalloutMock.class, mock);

    runBatch();

    for (ProductConsumed pc : [
      SELECT Id, ErpSyncStatus__c, ErpRetryCount__c
      FROM ProductConsumed
      WHERE Id IN :parts
    ]) {
      Assert.areEqual('Synced', pc.ErpSyncStatus__c, '사용 부품 완료');
      Assert.areEqual(
        pc.Id == failed.Id ? 1 : 0,
        pc.ErpRetryCount__c,
        '성공하면 횟수는 그대로'
      );
    }
    Assert.areEqual(
      'Synced',
      [
        SELECT ErpSyncStatus__c
        FROM ProductTransfer
        WHERE Id = :failedTransfer.Id
      ]
      .ErpSyncStatus__c,
      '재고 이동 완료'
    );
    Assert.areEqual(2, mock.consumeCalls, '차감: 재전송 1번 + 첫 전송 1번');
    Assert.areEqual(1, mock.transferCalls, '이동: 재전송 1번');
  }

  // 불허: 완료·확인 필요·재시도 초과(횟수 = 상한)·방금 저장된 대기 건은 보내지 않음
  @isTest
  static void rejectSkipsNonTargets() {
    List<ProductConsumed> parts = insertParts(4);
    Integer maxRetry = ErpInventoryService.getMaxRetry();
    setState(parts[0], 'Synced', 0, '[OK] 완료');
    setState(parts[1], 'NeedsReview', 0, '[INSUFFICIENT_STOCK] 부족');
    setState(parts[2], 'Failed', maxRetry, '[HTTP_503] 점검');
    // DESC: parts[3]은 방금 저장된 대기(Pending) — 기본 대기 시간(10분) 전이라 제외
    Database.update(
      new List<ProductConsumed>{ parts[0], parts[1], parts[2] },
      AccessLevel.SYSTEM_MODE
    );
    ErpMock mock = new ErpMock();
    Test.setMock(HttpCalloutMock.class, mock);

    runBatch();

    Assert.areEqual(0, mock.consumeCalls + mock.transferCalls, '콜아웃 없음');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM ProductConsumed
        WHERE Id = :parts[3].Id AND ErpSyncStatus__c = 'Pending'
      ],
      '방금 저장된 대기 건은 그대로'
    );
  }

  // 불허: 재전송에서도 실패해 상한 도달 → 확인 필요 [RETRY_EXHAUSTED]
  @isTest
  static void rejectRetryFailsAgainNeedsReview() {
    ProductConsumed part = insertParts(1)[0];
    Integer maxRetry = ErpInventoryService.getMaxRetry();
    setState(part, 'Failed', maxRetry - 1, '[HTTP_503] 점검');
    Database.update(part, AccessLevel.SYSTEM_MODE);
    ErpMock mock = new ErpMock();
    mock.statusCode = 503;
    Test.setMock(HttpCalloutMock.class, mock);

    runBatch();

    ProductConsumed after = [
      SELECT ErpSyncStatus__c, ErpRetryCount__c, ErpSyncMessage__c
      FROM ProductConsumed
      WHERE Id = :part.Id
    ];
    Assert.areEqual('NeedsReview', after.ErpSyncStatus__c, '확인 필요');
    Assert.areEqual(maxRetry, after.ErpRetryCount__c, '횟수 = 상한');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[RETRY_EXHAUSTED]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 벌크: 실패 사용 부품 200건 → 묶음 1개, 콜아웃 1번, 전부 완료
  @isTest
  static void bulk200FailedOneCallout() {
    List<ProductConsumed> parts = insertParts(200);
    for (ProductConsumed pc : parts) {
      setState(pc, 'Failed', 0, '[HTTP_503] 점검');
    }
    Database.update(parts, AccessLevel.SYSTEM_MODE);
    ErpMock mock = new ErpMock();
    Test.setMock(HttpCalloutMock.class, mock);

    runBatch();

    Assert.areEqual(1, mock.consumeCalls, '200건 = 콜아웃 1번');
    Assert.areEqual(200, mock.lastItemCount, '한 요청에 200건');
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM ProductConsumed WHERE ErpSyncStatus__c = 'Synced'],
      '200건 완료'
    );
  }

  // 정상: 예약 작업이 실행되면 재전송 Batch를 시작
  @isTest
  static void normalSchedulableStartsBatch() {
    Test.startTest();
    String jobId = System.schedule(
      'HG ERP 재전송 테스트',
      '0 0 * * * ?',
      new ErpRetrySchedulable()
    );
    Test.stopTest();

    Assert.isNotNull(jobId, '예약됨');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE JobType = 'BatchApex' AND ApexClass.Name = 'ErpRetryBatch'
      ],
      'Batch 시작'
    );
  }
}
