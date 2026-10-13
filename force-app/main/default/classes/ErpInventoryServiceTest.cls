/**
 * @description ErpInventoryService · ErpSyncQueueable · ProductConsumedTriggerHandler(ERP 부분) 테스트
 *              HttpCalloutMock으로 ERP 응답(성공·재고 부족·서버 오류·인증 오류·시간 초과)을 흉내 냄
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-13
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-13    Edwin     최초 작성 (D7 ERP 연동 5번)
 * 1.1    2026-10-13    Edwin     삭제 시 재고 되돌림·복원 거부 테스트 (decision-log 11 A안)
 * 1.2    2026-10-13    Edwin     ERP 이상 응답(읽을 수 없음·결과 누락·400)·15자리 Id·단위 표시·기사 삭제 테스트 (D7 ERP 연동 8번)
 * ----------------------------------------------------------------------------
 * @see ErpInventoryService
 */
@isTest
private class ErpInventoryServiceTest {
  private static final String VAN_CODE = 'VAN-TEST';
  private static final Decimal VAN_QUANTITY = 300;

  // DESC: 가짜 ERP. 요청의 refId마다 정해 둔 방식으로 응답하고 호출 횟수를 셈
  private class ErpMock implements HttpCalloutMock {
    String mode = 'OK'; // OK · REJECT · HTTP · THROW · RAW(본문 그대로) · EMPTY(결과 없음)
    Integer statusCode = 200;
    String rejectCode = 'INSUFFICIENT_STOCK';
    String rawBody;
    // DESC: ERP가 15자리 Id로 돌려주는 경우 흉내
    Boolean shortRefIds = false;
    Decimal remainingQty;
    Integer calls = 0;
    List<Object> lastItems;

    public HttpResponse respond(HttpRequest request) {
      calls++;
      if (mode == 'THROW') {
        throw new CalloutException('Read timed out');
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      if (mode == 'HTTP') {
        response.setBody(
          '{"error":"MAINTENANCE","message":"ERP 점검 중입니다."}'
        );
        return response;
      }
      if (mode == 'RAW') {
        response.setBody(rawBody);
        return response;
      }
      lastItems = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
          request.getBody()
        ))
        .get('items');
      List<Object> results = new List<Object>();
      for (Object raw : lastItems) {
        Map<String, Object> item = (Map<String, Object>) raw;
        String refId = String.valueOf(item.get('refId'));
        if (mode == 'EMPTY') {
          continue;
        }
        if (mode == 'OK') {
          results.add(
            new Map<String, Object>{
              'refId' => shortRefIds ? refId.left(15) : refId,
              'status' => 'OK',
              'remainingQty' => remainingQty,
              'unit' => 'Each'
            }
          );
        } else {
          results.add(
            new Map<String, Object>{
              'refId' => item.get('refId'),
              'status' => 'REJECTED',
              'code' => rejectCode,
              'message' => '재고가 부족합니다.'
            }
          );
        }
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
    Account account = TestDataFactory.createAccount();
    CustomerSite__c site = TestDataFactory.createSite(account.Id);
    List<Asset> assets = TestDataFactory.createAssets(
      account.Id,
      site.Id,
      'TEST-ERP-',
      1
    );
    TestDataFactory.createWorkOrders(TestDataFactory.createCases(assets, 1));
    Map<String, ProductItem> itemsByFamily = TestDataFactory.createVanStock(
      TestDataFactory.createProducts(),
      VAN_QUANTITY
    );
    // DESC: ERP 위치 코드가 있어야 전송 대상
    Schema.Location van = [
      SELECT Id
      FROM Location
      WHERE Id = :itemsByFamily.values()[0].LocationId
    ];
    van.ErpLocationCode__c = VAN_CODE;
    update van;
  }

  private static WorkOrder getWorkOrder() {
    return [SELECT Id FROM WorkOrder LIMIT 1];
  }

