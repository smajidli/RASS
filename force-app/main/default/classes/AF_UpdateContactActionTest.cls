@IsTest
private class AF_UpdateContactActionTest {

    @IsTest
    static void testUpdateByContactId() {
        Account a = new Account(Name='Test Account A', AccountNumber='A-001');
        insert a;

        Contact c = new Contact(FirstName='Jane', LastName='Doe', Email='jane@test.com', AccountId=a.Id);
        insert c;

        AF_UpdateContactAction.Request req = new AF_UpdateContactAction.Request();
        req.contactId = c.Id;
        req.newPhone = '416-555-1234';
        req.newTitle = 'Controller';

        Test.startTest();
        List<AF_UpdateContactAction.Response> res =
            AF_UpdateContactAction.updateContact(new List<AF_UpdateContactAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].done);
        System.assertEquals(c.Id, res[0].contactId);

        Contact after = [SELECT Phone, Title FROM Contact WHERE Id = :c.Id];
        System.assertEquals('416-555-1234', after.Phone);
        System.assertEquals('Controller', after.Title);
    }

    @IsTest
    static void testAmbiguousEmailReturnsDoneFalse() {
        Account a = new Account(Name='Test Account B', AccountNumber='B-001');
        insert a;

        Contact c1 = new Contact(FirstName='A', LastName='One', Email='dup@test.com', AccountId=a.Id);
        Contact c2 = new Contact(FirstName='B', LastName='Two', Email='dup@test.com', AccountId=a.Id);
        insert new List<Contact>{ c1, c2 };

        AF_UpdateContactAction.Request req = new AF_UpdateContactAction.Request();
        req.contactEmail = 'dup@test.com';
        req.newPhone = '647-555-0000';

        Test.startTest();
        List<AF_UpdateContactAction.Response> res =
            AF_UpdateContactAction.updateContact(new List<AF_UpdateContactAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].done);
        System.assert(res[0].message != null && res[0].message.contains('Multiple contacts'), 'Expected ambiguity message');
    }
}