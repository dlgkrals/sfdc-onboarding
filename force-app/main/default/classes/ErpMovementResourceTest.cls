/**
 * @description ErpMovementResource 테스트 — IF-02 푸시 입구(Apex REST)
 *              반영·새 재고·중복·Salesforce 출처 건너뜀·데이터 문제·건별 형식 오류·요청 전체 오류(400)·200건·푸시 뒤 가져오기 중복 건너뜀
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-15
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-15    Edwin     최초 작성 (IF-02 Pull → Push + Pull)
 * 1.1    2026-10-15    Edwin     레코드 접근 없는 사용자로 호출 (실제 호출 결함 재발 방지)
 * ----------------------------------------------------------------------------
 * @see ErpMovementResource, ErpStockSyncService.applyPushed
 */
@isTest
private class ErpMovementResourceTest {
  private static final String VAN_CODE = 'VAN-P';
  private static final Decimal VAN_GENERAL_QTY = 10;
  private static final Long BASELINE = 100;

  @TestSetup
  static void setupData() {
    Map<String, Product2> productsByFamily = TestDataFactory.createProducts();
    Schema.Location van = new Schema.Location(
      Name = '테스트 푸시 차량',
      LocationType = 'Van',
      IsInventoryLocation = true,
      ErpLocationCode__c = VAN_CODE
    );
    insert van;
    insert new ProductItem(
      LocationId = van.Id,
      Product2Id = productsByFamily.get('General').Id,
      QuantityOnHand = VAN_GENERAL_QTY,
      QuantityUnitOfMeasure = 'Each'
    );
    ErpStockSyncService.saveLastMovementId(BASELINE);
  }

  private static Map<String, Object> movement(
    Object id,
    String type,
    String origin,
    String part,
    Object change
  ) {
    return new Map<String, Object>{
      'id' => id,
      'type' => type,
      'origin' => origin,
      'locationCode' => VAN_CODE,
      'partCode' => part,
      'quantityChange' => change,
      'unit' => 'Each',
      'createdAt' => '2026-10-15T09:00:00.000Z'
    };
  }