  private static ProductItem getItem(String family) {
    // DESC: 테스트 차량(TestDataFactory.VAN_NAME) 재고. ERP 위치 코드를 지우는 테스트가 있어 이름으로 찾음
    return [
      SELECT Id, QuantityOnHand
      FROM ProductItem
      WHERE
        Product2.Family = :family
        AND Location.Name = :TestDataFactory.VAN_NAME
      LIMIT 1
    ];
  }

  private static ProductConsumed reload(Id id) {
    return [
      SELECT
        ErpSyncStatus__c,
        ErpSyncMessage__c,
        ErpSyncedAt__c,
        ErpRetryCount__c,
        ErpRemainingQty__c,
        InventoryMismatch__c
      FROM ProductConsumed
      WHERE Id = :id
    ];
  }

  // DESC: 사용 부품 1건 저장 → stopTest에서 Queueable이 ERP 전송
  private static ProductConsumed insertOneAndSync(
    ErpMock mock,
    Decimal quantity
  ) {
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    ProductConsumed part = TestDataFactory.buildPart(
      getWorkOrder().Id,
      getItem('Compressor').Id
    );
    part.QuantityConsumed = quantity;
    Test.startTest();
    insert part;
    Test.stopTest();
    return reload(part.Id);
  }

  // 정상: ERP 차감 성공 → 완료, 남은 수량 기록, Salesforce 수량과 같으면 불일치 아님, 요청에 위치·부품 코드·수량
  @isTest
  static void normalSuccessMarksSynced() {
    ErpMock mock = new ErpMock();
    mock.remainingQty = VAN_QUANTITY - 1;

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Synced', after.ErpSyncStatus__c, '완료');
    Assert.areEqual(
      VAN_QUANTITY - 1,
      after.ErpRemainingQty__c,
      'ERP 남은 수량 기록'
    );
    Assert.isFalse(
      after.InventoryMismatch__c,
      'Salesforce 표준 차감 후 수량과 같음'
    );
    Assert.isNotNull(after.ErpSyncedAt__c, '전송 일시');
    Assert.areEqual(0, after.ErpRetryCount__c, '재시도 없음');
    Assert.areEqual(1, mock.calls, '콜아웃 1번');
    Map<String, Object> sent = (Map<String, Object>) mock.lastItems[0];
    Assert.areEqual(VAN_CODE, sent.get('locationCode'), 'ERP 위치 코드');
    Assert.areEqual('TEST-CMP', sent.get('partCode'), 'ERP 부품 코드');
    Assert.areEqual(
      1,
      Decimal.valueOf(String.valueOf(sent.get('quantity'))),
      '수량'
    );
  }

  // 정상: ERP 남은 수량이 Salesforce 재고와 다르면 불일치 체크, Salesforce 수량은 그대로
  @isTest
  static void normalMismatchFlaggedWithoutFixingQuantity() {
    ErpMock mock = new ErpMock();
    mock.remainingQty = 50;

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Synced', after.ErpSyncStatus__c, '완료');
    Assert.isTrue(after.InventoryMismatch__c, '불일치 표시');
    Assert.areEqual(
      VAN_QUANTITY - 1,
      getItem('Compressor').QuantityOnHand,
      'Salesforce 수량은 표준 차감 그대로 (Apex가 덮어쓰지 않음)'
    );
  }

