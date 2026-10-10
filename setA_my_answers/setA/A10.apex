Set<String> brns = new Set<String>{'2208100137', '2208100822', '0000000000'};
Map<String, Account> accountsByBrn = new Map<String, Account>();
for (Account a : [SELECT Id, Name, BusinessRegistrationNumber__c,
                         (SELECT Id FROM AccountCustomerSites__r)
                  FROM Account WHERE BusinessRegistrationNumber__c IN :brns]) {
    accountsByBrn.put(a.BusinessRegistrationNumber__c, a);
}
for (String b : brns) {
    Account a = accountsByBrn.get(b);
    System.debug(b + ' → ' + (a == null ? '없음' : a.Name + ' 사업장 ' + a.AccountCustomerSites__r.size()));
}
System.debug('SOQL: ' + Limits.getQueries());   // 1