  // DESC: Apex REST 호출 흉내 → (상태 코드, 응답 본문)
  private static Map<String, Object> post(String body) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/hg/erp/movements';
    req.httpMethod = 'POST';
    req.requestBody = body == null ? null : Blob.valueOf(body);
    RestContext.request = req;
    RestContext.response = new RestResponse();
    ErpMovementResource.receive();
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
    parsed.put('_status', RestContext.response.statusCode);
    return parsed;
  }

  private static Map<String, Object> postMovements(List<Object> movements) {
    return post(
      JSON.serialize(new Map<String, Object>{ 'movements' => movements })
    );
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

  private static Map<String, Object> resultAt(
    Map<String, Object> res,
    Integer i
  ) {
    return (Map<String, Object>) ((List<Object>) res.get('results'))[i];
  }

  // 정상: ERP 입고 +5 → 10 + 5, 기록 "반영 · 푸시", 이력 번호(가져오기 기준)는 그대로, 응답 APPLIED + 반영 후 수량
  @isTest
  static void normalReceiptApplied() {
    Test.startTest();
    Map<String, Object> res = postMovements(
      new List<Object>{ movement(101, 'RECEIPT', 'ERP', 'TEST-GEN', 5) }
    );
    Test.stopTest();

    Assert.areEqual(200, res.get('_status'), 'HTTP 200');
    Assert.areEqual(1, res.get('applied'), '반영 1');
    Assert.areEqual('APPLIED', resultAt(res, 0).get('result'), '건별 결과');
    Assert.areEqual(15, resultAt(res, 0).get('quantityAfter'), '반영 후 15');
    Assert.areEqual(VAN_GENERAL_QTY + 5, vanQty('TEST-GEN'), '10 + 5');
    ErpInboundLog__c log = [
      SELECT Result__c, Message__c
      FROM ErpInboundLog__c
      WHERE MovementId__c = 101
    ];
    Assert.areEqual('Applied', log.Result__c, '기록 반영');
    Assert.isTrue(
      log.Message__c.endsWith('· 푸시'),
      '기록에 경로: ' + log.Message__c
    );
    Assert.areEqual(
      BASELINE,
      ErpStockSyncService.getLastMovementId(),
      '푸시는 가져오기 기준 번호를 올리지 않음'
    );
  }

  // 정상(권한): 레코드를 하나도 못 보는 사용자(연동 사용자와 같은 처지)로 호출해도 위치·재고를 찾아 반영
  //            (2026-10-15 실제 호출에서 with sharing 때문에 "없는 위치 코드"가 났던 결함의 재발 방지)
  @isTest
  static void normalAppliedByUserWithoutRecordAccess() {
    User noAccess;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      noAccess = TestDataFactory.createUser('HG_CallCenter', false);
    }
    Id vanId = [SELECT Id FROM Location WHERE ErpLocationCode__c = :VAN_CODE]
    .Id;
    Assert.isFalse(
      [
        SELECT RecordId, HasReadAccess
        FROM UserRecordAccess
        WHERE UserId = :noAccess.Id AND RecordId = :vanId
      ]
      .HasReadAccess,
      '전제: 이 사용자는 차량 위치를 볼 수 없음'
    );
    Map<String, Object> res;

    Test.startTest();
    System.runAs(noAccess) {
      res = postMovements(
        new List<Object>{ movement(101, 'RECEIPT', 'ERP', 'TEST-GEN', 3) }
      );
    }
    Test.stopTest();

    Assert.areEqual(
      'APPLIED',
      resultAt(res, 0).get('result'),
      '반영: ' + resultAt(res, 0)
    );
    Assert.areEqual(VAN_GENERAL_QTY + 3, vanQty('TEST-GEN'), '10 + 3');
  }

  // 정상: Salesforce에 없던 재고(차량 압축기) 입고 → 새로 생성
  @isTest
  static void normalNewStockCreated() {
    Test.startTest();
    Map<String, Object> res = postMovements(
      new List<Object>{ movement(101, 'RECEIPT', 'ERP', 'TEST-CMP', 2) }
    );
    Test.stopTest();

    Assert.areEqual('APPLIED', resultAt(res, 0).get('result'), '반영');
    Assert.areEqual(2, vanQty('TEST-CMP'), '새 재고 2');
  }

  // 불허: 이미 기록된 번호·같은 요청 안의 반복 번호 → DUPLICATE, 한 번만 반영
  @isTest
  static void rejectDuplicateAppliedOnce() {
    insert new ErpInboundLog__c(
      MovementId__c = 101,
      Result__c = 'Applied',
      MovementType__c = 'RECEIPT'
    );

    Test.startTest();
    Map<String, Object> res = postMovements(
      new List<Object>{
        movement(101, 'RECEIPT', 'ERP', 'TEST-GEN', 5),
        movement(102, 'RECEIPT', 'ERP', 'TEST-GEN', 1),
        movement(102, 'RECEIPT', 'ERP', 'TEST-GEN', 1)
      }
    );
    Test.stopTest();

    Assert.areEqual(
      'DUPLICATE',
      resultAt(res, 0).get('result'),
      '이미 기록된 101'
    );
    Assert.areEqual('APPLIED', resultAt(res, 1).get('result'), '102 처음');
    Assert.areEqual(
      'DUPLICATE',
      resultAt(res, 2).get('result'),
      '같은 요청 안 102 반복'
    );
    Assert.areEqual(
      VAN_GENERAL_QTY + 1,
      vanQty('TEST-GEN'),
      '+1만 (재귀·이중 반영 없음)'
    );
  }

  // 불허(재귀 방지): Salesforce 출처(사용 차감)·초기 적재 → SKIPPED, 재고·기록 변화 없음
  @isTest
  static void rejectNonErpOriginSkipped() {
    Test.startTest();
    Map<String, Object> res = postMovements(
      new List<Object>{
        movement(101, 'CONSUME', 'SALESFORCE', 'TEST-GEN', -1),
        movement(102, 'SEED', 'SEED', 'TEST-GEN', 10)
      }
    );
    Test.stopTest();

    Assert.areEqual(2, res.get('skipped'), '건너뜀 2');
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
    Assert.areEqual(0, [SELECT COUNT() FROM ErpInboundLog__c], '기록 없음');
  }

  // 불허: 데이터 문제(없는 부품 코드, 0 미만이 되는 조정) → ERROR + 오류 기록, 재고 그대로
  @isTest
  static void rejectDataProblemsLogged() {
    Test.startTest();
    Map<String, Object> res = postMovements(
      new List<Object>{
        movement(101, 'RECEIPT', 'ERP', 'NO-SUCH', 1),
        movement(102, 'ADJUST', 'ERP', 'TEST-GEN', -11)
      }
    );
    Test.stopTest();

    Assert.areEqual(2, res.get('errors'), '오류 2');
    Assert.areEqual('UNKNOWN_CODE', resultAt(res, 0).get('code'), '없는 코드');
    Assert.areEqual('NEGATIVE_STOCK', resultAt(res, 1).get('code'), '0 미만');
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM ErpInboundLog__c WHERE Result__c = 'Error'],
      '오류 기록 2'
    );
  }

  // 불허: 건별 형식 오류 → INVALID(반영·기록 없음), 나머지 정상 건은 반영
  @isTest
  static void rejectInvalidItemsOnly() {
    Map<String, Object> textQuantity = movement(
      103,
      'RECEIPT',
      'ERP',
      'TEST-GEN',
      '5'
    );
    Map<String, Object> badUnit = movement(
      104,
      'RECEIPT',
      'ERP',
      'TEST-GEN',
      1
    );
    badUnit.put('unit', 'box');
    Map<String, Object> badCode = movement(
      105,
      'RECEIPT',
      'ERP',
      'TEST GEN!',
      1
    );
    Map<String, Object> badDate = movement(
      106,
      'RECEIPT',
      'ERP',
      'TEST-GEN',
      1
    );
    badDate.put('createdAt', '어제');

    Test.startTest();
    Map<String, Object> res = postMovements(
      new List<Object>{
        movement(101, 'RECEIPT', 'ERP', 'TEST-GEN', 2),
        movement(1.5, 'RECEIPT', 'ERP', 'TEST-GEN', 1),
        movement(102, 'MOVE', 'ERP', 'TEST-GEN', 1),
        textQuantity,
        badUnit,
        badCode,
        badDate,
        movement(107, 'RECEIPT', 'ERP', 'TEST-GEN', 0.123),
        movement(108, 'RECEIPT', 'ERP', 'TEST-GEN', 0),
        'not-an-object'
      }
    );
    Test.stopTest();

    Assert.areEqual(200, res.get('_status'), '요청 자체는 받음');
    Assert.areEqual(1, res.get('applied'), '정상 1건만 반영');
    Assert.areEqual(9, res.get('invalid'), '형식 오류 9건');
    String idMessage = (String) resultAt(res, 1).get('message');
    Assert.isTrue(
      idMessage.startsWith('movements[1]: id'),
      '어느 항목·필드인지: ' + idMessage
    );
    Assert.areEqual(VAN_GENERAL_QTY + 2, vanQty('TEST-GEN'), '+2만');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM ErpInboundLog__c],
      '형식 오류는 기록 안 함'
    );
  }

  // 불허: 요청 전체 오류 → 400 (본문 없음·JSON 아님·movements 없음·빈 배열·201건)
  @isTest
  static void rejectBadRequests() {
    List<Object> tooMany = new List<Object>();
    for (Integer i = 1; i <= ErpMovementResource.MAX_MOVEMENTS + 1; i++) {
      tooMany.add(movement(i, 'RECEIPT', 'ERP', 'TEST-GEN', 1));
    }

    Test.startTest();
    List<Map<String, Object>> responses = new List<Map<String, Object>>{
      post(null),
      post('not json'),
      post('{"items":[]}'),
      post('[1,2]'),
      postMovements(new List<Object>()),
      postMovements(tooMany)
    };
    Test.stopTest();

    for (Map<String, Object> res : responses) {
      Assert.areEqual(400, res.get('_status'), 'HTTP 400: ' + res);
      Assert.areEqual(
        'BAD_REQUEST',
        ((Map<String, Object>) res.get('error')).get('code'),
        '오류 코드'
      );
    }
    Assert.areEqual(VAN_GENERAL_QTY, vanQty('TEST-GEN'), '재고 그대로');
  }

  // 벌크: 200건(상한) 한 번에 → 모두 반영, 같은 재고에 순서대로 누적
  @isTest
  static void bulk200Movements() {
    List<Object> movements = new List<Object>();
    for (Integer i = 1; i <= ErpMovementResource.MAX_MOVEMENTS; i++) {
      movements.add(movement(BASELINE + i, 'RECEIPT', 'ERP', 'TEST-GEN', 0.5));
    }

    Test.startTest();
    Map<String, Object> res = postMovements(movements);
    Test.stopTest();

    Assert.areEqual(200, res.get('applied'), '200건 반영');
    Assert.areEqual(
      VAN_GENERAL_QTY + 100,
      vanQty('TEST-GEN'),
      '10 + 0.5 × 200'
    );
  }

  // 정상: 푸시로 먼저 받은 변동을 매시 가져오기가 다시 만나도 건너뜀 → 한 번만 반영, 가져오기 기준 번호는 앞으로
  @isTest
  static void normalPullAfterPushSkipsDuplicate() {
    postMovements(
      new List<Object>{ movement(101, 'RECEIPT', 'ERP', 'TEST-GEN', 5) }
    );
    Test.setMock(HttpCalloutMock.class, new SingleMovementMock());

    Test.startTest();
    ErpStockSyncService.SyncResult result = ErpStockSyncService.syncNextPage();
    Test.stopTest();

    Assert.areEqual(1, result.duplicates, '가져오기에서 중복');
    Assert.areEqual(0, result.applied, '다시 반영 안 됨');
    Assert.areEqual(VAN_GENERAL_QTY + 5, vanQty('TEST-GEN'), '+5 한 번만');
    Assert.areEqual(
      101,
      ErpStockSyncService.getLastMovementId(),
      '기준 번호 101로'
    );
  }

  // DESC: 가져오기용 가짜 ERP — 101번 입고 1건
  private class SingleMovementMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(
        JSON.serialize(
          new Map<String, Object>{
            'items' => new List<Object>{
              movement(101, 'RECEIPT', 'ERP', 'TEST-GEN', 5)
            },
            'lastId' => 101,
            'hasMore' => false,
            'latestId' => 101
          }
        )
      );
      return response;
    }
  }
}