  // 불허: ERP 재고 부족 → 확인 필요, 코드가 메시지에, 재시도 대상 아님
  @isTest
  static void rejectInsufficientStockNeedsReview() {
    ErpMock mock = new ErpMock();
    mock.mode = 'REJECT';

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('NeedsReview', after.ErpSyncStatus__c, '확인 필요');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[INSUFFICIENT_STOCK]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 불허: ERP 장애(503)·인증 오류(401) → 실패(일시적), 재시도 횟수 0
  @isTest
  static void rejectServerAndAuthErrorsAreTransient() {
    ErpMock mock = new ErpMock();
    mock.mode = 'HTTP';
    mock.statusCode = 503;

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Failed', after.ErpSyncStatus__c, '503 → 실패');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[HTTP_503]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
    Assert.areEqual(0, after.ErpRetryCount__c, '첫 전송은 재시도 아님');

    mock.statusCode = 401;
    ErpInventoryService.sendConsumed(
      new Set<Id>{ [SELECT Id FROM ProductConsumed LIMIT 1].Id },
      false
    );
    Assert.isTrue(
      reload([SELECT Id FROM ProductConsumed LIMIT 1].Id)
        .ErpSyncMessage__c.startsWith('[HTTP_401]'),
      '401 → 실패(키를 고치면 재전송으로 회복)'
    );
  }

  // 불허: 시간 초과·연결 실패 → 실패
  @isTest
  static void rejectTimeoutIsTransient() {
    ErpMock mock = new ErpMock();
    mock.mode = 'THROW';

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Failed', after.ErpSyncStatus__c, '실패');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[CONNECTION]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 불허: 재전송에서도 실패해 상한(3회) 도달 → 확인 필요 [RETRY_EXHAUSTED], 그 전까지는 실패 + 횟수 증가
  @isTest
  static void rejectRetryExhaustedNeedsReview() {
    ErpMock mock = new ErpMock();
    mock.mode = 'HTTP';
    mock.statusCode = 503;
    ProductConsumed part = insertOneAndSync(mock, 1);
    Id partId = [SELECT Id FROM ProductConsumed LIMIT 1].Id;
    Integer maxRetry = ErpInventoryService.getMaxRetry();

    for (Integer i = 1; i < maxRetry; i++) {
      ErpInventoryService.sendConsumed(new Set<Id>{ partId }, true);
      ProductConsumed mid = reload(partId);
      Assert.areEqual('Failed', mid.ErpSyncStatus__c, i + '회째: 아직 실패');
      Assert.areEqual(i, mid.ErpRetryCount__c, i + '회째 횟수');
    }
    ErpInventoryService.sendConsumed(new Set<Id>{ partId }, true);
    ProductConsumed last = reload(partId);

    Assert.areEqual(
      'NeedsReview',
      last.ErpSyncStatus__c,
      '상한 초과 → 확인 필요'
    );
    Assert.areEqual(maxRetry, last.ErpRetryCount__c, '횟수 = 상한');
    Assert.isTrue(
      last.ErpSyncMessage__c.startsWith('[RETRY_EXHAUSTED]'),
      '메시지: ' + last.ErpSyncMessage__c
    );
  }

  // 불허: ERP 위치 코드가 없는 재고 → 보내지 않고 확인 필요 [MISSING_CODE]
  @isTest
  static void rejectMissingErpCodeWithoutCallout() {
    Schema.Location van = [
      SELECT Id
      FROM Location
      WHERE ErpLocationCode__c = :VAN_CODE
    ];
    van.ErpLocationCode__c = null;
    update van;
    ErpMock mock = new ErpMock();

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('NeedsReview', after.ErpSyncStatus__c, '확인 필요');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[MISSING_CODE]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
    Assert.areEqual(0, mock.calls, '콜아웃 없음');
  }

  // 벌크: 사용 부품 200건 → Queueable 1개, 콜아웃 1번, 전부 완료
  @isTest
  static void bulk200PartsOneCallout() {
    ErpMock mock = new ErpMock();
    mock.remainingQty = 100;
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    Id workOrderId = getWorkOrder().Id;
    Id itemId = getItem('General').Id;
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 200; i++) {
      parts.add(TestDataFactory.buildPart(workOrderId, itemId));
    }

    Test.startTest();
    insert parts;
    Test.stopTest();

    Assert.areEqual(1, mock.calls, '200건 = 콜아웃 1번');
    Assert.areEqual(200, mock.lastItems.size(), '한 요청에 200건');
    Assert.areEqual(
      200,
      [SELECT COUNT() FROM ProductConsumed WHERE ErpSyncStatus__c = 'Synced'],
      '200건 완료'
    );
  }

  // 정상: 협력 기사 사용자가 자기 차량 재고로 사용 부품을 실제 저장 → 판정 + ERP 전송까지 (기사 권한으로 Queueable 실행)
  private static User getTechnician() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = '테스트 HG_Technician'
      LIMIT 1
    ];
  }

