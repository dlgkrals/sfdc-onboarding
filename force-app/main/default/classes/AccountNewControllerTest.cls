/**
 * @description AccountNewController 테스트 + 고객사 등록 화면(새로 만들기 재정의) 저장 경로
 *              유형 API 이름 조회, 개인은 사업자번호 없이 저장, 사업자번호 형식 오류는 검증 규칙이 거부, 상담원·기사 권한
 * @layer       Test
 * @author      Edwin
 * @date        2026-10-14
 * ----------------------------------------------------------------------------
 * 변경 이력
 * 버전    날짜          작성자    내용
 * 1.0    2026-10-14    Edwin     최초 작성 (D8 고객사·사업장 새로 만들기 재정의)
 * ----------------------------------------------------------------------------
 * @see AccountNewController, accountNew (LWC)
 */
@isTest
private class AccountNewControllerTest {
  @TestSetup
  static void setupData() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.createUser('HG_CallCenter', false);
      TestDataFactory.createUser('HG_Technician', true);
    }
  }

  private static User getUser(String permissionSet) {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :('테스트 ' + permissionSet)
      LIMIT 1
    ];
  }

  private static Id recordTypeId(String developerName) {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  // 정상: 상담원 권한으로 고른 유형의 API 이름을 돌려줌 (화면이 개인이면 사업자번호를 숨김)
  @isTest
  static void normalCallCenterGetsDeveloperName() {
    String individual;
    String corporation;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      individual = AccountNewController.getRecordTypeDeveloperName(
        recordTypeId('Individual')
      );
      corporation = AccountNewController.getRecordTypeDeveloperName(
        recordTypeId('Corporation')
      );
    }
    Test.stopTest();

    Assert.areEqual('Individual', individual, '개인');
    Assert.areEqual('Corporation', corporation, '법인');
  }

  // 불허: 유형 Id가 없거나 고객사 유형이 아니면 null (화면은 사업자번호를 보여 둠)
  @isTest
  static void rejectMissingOrOtherIdReturnsNull() {
    Account other = TestDataFactory.createAccount();

    Test.startTest();
    String none = AccountNewController.getRecordTypeDeveloperName(null);
    String notType = AccountNewController.getRecordTypeDeveloperName(other.Id);
    Test.stopTest();

    Assert.isNull(none, 'null');
    Assert.isNull(notType, '레코드 유형이 아닌 Id');
  }

  // 정상: 화면 저장 경로 — 상담원이 개인 고객사를 사업자번호 없이 등록 (청구지는 화면 규칙대로)
  @isTest
  static void normalCallCenterCreatesIndividualWithoutBusinessNumber() {
    Account created = new Account(
      Name = '홍길동',
      RecordTypeId = recordTypeId('Individual'),
      BillingCountryCode = 'KR',
      BillingCity = '평택시',
      BillingStreet = '경기도 평택시 평택로 32, 101호',
      BillingPostalCode = '17901'
    );

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      Database.insert(created, true, AccessLevel.USER_MODE);
    }
    Test.stopTest();

    Assert.isNotNull(created.Id, '저장됨');
  }

  // 불허: 법인인데 사업자번호 형식이 틀리면 기존 검증 규칙이 거부 (화면은 오류를 토스트로 보여 줌)
  @isTest
  static void rejectCorporationWithInvalidBusinessNumber() {
    Account invalid = new Account(
      Name = '형식 오류 법인',
      RecordTypeId = recordTypeId('Corporation'),
      BusinessRegistrationNumber__c = '12-34',
      BillingContactEmail__c = 'billing@example.com'
    );
    Boolean failed = false;

    Test.startTest();
    System.runAs(getUser('HG_CallCenter')) {
      try {
        Database.insert(invalid, true, AccessLevel.USER_MODE);
      } catch (DmlException e) {
        failed = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(failed, '검증 규칙 거부');
  }

  // 불허: 협력 기사는 고객사를 만들 수 없음 (고객사 오브젝트 권한 없음)
  @isTest
  static void rejectTechnicianCannotCreateAccount() {
    Boolean failed = false;

    Test.startTest();
    System.runAs(getUser('HG_Technician')) {
      try {
        Database.insert(
          new Account(
            Name = '기사 등록 시도',
            RecordTypeId = recordTypeId('Individual')
          ),
          true,
          AccessLevel.USER_MODE
        );
      } catch (Exception e) {
        failed = true;
      }
    }
    Test.stopTest();

    Assert.isTrue(failed, '기사 생성 거부');
  }
}
