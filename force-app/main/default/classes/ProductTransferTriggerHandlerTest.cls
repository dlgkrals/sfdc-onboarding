/**
 * @description ProductTransferTriggerHandler · ErpInventoryService(재고 이동 IF-06) 테스트
 *              창고 → 기사 차량 재고 이동을 수령하면 ERP로 이동 전송. HttpCalloutMock으로 ERP 응답을 흉내 냄
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 6번)
 * ----------------------------------------------------------------------------
 * @see ProductTransferTriggerHandler, ErpInventoryService
 */
@isTest
private class ProductTransferTriggerHandlerTest {
  private static final String WAREHOUSE_CODE = 'WH-TEST';
  private static final String VAN_CODE = 'VAN-TEST';
  private static final Decimal WAREHOUSE_QUANTITY = 1000;
  private static final Decimal VAN_QUANTITY = 5;

  // DESC: 가짜 ERP 재고 이동. 정해 둔 방식으로 응답하고 호출 횟수·마지막 요청을 기록
  private class ErpTransferMock implements HttpCalloutMock {
    String mode = 'OK'; // OK · REJECT · HTTP
    Integer statusCode = 200;
    Decimal sourceRemainingQty;
    Decimal destinationRemainingQty;
    Integer calls = 0;
    String lastEndpoint;
    List<Object> lastItems;