  // DESC: 기사 소유 출동 + 기사 차량(ERP 코드 VAN-TECH) + 압축기 재고 10. 결과 Map 키 workOrder / item
  private static Map<String, SObject> createTechnicianStock(User technician) {
    WorkOrder source = [SELECT CaseId, AssetId FROM WorkOrder LIMIT 1];
    WorkOrder techWorkOrder = new WorkOrder(
      CaseId = source.CaseId,
      AssetId = source.AssetId,
      Subject = '기사 출동',
      Status = 'Assigned',
      OwnerId = technician.Id
    );
    insert techWorkOrder;
    Schema.Location techVan = new Schema.Location(
      Name = '기사 차량',
      LocationType = 'Van',
      IsInventoryLocation = true,
      OwnerId = technician.Id,
      ErpLocationCode__c = 'VAN-TECH'
    );
    insert techVan;
    ProductItem techItem = new ProductItem(
      LocationId = techVan.Id,
      Product2Id = [SELECT Id FROM Product2 WHERE Family = 'Compressor' LIMIT 1]
      .Id,
      QuantityOnHand = 10,
      OwnerId = technician.Id
    );
    insert techItem;
    return new Map<String, SObject>{
      'workOrder' => techWorkOrder,
      'item' => techItem
    };
  }

  @isTest
  static void normalTechnicianSaveSyncsToErp() {
    User technician = getTechnician();
    Map<String, SObject> stock = createTechnicianStock(technician);
    WorkOrder techWorkOrder = (WorkOrder) stock.get('workOrder');
    ProductItem techItem = (ProductItem) stock.get('item');

    ErpMock mock = new ErpMock();
    mock.remainingQty = 9;
    Test.setMock(HttpCalloutMock.class, mock);
    ErpInventoryService.enqueueInTests = true;
    ProductConsumed part;

    System.runAs(technician) {
      part = TestDataFactory.buildPart(techWorkOrder.Id, techItem.Id);
      Test.startTest();
      insert part;
      Test.stopTest();
    }

    ProductConsumed after = [
      SELECT
        ErpSyncStatus__c,
        ErpRemainingQty__c,
        InventoryMismatch__c,
        AutoChargeType__c
      FROM ProductConsumed
      WHERE Id = :part.Id
    ];
    Assert.areEqual('Synced', after.ErpSyncStatus__c, '기사 저장 → ERP 완료');
    Assert.areEqual(9, after.ErpRemainingQty__c, 'ERP 남은 수량');
    Assert.isFalse(after.InventoryMismatch__c, '기사 차량 10 → 9, ERP와 같음');
    Assert.isNotNull(after.AutoChargeType__c, '유·무상 판정도 그대로 동작');
    Assert.areEqual(
      'VAN-TECH',
      ((Map<String, Object>) mock.lastItems[0]).get('locationCode'),
      '기사 차량 위치 코드로 전송'
    );
  }

