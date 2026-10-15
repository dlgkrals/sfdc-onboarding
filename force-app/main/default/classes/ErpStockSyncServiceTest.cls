/**
 * @description ErpStockSyncService · ErpStockSyncBatch · ErpStockSyncSchedulable 테스트 (IF-02 역방향)
 *              가짜 ERP가 "이력 번호 after 이후"만 돌려줌 → 입고·조정 반영, Salesforce 출처 건너뜀, 새 재고 생성,
 *              통신 실패 시 번호 유지, 데이터 문제 기록, 같은 변동 한 번만, 200건
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 IF-02 역방향)
 * 1.1    2026-10-15    Edwin     중복 번호는 쪽 실패 대신 건너뜀(푸시와 함께 쓰기), 기록 메시지 경로 확인
 * ----------------------------------------------------------------------------
 * @see ErpStockSyncService
 */
@isTest
private class ErpStockSyncServiceTest {
  private static final String VAN_CODE = 'VAN-T';
  private static final String WAREHOUSE_CODE = 'WH-T';
  private static final Decimal VAN_GENERAL_QTY = 10;
  private static final Long BASELINE = 100;

  // DESC: 가짜 ERP 이력. 요청의 after·limit을 읽어 그 이후만 돌려줌 (실제 API와 같은 규칙)
  private class MovementsMock implements HttpCalloutMock {
    List<Map<String, Object>> movements = new List<Map<String, Object>>();
    Integer statusCode = 200;
    Integer calls = 0;

    void add(
      Long id,
      String type,
      String origin,
      String location,
      String part,
      Decimal change,
      String unit
    ) {
      movements.add(
        new Map<String, Object>{
          'id' => id,
          'type' => type,
          'origin' => origin,
          'locationCode' => location,
          'partCode' => part,
          'quantityChange' => change,
          'unit' => unit,
          'createdAt' => '2026-10-13T12:00:00.000Z'
        }
      );
    }