    public HttpResponse respond(HttpRequest request) {
      calls++;
      lastEndpoint = request.getEndpoint();
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      if (mode == 'HTTP') {
        response.setBody('{"error":"MAINTENANCE"}');
        return response;
      }
      lastItems = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
          request.getBody()
        ))
        .get('items');
      List<Object> results = new List<Object>();
      for (Object raw : lastItems) {
        Map<String, Object> item = (Map<String, Object>) raw;
        results.add(
          mode == 'OK'
            ? new Map<String, Object>{
                'refId' => item.get('refId'),
                'status' => 'OK',
                'sourceRemainingQty' => sourceRemainingQty,
                'destinationRemainingQty' => destinationRemainingQty,
                'unit' => 'Each'
              }
            : new Map<String, Object>{
                'refId' => item.get('refId'),
                'status' => 'REJECTED',
                'code' => 'INSUFFICIENT_STOCK',
                'message' => '출발 위치 재고가 부족합니다.'
              }
        );
      }
      response.setBody(
        JSON.serialize(new Map<String, Object>{ 'results' => results })
      );
      return response;
    }
  }

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_Technician', true);
    }
    User technician = getTechnician();
    Product2 part = TestDataFactory.createProducts().get('General');
    // DESC: 창고 = 관리자(실행 사용자) 소유, 기사 차량 = 기사 소유 (실제 org와 같은 구조)
    Schema.Location warehouse = new Schema.Location(
      Name = '테스트 창고',
      LocationType = 'Warehouse',
      IsInventoryLocation = true,
      ErpLocationCode__c = WAREHOUSE_CODE
    );
    Schema.Location van = new Schema.Location(
      Name = '테스트 기사 차량',
      LocationType = 'Van',
      IsInventoryLocation = true,
      ErpLocationCode__c = VAN_CODE,
      OwnerId = technician.Id
    );
    insert new List<Schema.Location>{ warehouse, van };
    ProductItem warehouseItem = new ProductItem(
      LocationId = warehouse.Id,
      Product2Id = part.Id,
      QuantityOnHand = WAREHOUSE_QUANTITY
    );
    ProductItem vanItem = new ProductItem(
      LocationId = van.Id,
      Product2Id = part.Id,
      QuantityOnHand = VAN_QUANTITY,
      OwnerId = technician.Id
    );
    insert new List<ProductItem>{ warehouseItem, vanItem };
    // DESC: 실제 org의 공유 규칙(창고·창고 재고 → 경기남부 기사 읽기)을 수동 공유로 재현
    insert new LocationShare(
      ParentId = warehouse.Id,
      UserOrGroupId = technician.Id,
      AccessLevel = 'Read'
    );
    insert new ProductItemShare(
      ParentId = warehouseItem.Id,
      UserOrGroupId = technician.Id,
      AccessLevel = 'Read'
    );
  }

  private static User getTechnician() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_Technician'
      LIMIT 1
    ];
  }

  private static ProductItem getItem(String locationCode) {
    return [
      SELECT Id, Product2Id, LocationId, QuantityOnHand
      FROM ProductItem
      WHERE Location.ErpLocationCode__c = :locationCode
      LIMIT 1
    ];
  }

  private static ProductTransfer buildTransfer(Decimal quantity) {
    ProductItem source = getItem(WAREHOUSE_CODE);
    return new ProductTransfer(
      SourceProductItemId = source.Id,
      Product2Id = source.Product2Id,
      DestinationLocationId = getItem(VAN_CODE).LocationId,
      QuantitySent = quantity
    );
  }

  private static ProductTransfer reload(Id id) {
    return [
      SELECT
        ErpSyncStatus__c,
        ErpSyncMessage__c,
        ErpSyncedAt__c,
        ErpRetryCount__c,
        ErpSourceRemainingQty__c,
        ErpDestinationRemainingQty__c,
        InventoryMismatch__c
      FROM ProductTransfer
      WHERE Id = :id
    ];
  }

  // DESC: 이동 건 생성(미수령) → 수령 저장 → stopTest에서 Queueable이 ERP 전송
  private static ProductTransfer receiveAndSync(
    ErpTransferMock mock,
    Decimal quantity
  ) {
    ProductTransfer transfer = buildTransfer(quantity);
    insert transfer;
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    Test.startTest();
    transfer.IsReceived = true;
    transfer.QuantityReceived = quantity;
    update transfer;
    Test.stopTest();
    return reload(transfer.Id);
  }

  // 정상: 수령 → ERP 이동 완료, 출발·도착 남은 수량 기록, Salesforce 표준 수량과 같으면 불일치 아님, 요청 항목 확인
  @isTest
  static void normalReceiveSyncsToErp() {
    ErpTransferMock mock = new ErpTransferMock();
    mock.sourceRemainingQty = WAREHOUSE_QUANTITY - 3;
    mock.destinationRemainingQty = VAN_QUANTITY + 3;

    ProductTransfer after = receiveAndSync(mock, 3);

    Assert.areEqual('Synced', after.ErpSyncStatus__c, '완료');
    Assert.areEqual(
      WAREHOUSE_QUANTITY - 3,
      after.ErpSourceRemainingQty__c,
      'ERP 출발 남은 수량'
    );
    Assert.areEqual(
      VAN_QUANTITY + 3,
      after.ErpDestinationRemainingQty__c,
      'ERP 도착 남은 수량'
    );
    Assert.isFalse(after.InventoryMismatch__c, '표준 이동 후 수량과 같음');
    Assert.areEqual(0, after.ErpRetryCount__c, '재시도 없음');
    Assert.areEqual(
      1,
      mock.calls,
      '콜아웃 1번 (결과 저장 때 다시 예약하지 않음)'
    );
    Assert.isTrue(
      mock.lastEndpoint.endsWith('/api/stock/transfer'),
      '이동 API'
    );
    Map<String, Object> sent = (Map<String, Object>) mock.lastItems[0];
    Assert.areEqual(WAREHOUSE_CODE, sent.get('fromLocationCode'), '출발');
    Assert.areEqual(VAN_CODE, sent.get('toLocationCode'), '도착');
    Assert.areEqual('TEST-GEN', sent.get('partCode'), '부품 코드');
    Assert.areEqual(
      3,
      Decimal.valueOf(String.valueOf(sent.get('quantity'))),
      '받은 수량'
    );
    Assert.isNotNull(sent.get('reference'), '재고 이동 번호');
  }

  // 정상: 처음부터 수령 상태로 만든 이동 건도 전송, ERP 수량이 다르면 불일치 표시(수량은 고치지 않음)
  @isTest
  static void normalInsertReceivedFlagsMismatch() {
    ErpTransferMock mock = new ErpTransferMock();
    mock.sourceRemainingQty = 10;
    mock.destinationRemainingQty = VAN_QUANTITY + 2;
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    ProductTransfer transfer = buildTransfer(2);
    transfer.IsReceived = true;
    transfer.QuantityReceived = 2;

    Test.startTest();
    insert transfer;
    Test.stopTest();

    ProductTransfer after = reload(transfer.Id);
    Assert.areEqual('Synced', after.ErpSyncStatus__c, '완료');
    Assert.isTrue(after.InventoryMismatch__c, '출발 수량이 달라 불일치');
    Assert.areEqual(
      WAREHOUSE_QUANTITY - 2,
      getItem(WAREHOUSE_CODE).QuantityOnHand,
      'Salesforce 창고 수량은 표준 이동 그대로'
    );
  }

  // 불허: 아직 수령하지 않은 이동 건은 보내지 않음 (상태 없음, 콜아웃 없음)
  @isTest
  static void rejectNotReceivedNotSent() {
    ErpTransferMock mock = new ErpTransferMock();
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    ProductTransfer transfer = buildTransfer(1);

    Test.startTest();
    insert transfer;
    transfer.Description = '수령 전 메모 수정';
    update transfer;
    Test.stopTest();

    Assert.isNull(reload(transfer.Id).ErpSyncStatus__c, '전송 대상 아님');
    Assert.areEqual(0, mock.calls, '콜아웃 없음');
  }

  // 불허: ERP 출발 재고 부족 → 확인 필요, 코드가 메시지에
  @isTest
  static void rejectInsufficientStockNeedsReview() {
    ErpTransferMock mock = new ErpTransferMock();
    mock.mode = 'REJECT';

    ProductTransfer after = receiveAndSync(mock, 1);

    Assert.areEqual('NeedsReview', after.ErpSyncStatus__c, '확인 필요');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[INSUFFICIENT_STOCK]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 불허: ERP 장애(503) → 실패, 재전송에서도 실패해 상한 도달 → 확인 필요 [RETRY_EXHAUSTED]
  @isTest
  static void rejectServerErrorRetriesThenNeedsReview() {
    ErpTransferMock mock = new ErpTransferMock();
    mock.mode = 'HTTP';
    mock.statusCode = 503;

    ProductTransfer first = receiveAndSync(mock, 1);
    Assert.areEqual('Failed', first.ErpSyncStatus__c, '503 → 실패');
    Assert.isTrue(
      first.ErpSyncMessage__c.startsWith('[HTTP_503]'),
      '메시지: ' + first.ErpSyncMessage__c
    );

    Id transferId = [SELECT Id FROM ProductTransfer LIMIT 1].Id;
    Integer maxRetry = ErpInventoryService.getMaxRetry();
    for (Integer i = 0; i < maxRetry; i++) {
      ErpInventoryService.sendTransfers(new Set<Id>{ transferId }, true);
    }
    ProductTransfer last = reload(transferId);
    Assert.areEqual('NeedsReview', last.ErpSyncStatus__c, '상한 초과');
    Assert.areEqual(maxRetry, last.ErpRetryCount__c, '횟수 = 상한');
    Assert.isTrue(
      last.ErpSyncMessage__c.startsWith('[RETRY_EXHAUSTED]'),
      '메시지: ' + last.ErpSyncMessage__c
    );
  }

  // 불허: 도착 위치에 ERP 코드가 없으면 보내지 않고 확인 필요 [MISSING_CODE]
  @isTest
  static void rejectMissingErpCodeWithoutCallout() {
    Schema.Location van = [
      SELECT Id
      FROM Location
      WHERE ErpLocationCode__c = :VAN_CODE
    ];
    ProductTransfer transfer = buildTransfer(1);
    van.ErpLocationCode__c = null;
    update van;
    ErpTransferMock mock = new ErpTransferMock();
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    transfer.IsReceived = true;
    transfer.QuantityReceived = 1;

    Test.startTest();
    insert transfer;
    Test.stopTest();

    ProductTransfer after = reload(transfer.Id);
    Assert.areEqual('NeedsReview', after.ErpSyncStatus__c, '확인 필요');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[MISSING_CODE]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
    Assert.areEqual(0, mock.calls, '콜아웃 없음');
  }

  // 벌크: 이동 200건을 한 번에 수령 → Queueable 1개, 콜아웃 1번, 전부 완료
  @isTest
  static void bulk200TransfersOneCallout() {
    List<ProductTransfer> transfers = new List<ProductTransfer>();
    // PERF: 조회는 1번, 복제로 200건
    ProductTransfer template = buildTransfer(1);
    for (Integer i = 0; i < 200; i++) {
      transfers.add(template.clone());
    }
    insert transfers;
    ErpTransferMock mock = new ErpTransferMock();
    mock.sourceRemainingQty = WAREHOUSE_QUANTITY - 200;
    mock.destinationRemainingQty = VAN_QUANTITY + 200;
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    for (ProductTransfer pt : transfers) {
      pt.IsReceived = true;
      pt.QuantityReceived = 1;
    }

    Test.startTest();
    update transfers;
    Test.stopTest();

    Assert.areEqual(1, mock.calls, '200건 = 콜아웃 1번');
    Assert.areEqual(200, mock.lastItems.size(), '한 요청에 200건');
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM ProductTransfer WHERE ErpSyncStatus__c = 'Synced'],
      '200건 완료'
    );
    Assert.areEqual(
      WAREHOUSE_QUANTITY - 200,
      getItem(WAREHOUSE_CODE).QuantityOnHand,
      '표준 이동: 창고 -200'
    );
  }

  // 정상: 협력 기사가 읽기 전용으로 공유된 창고 재고에서 자기 차량으로 이동 건을 만들고 수령 → 표준 이동 + ERP 전송 (기사 권한)
  @isTest
  static void normalTechnicianReceivesFromWarehouse() {
    User technician = getTechnician();
    ErpTransferMock mock = new ErpTransferMock();
    mock.sourceRemainingQty = WAREHOUSE_QUANTITY - 4;
    mock.destinationRemainingQty = VAN_QUANTITY + 4;
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    ProductTransfer transfer;

    System.runAs(technician) {
      transfer = buildTransfer(4);
      insert transfer;
      Test.startTest();
      transfer.IsReceived = true;
      transfer.QuantityReceived = 4;
      update transfer;
      Test.stopTest();
    }

    ProductTransfer after = reload(transfer.Id);
    Assert.areEqual('Synced', after.ErpSyncStatus__c, '기사 수령 → ERP 완료');
    Assert.isFalse(after.InventoryMismatch__c, '창고 996·차량 9, ERP와 같음');
    Assert.areEqual(
      WAREHOUSE_QUANTITY - 4,
      getItem(WAREHOUSE_CODE).QuantityOnHand,
      '창고 재고 수정 권한 없이도 표준 이동으로 창고 -4'
    );
    Assert.areEqual(
      VAN_QUANTITY + 4,
      getItem(VAN_CODE).QuantityOnHand,
      '기사 차량 +4'
    );
  }
}