  // 정상: 실패 상태·영구적 실패로 확인 필요인 사용 부품은 삭제 가능, 삭제한 수량만큼 재고가 돌아옴 (현재 + 삭제 수량)
  @isTest
  static void normalDeleteAllowedWhenNotReflected() {
    ProductConsumed failed = TestDataFactory.buildPart(
      getWorkOrder().Id,
      getItem('General').Id
    );
    failed.QuantityConsumed = 2;
    ProductConsumed rejected = TestDataFactory.buildPart(
      getWorkOrder().Id,
      getItem('General').Id
    );
    insert new List<ProductConsumed>{ failed, rejected };
    Assert.areEqual(
      VAN_QUANTITY - 3,
      getItem('General').QuantityOnHand,
      '표준 차감: 2 + 1'
    );
    failed.ErpSyncStatus__c = 'Failed';
    rejected.ErpSyncStatus__c = 'NeedsReview';
    rejected.ErpSyncMessage__c = '[INSUFFICIENT_STOCK] 재고가 부족합니다.';
    // DESC: ERP 필드는 사용자에게 읽기 전용(Apex만 씀) → 테스트 데이터 준비도 시스템 모드
    Database.update(
      new List<ProductConsumed>{ failed, rejected },
      AccessLevel.SYSTEM_MODE
    );

    Test.startTest();
    delete new List<ProductConsumed>{ failed, rejected };
    Test.stopTest();

    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM ProductConsumed
        WHERE Id IN (:failed.Id, :rejected.Id)
      ],
      '둘 다 삭제됨'
    );
    Assert.areEqual(
      VAN_QUANTITY,
      getItem('General').QuantityOnHand,
      '삭제한 2 + 1만큼 되돌림'
    );
  }

  // 불허: 완료·대기·재시도 초과 사용 부품은 삭제 거부 (안내 문구)
  @isTest
  static void rejectDeleteWhenReflectedOrUnknown() {
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 3; i++) {
      parts.add(
        TestDataFactory.buildPart(getWorkOrder().Id, getItem('General').Id)
      );
    }
    insert parts;
    parts[0].ErpSyncStatus__c = 'Synced';
    parts[1].ErpSyncStatus__c = 'Pending';
    parts[2].ErpSyncStatus__c = 'NeedsReview';
    parts[2].ErpSyncMessage__c = '[RETRY_EXHAUSTED] 재시도 3회 초과';
    Database.update(parts, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    List<Database.DeleteResult> results = Database.delete(parts, false);
    Test.stopTest();

    for (Database.DeleteResult r : results) {
      Assert.isFalse(r.isSuccess(), '삭제 거부');
      Assert.areEqual(
        System.Label.MSG_ERP_DELETE_BLOCKED,
        r.getErrors()[0].getMessage(),
        '안내 문구'
      );
    }
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM ProductConsumed WHERE Id IN :parts],
      '3건 그대로'
    );
    Assert.areEqual(
      VAN_QUANTITY - 3,
      getItem('General').QuantityOnHand,
      '거부된 건은 재고도 그대로'
    );
  }

  // 불허: 삭제한 사용 부품을 휴지통에서 복원하면 거부 (잘못 지웠으면 새로 입력)
  @isTest
  static void rejectUndeleteDeletedPart() {
    ProductConsumed part = TestDataFactory.buildPart(
      getWorkOrder().Id,
      getItem('General').Id
    );
    insert part;
    part.ErpSyncStatus__c = 'Failed';
    Database.update(part, AccessLevel.SYSTEM_MODE);
    delete part;

    Test.startTest();
    Database.UndeleteResult result = Database.undelete(part.Id, false);
    Test.stopTest();

    Assert.isFalse(result.isSuccess(), '복원 거부');
    Assert.areEqual(
      System.Label.MSG_ERP_UNDELETE_BLOCKED,
      result.getErrors()[0].getMessage(),
      '안내 문구'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ProductConsumed WHERE Id = :part.Id],
      '복원되지 않음'
    );
    Assert.areEqual(
      VAN_QUANTITY,
      getItem('General').QuantityOnHand,
      '삭제 때 되돌린 재고 그대로'
    );
  }

  // 벌크: 200건 한 번에 삭제(실패 100 + 완료 100, 부분 성공) → 실패 100건만 삭제·재고 되돌림, 완료 100건은 거부
  @isTest
  static void bulkDelete200RestoresOnlyAllowed() {
    Id workOrderId = getWorkOrder().Id;
    Id itemId = getItem('General').Id;
    List<ProductConsumed> parts = new List<ProductConsumed>();
    for (Integer i = 0; i < 200; i++) {
      parts.add(TestDataFactory.buildPart(workOrderId, itemId));
    }
    insert parts;
    for (Integer i = 0; i < 200; i++) {
      parts[i].ErpSyncStatus__c = Math.mod(i, 2) == 0 ? 'Failed' : 'Synced';
    }
    Database.update(parts, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    List<Database.DeleteResult> results = Database.delete(parts, false);
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Integer deleted = 0;
    for (Database.DeleteResult r : results) {
      deleted += r.isSuccess() ? 1 : 0;
    }
    Assert.areEqual(100, deleted, '실패 100건만 삭제');
    Assert.areEqual(
      VAN_QUANTITY - 100,
      getItem('General').QuantityOnHand,
      '300 - 200 + 100 (삭제된 100건만 되돌림)'
    );
    Assert.isTrue(queries <= 5, '200건이어도 조회 몇 번: ' + queries);
  }

  // 불허: ERP가 200인데 읽을 수 없는 본문을 주면 실패(일시적) [BAD_RESPONSE] → 재전송 대상
  @isTest
  static void rejectUnreadableResponseIsTransient() {
    ErpMock mock = new ErpMock();
    mock.mode = 'RAW';
    mock.rawBody = '<html>Bad Gateway</html>';

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Failed', after.ErpSyncStatus__c, '실패');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[BAD_RESPONSE]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 불허: ERP 응답에 이 건의 결과가 빠지면 실패 [NO_RESULT] (반영 여부를 모르므로 재전송, ERP가 중복은 무시)
  @isTest
  static void rejectMissingResultIsTransient() {
    ErpMock mock = new ErpMock();
    mock.mode = 'EMPTY';

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Failed', after.ErpSyncStatus__c, '실패');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[NO_RESULT]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 불허: HTTP 400(요청 형식 오류)은 다시 보내도 같으므로 확인 필요
  @isTest
  static void rejectBadRequestNeedsReview() {
    ErpMock mock = new ErpMock();
    mock.mode = 'HTTP';
    mock.statusCode = 400;

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('NeedsReview', after.ErpSyncStatus__c, '확인 필요');
    Assert.isTrue(
      after.ErpSyncMessage__c.startsWith('[HTTP_400]'),
      '메시지: ' + after.ErpSyncMessage__c
    );
  }

  // 정상: ERP가 15자리 Id로 돌려줘도 같은 건으로 찾아 완료, 화면 표시는 "남은 수량 + 단위 표기"(수식의 Custom Label)
  @isTest
  static void normalShortIdMatchedAndUnitShown() {
    update new ProductItem(
      Id = getItem('Compressor').Id,
      QuantityUnitOfMeasure = 'Each'
    );
    ErpMock mock = new ErpMock();
    mock.shortRefIds = true;
    mock.remainingQty = VAN_QUANTITY - 1;

    ProductConsumed after = insertOneAndSync(mock, 1);

    Assert.areEqual('Synced', after.ErpSyncStatus__c, '15자리 Id로도 완료');
    String shown = [
      SELECT fmErpRemainingQty__c
      FROM ProductConsumed
      WHERE Id = :after.Id
    ]
    .fmErpRemainingQty__c;
    Assert.isTrue(
      shown.startsWith(String.valueOf((VAN_QUANTITY - 1).intValue())) &&
      shown.endsWith(' ' + System.Label.MISC_UNIT_EACH),
      '표시: ' + shown
    );
  }

  // 정상: 협력 기사가 자기 차량 재고로 입력한 실패 건을 직접 삭제 → 재고 되돌림 (기사 권한으로 삭제 + 시스템 보정)
  @isTest
  static void normalTechnicianDeleteRestoresStock() {
    User technician = getTechnician();
    Map<String, SObject> stock = createTechnicianStock(technician);
    Id techItemId = stock.get('item').Id;
    ProductConsumed part;
    System.runAs(technician) {
      part = TestDataFactory.buildPart(stock.get('workOrder').Id, techItemId);
      part.QuantityConsumed = 3;
      insert part;
    }
    part.ErpSyncStatus__c = 'Failed';
    Database.update(part, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    System.runAs(technician) {
      delete part;
    }
    Test.stopTest();

    Assert.areEqual(
      10,
      [SELECT QuantityOnHand FROM ProductItem WHERE Id = :techItemId]
      .QuantityOnHand,
      '10 - 3 + 3'
    );
  }
}