    public HttpResponse respond(HttpRequest request) {
      calls++;
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      if (statusCode != 200) {
        response.setBody('{"error":"MAINTENANCE"}');
        return response;
      }
      PageReference ref = new PageReference(request.getEndpoint());
      Long after = Long.valueOf(ref.getParameters().get('after'));
      Integer limitRows = Integer.valueOf(ref.getParameters().get('limit'));
      List<Map<String, Object>> page = new List<Map<String, Object>>();
      Long latest = 0;
      Boolean hasMore = false;
      for (Map<String, Object> m : movements) {
        Long id = (Long) m.get('id');
        latest = Math.max(latest, id);
        if (id > after) {
          if (page.size() < limitRows) {
            page.add(m);
          } else {
            hasMore = true;
          }
        }
      }
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'items' => page,
            'lastId' => page.isEmpty()
              ? after
              : (Long) page[page.size() - 1].get('id'),
            'hasMore' => hasMore,
            'latestId' => latest
          }
        )
      );
      return response;
    }
  }

  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_Technician', true);
    }
    User technician = [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_Technician'
      LIMIT 1
    ];
    Map<String, Product2> productsByFamily = TestDataFactory.createProducts();
    Schema.Location van = new Schema.Location(
      Name = '테스트 기사 차량',
      LocationType = 'Van',
      IsInventoryLocation = true,
      ErpLocationCode__c = VAN_CODE,
      OwnerId = technician.Id
    );
    Schema.Location warehouse = new Schema.Location(
      Name = '테스트 창고',
      LocationType = 'Warehouse',
      IsInventoryLocation = true,
      ErpLocationCode__c = WAREHOUSE_CODE
    );
    insert new List<Schema.Location>{ van, warehouse };
    // DESC: 차량에는 일반 부품 재고만 (압축기는 없음 → 입고 시 새로 생성되는지 확인)
    insert new ProductItem(
      LocationId = van.Id,
      Product2Id = productsByFamily.get('General').Id,
      QuantityOnHand = VAN_GENERAL_QTY,
      QuantityUnitOfMeasure = 'Each',
      OwnerId = technician.Id
    );
    ErpStockSyncService.saveLastMovementId(BASELINE);
  }

  private static Decimal vanQty(String partCode) {
    List<ProductItem> items = [
      SELECT QuantityOnHand
      FROM ProductItem
      WHERE
        Location.ErpLocationCode__c = :VAN_CODE
        AND Product2.ErpPartCode__c = :partCode
    ];
    return items.isEmpty() ? null : items[0].QuantityOnHand;
  }

  private static ErpStockSyncService.SyncResult sync(MovementsMock mock) {
    Test.setMock(HttpCalloutMock.class, mock);
    return ErpStockSyncService.syncNextPage();
  }

  // 정상: ERP 입고 +5, 조정 -1.5 → 현재 + 변동량, 기록 2건 반영, 이력 번호 102로
  @isTest
  static void normalReceiptAndAdjustApplied() {
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 5, 'Each');
    mock.add(102, 'ADJUST', 'ERP', VAN_CODE, 'TEST-GEN', -1.5, 'Each');

    Test.startTest();
    ErpStockSyncService.SyncResult result = sync(mock);
    Test.stopTest();

    Assert.areEqual(
      VAN_GENERAL_QTY + 5 - 1.5,
      vanQty('TEST-GEN'),
      '10 + 5 - 1.5'
    );
    Assert.areEqual(2, result.applied, '반영 2건');
    Assert.areEqual(
      102,
      ErpStockSyncService.getLastMovementId(),
      '이력 번호 102'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM ErpInboundLog__c WHERE Result__c = 'Applied'],
      '기록 2건'
    );
  }

  // 정상: Salesforce에 없던 위치+부품(차량의 압축기) 입고 → 재고 새로 생성, 소유자 = 차량 소유자(기사), 단위
  @isTest
  static void normalNewStockCreated() {
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-CMP', 3, 'Each');

    Test.startTest();
    ErpStockSyncService.SyncResult result = sync(mock);
    Test.stopTest();

    ProductItem created = [
      SELECT QuantityOnHand, QuantityUnitOfMeasure, OwnerId, Location.OwnerId
      FROM ProductItem
      WHERE
        Location.ErpLocationCode__c = :VAN_CODE
        AND Product2.ErpPartCode__c = 'TEST-CMP'
    ];
    Assert.areEqual(3, created.QuantityOnHand, '새 재고 3');
    Assert.areEqual('Each', created.QuantityUnitOfMeasure, '단위');
    Assert.areEqual(
      created.Location.OwnerId,
      created.OwnerId,
      '소유자 = 차량 소유자'
    );
    Assert.areEqual(1, result.createdItems, '생성 1건');
  }

  // 불허: Salesforce가 보낸 사용 차감·재고 이동과 초기 적재는 건너뜀 (재고·기록 그대로), 이력 번호는 넘어감
  @isTest
  static void rejectSalesforceOriginSkipped() {
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'CONSUME', 'SALESFORCE', VAN_CODE, 'TEST-GEN', -1, 'Each');
    mock.add(102, 'TRANSFER_IN', 'SALESFORCE', VAN_CODE, 'TEST-GEN', 2, 'Each');
    mock.add(103, 'SEED', 'SEED', VAN_CODE, 'TEST-GEN', 10, 'Each');

    Test.startTest();
    ErpStockSyncService.SyncResult result = sync(mock);
    Test.stopTest();

    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
    Assert.areEqual(3, result.skipped, '3건 건너뜀');
    Assert.areEqual(0, [SELECT COUNT() FROM ErpInboundLog__c], '기록 없음');
    Assert.areEqual(
      103,
      ErpStockSyncService.getLastMovementId(),
      '번호는 103으로'
    );
  }

  // 불허: ERP 장애(503) → 예외, 이력 번호 그대로 (다음 실행에서 다시), 재고 그대로
  @isTest
  static void rejectConnectionFailureKeepsCursor() {
    MovementsMock mock = new MovementsMock();
    mock.statusCode = 503;
    String message;

    Test.startTest();
    try {
      sync(mock);
    } catch (ErpStockSyncService.ErpSyncException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isTrue(
      message != null && message.startsWith('[HTTP_503]'),
      '메시지: ' + message
    );
    Assert.areEqual(
      BASELINE,
      ErpStockSyncService.getLastMovementId(),
      '번호 그대로'
    );
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
  }

  // 불허: 없는 코드·0 미만이 되는 조정은 오류로 기록하고 건너뜀 (다시 해도 같으므로 번호는 넘어감)
  @isTest
  static void rejectDataProblemsLoggedAndSkipped() {
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'RECEIPT', 'ERP', 'NOPE', 'TEST-GEN', 1, 'Each');
    mock.add(102, 'ADJUST', 'ERP', VAN_CODE, 'TEST-GEN', -50, 'Each');

    Test.startTest();
    ErpStockSyncService.SyncResult result = sync(mock);
    Test.stopTest();

    Assert.areEqual(2, result.errors, '오류 2건');
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
    Assert.areEqual(
      102,
      ErpStockSyncService.getLastMovementId(),
      '번호는 넘어감'
    );
    for (ErpInboundLog__c log : [
      SELECT MovementId__c, Result__c, Message__c
      FROM ErpInboundLog__c
      ORDER BY MovementId__c
    ]) {
      Assert.areEqual('Error', log.Result__c, '오류 기록');
      Assert.isTrue(
        log.Message__c.startsWith(
          log.MovementId__c == 101 ? '[UNKNOWN_CODE]' : '[NEGATIVE_STOCK]'
        ),
        '메시지: ' + log.Message__c
      );
    }
  }

  // 정상: 같은 변동은 한 번만 ① 이미 가져온 번호(101) 이후만 조회하므로 다시 실행해도 가져올 것 없음
  @isTest
  static void normalAlreadyFetchedNotFetchedAgain() {
    ErpStockSyncService.saveLastMovementId(101);
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 5, 'Each');

    Test.startTest();
    ErpStockSyncService.SyncResult again = sync(mock);
    Test.stopTest();

    Assert.areEqual(0, again.fetched, '가져올 것 없음');
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
  }

  // 정상: 같은 변동은 한 번만 ② 이미 기록이 있는 번호(101, 푸시로 먼저 반영된 경우 등)는 건너뜀 → 쪽은 정상 처리, 번호는 101로, 이중 반영 없음
  //       (1.0에서는 고유키 충돌로 쪽 전체가 실패해 같은 쪽에서 계속 멈췄음 → 푸시와 함께 쓰려고 1.1에서 건너뜀으로 변경)
  @isTest
  static void normalDuplicateMovementSkippedOnce() {
    insert new ErpInboundLog__c(
      MovementId__c = 101,
      Result__c = 'Applied',
      MovementType__c = 'RECEIPT'
    );
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 5, 'Each');
    mock.add(102, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 2, 'Each');

    Test.startTest();
    ErpStockSyncService.SyncResult result = sync(mock);
    Test.stopTest();

    Assert.areEqual(1, result.duplicates, '101은 중복으로 건너뜀');
    Assert.areEqual(1, result.applied, '102만 반영');
    Assert.areEqual(
      VAN_GENERAL_QTY + 2,
      vanQty('TEST-GEN'),
      '+5는 다시 반영 안 됨, +2만'
    );
    Assert.areEqual(
      102,
      ErpStockSyncService.getLastMovementId(),
      '번호는 102로 (멈추지 않음)'
    );
    Assert.isTrue(
      [SELECT Message__c FROM ErpInboundLog__c WHERE MovementId__c = 102]
        .Message__c.endsWith('· 가져오기'),
      '기록 메시지에 경로'
    );
  }

  // 불허: 기준점(이력 번호)이 없으면 가져오지 않음 (초기 적재·과거 이력 반영 방지)
  @isTest
  static void rejectWithoutBaseline() {
    delete [SELECT Id FROM ErpSyncState__c];
    MovementsMock mock = new MovementsMock();
    mock.add(1, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 5, 'Each');
    String message;

    Test.startTest();
    try {
      sync(mock);
    } catch (ErpStockSyncService.ErpSyncException e) {
      message = e.getMessage();
    }
    Test.stopTest();

    Assert.isTrue(
      message != null && message.startsWith('[NO_BASELINE]'),
      '메시지: ' + message
    );
    Assert.areEqual(0, mock.calls, 'ERP 호출 안 함');
  }

  // 정상: 미리 보기는 건수만 세고 반영·번호 저장 안 함
  @isTest
  static void normalPreviewCountsOnly() {
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'CONSUME', 'SALESFORCE', VAN_CODE, 'TEST-GEN', -1, 'Each');
    mock.add(102, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 5, 'Each');
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    ErpStockSyncService.SyncResult preview = ErpStockSyncService.preview();
    Test.stopTest();

    Assert.areEqual(1, preview.erpChanges, 'ERP 변동 1건');
    Assert.areEqual(1, preview.skipped, '건너뛸 1건');
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
    Assert.areEqual(
      BASELINE,
      ErpStockSyncService.getLastMovementId(),
      '번호 그대로'
    );
  }

  // 벌크: ERP 입고 200건 → 콜아웃 1번, 재고 +200, 기록 200건
  @isTest
  static void bulk200ReceiptsOneCallout() {
    MovementsMock mock = new MovementsMock();
    for (Integer i = 1; i <= 200; i++) {
      mock.add(BASELINE + i, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 1, 'Each');
    }

    Test.startTest();
    sync(mock);
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(1, mock.calls, '콜아웃 1번');
    Assert.areEqual(VAN_GENERAL_QTY + 200, vanQty('TEST-GEN'), '+200');
    Assert.areEqual(200, [SELECT COUNT() FROM ErpInboundLog__c], '기록 200건');
    Assert.isTrue(queries <= 6, '200건이어도 조회 몇 번: ' + queries);
  }

  // 정상: Batch가 한 쪽을 가져와 반영, 예약 작업은 Batch를 시작
  @isTest
  static void normalBatchAndSchedule() {
    MovementsMock mock = new MovementsMock();
    mock.add(101, 'RECEIPT', 'ERP', VAN_CODE, 'TEST-GEN', 2, 'Each');
    Test.setMock(HttpCalloutMock.class, mock);
    ErpStockSyncBatch.maxPages = 1;

    Test.startTest();
    Database.executeBatch(
      new ErpStockSyncBatch(),
      ErpStockSyncSchedulable.BATCH_SIZE
    );
    String jobId = System.schedule(
      'HG ERP 재고 동기화 테스트',
      '0 15 * * * ?',
      new ErpStockSyncSchedulable()
    );
    Test.stopTest();

    Assert.areEqual(VAN_GENERAL_QTY + 2, vanQty('TEST-GEN'), 'Batch 반영');
    Assert.isNotNull(jobId, '예약됨');
  }
}
