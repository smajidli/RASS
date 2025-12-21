public with sharing class AF_CreateContactAction {

    public class Request {
        // --- Name inputs ---
        @InvocableVariable(label='Full Name' description='Optional. Full name in one string (example: "Stephen Ayers"). If lastName is missing, the action will split this into first/last.' required=false)
        public String fullName;

        @InvocableVariable(label='First Name' description='Optional. Contact.FirstName. Example: Stephen.' required=false)
        public String firstName;

        @InvocableVariable(label='Last Name' description='Required. Contact.LastName. Example: Ayers.' required=false)
        public String lastName;

        // --- Other contact fields ---
        @InvocableVariable(label='Email' description='Optional. Contact.Email. Example: stephen.ayers98@gmail.com.' required=false)
        public String email;

        @InvocableVariable(label='Phone' description='Optional. Contact.Phone.' required=false)
        public String phone;

        @InvocableVariable(label='Title' description='Optional. Contact.Title.' required=false)
        public String title;

        @InvocableVariable(label='Level' description='Optional. Contact.Level__c value (example: Primary/Secondary/Tertiary) if the field exists.' required=false)
        public String level;

        @InvocableVariable(label='Languages' description='Optional. Contact.Languages__c value. If multi-select, use semicolon-separated values.' required=false)
        public String languages;

        // --- Optional account association ---
        @InvocableVariable(label='Account Id' description='Optional. 18-character Account Id (preferred) to link the contact to an account.' required=false)
        public String accountId;

        @InvocableVariable(label='Account Number' description='Optional. Exact AccountNumber to locate the account.' required=false)
        public String accountNumber;

        @InvocableVariable(label='Account Name' description='Optional. Account name search text (contains). Example: Burlington.' required=false)
        public String accountName;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when the contact is created; false when the user must choose an Account Id due to multiple matches.')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML result or disambiguation list. Show as-is.')
        public String message;

        @InvocableVariable(label='Contact Id' description='Created Contact Id when successful.')
        public String contactId;

        @InvocableVariable(label='Account Id' description='Linked Account Id when provided/resolved.')
        public String accountId;
    }

    @InvocableMethod(
        label='Create Contact'
        description='Creates one Contact and optionally links it to an Account. Accepts either first/last name or a fullName string.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        Boolean hasLevel = Schema.sObjectType.Contact.fields.getMap().containsKey('Level__c');
        Boolean hasLanguages = Schema.sObjectType.Contact.fields.getMap().containsKey('Languages__c');

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;

            // --- Normalize / derive names ---
            deriveNames(req);

            if (isBlank(req.lastName)) {
                res.message = '<p>Please provide the contact last name.</p>';
                outList.add(res);
                continue;
            }

            // Resolve account (optional)
            Account a = resolveAccount(req, res, 6);
            if (a == null && needsChoice(res)) {
                outList.add(res);
                continue;
            }

            Contact c = new Contact();
            if (!isBlank(req.firstName)) c.FirstName = req.firstName.trim();
            c.LastName = req.lastName.trim();

            if (!isBlank(req.email)) c.Email = req.email.trim();
            if (!isBlank(req.phone)) c.Phone = req.phone.trim();
            if (!isBlank(req.title)) c.Title = req.title.trim();

            if (hasLevel && !isBlank(req.level)) c.put('Level__c', req.level.trim());
            if (hasLanguages && !isBlank(req.languages)) c.put('Languages__c', req.languages.trim());

            if (a != null) {
                c.AccountId = a.Id;
                res.accountId = a.Id;
            }

            try {
                SObjectAccessDecision ins = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ c });
                List<SObject> safe = ins.getRecords();
                if (safe.isEmpty()) {
                    res.done = true;
                    res.message = '<p>Contact creation failed due to access restrictions. Please confirm you have permission to create Contacts.</p>';
                    outList.add(res);
                    continue;
                }

                insert safe;

                Id createdId = ((Contact)safe[0]).Id;

                Contact created = [
                    SELECT Id, Name, Email, Phone, Title, AccountId, Account.Name, Account.AccountNumber
                    FROM Contact
                    WHERE Id = :createdId
                    LIMIT 1
                ];

                res.done = true;
                res.contactId = created.Id;

                res.message =
                    '<p>Created contact.</p>' +
                    '<ul>' +
                    formatContactBlock(created, baseUrl) +
                    '</ul>';

                outList.add(res);

            } catch (DmlException dmle) {
                res.done = true;
                res.message = '<p>Contact creation failed: ' + escapeHtml(dmle.getDmlMessage(0)) + '</p>';
                outList.add(res);
            } catch (Exception e) {
                res.done = true;
                res.message = '<p>Contact creation failed: ' + escapeHtml(e.getMessage()) + '</p>';
                outList.add(res);
            }
        }

        return outList;
    }

    // If lastName missing, attempt to derive from fullName or firstName containing spaces
    private static void deriveNames(Request req) {
        // 1) If fullName provided and lastName missing -> split
        if (isBlank(req.lastName) && !isBlank(req.fullName)) {
            splitFullNameIntoFirstLast(req, req.fullName);
        }

        // 2) If lastName missing and firstName contains spaces (agent sometimes dumps full name into firstName)
        if (isBlank(req.lastName) && !isBlank(req.firstName) && req.firstName.trim().contains(' ')) {
            splitFullNameIntoFirstLast(req, req.firstName);
        }

        // 3) If firstName missing but lastName exists and fullName exists, still split to populate firstName
        if (isBlank(req.firstName) && !isBlank(req.lastName) && !isBlank(req.fullName)) {
            splitFullNameIntoFirstLast(req, req.fullName);
        }
    }

    private static void splitFullNameIntoFirstLast(Request req, String full) {
        if (isBlank(full)) return;

        String cleaned = full.trim().replaceAll('\\s+', ' ');
        List<String> parts = cleaned.split(' ');
        if (parts == null || parts.size() == 0) return;

        if (parts.size() == 1) {
            // Single token: treat as last name (Salesforce requires LastName)
            if (isBlank(req.lastName)) req.lastName = parts[0];
            return;
        }

        // Last token is last name; rest is first name
        String ln = parts[parts.size() - 1];
        String fn = cleaned.substring(0, cleaned.lastIndexOf(' '));

        if (isBlank(req.lastName)) req.lastName = ln;
        if (isBlank(req.firstName)) req.firstName = fn;
    }

    // ---------- Rendering (one field per line) ----------

    private static String formatContactBlock(Contact c, String baseUrl) {
        String html = '<li>';

        html += '<a href="' + baseUrl + '/lightning/r/Contact/' + c.Id + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                c.Id + '</code></a><br/>';

        html += '<b>Name:</b> ' + escapeHtml(c.Name) + '<br/>';

        if (!isBlank(c.Email)) html += '<b>Email:</b> ' + escapeHtml(c.Email) + '<br/>';
        if (!isBlank(c.Phone)) html += '<b>Phone:</b> ' + escapeHtml(c.Phone) + '<br/>';
        if (!isBlank(c.Title)) html += '<b>Title:</b> ' + escapeHtml(c.Title) + '<br/>';

        if (c.AccountId != null) {
            html += '<b>Account Id:</b> ' + escapeHtml(String.valueOf(c.AccountId)) + '<br/>';
            if (c.Account != null && !isBlank(c.Account.Name)) html += '<b>Account Name:</b> ' + escapeHtml(c.Account.Name) + '<br/>';
            if (c.Account != null && !isBlank(c.Account.AccountNumber)) html += '<b>Account Number:</b> ' + escapeHtml(c.Account.AccountNumber) + '<br/>';
        }

        html += '</li>';
        return html;
    }

    // ---------- Account resolution ----------

    private static Account resolveAccount(Request req, Response res, Integer maxToShow) {
        if (isBlank(req.accountId) && isBlank(req.accountNumber) && isBlank(req.accountName)) return null;

        if (!isBlank(req.accountId)) {
            List<Account> a = [
                SELECT Id, Name, AccountNumber
                FROM Account
                WHERE Id = :req.accountId
                LIMIT 1
            ];
            if (a.isEmpty()) {
                res.message = '<p>No account found for accountId <code>' + escapeHtml(req.accountId) + '</code>.</p>';
                return null;
            }
            return a[0];
        }

        if (!isBlank(req.accountNumber)) {
            List<Account> a = [
                SELECT Id, Name, AccountNumber
                FROM Account
                WHERE AccountNumber = :req.accountNumber
                LIMIT 2
            ];
            if (a.isEmpty()) {
                res.message = '<p>No account found with Account Number <b>' + escapeHtml(req.accountNumber) + '</b>.</p>';
                return null;
            }
            if (a.size() > 1) {
                res.message = '<p>Multiple accounts have that Account Number. Reply with the Account Id.</p>';
                return null;
            }
            return a[0];
        }

        String term = '%' + req.accountName.trim() + '%';
        List<Account> m = [
            SELECT Id, Name, AccountNumber
            FROM Account
            WHERE Name LIKE :term
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ];

        if (m.isEmpty()) {
            res.message = '<p>No account found with a name containing <b>' + escapeHtml(req.accountName) + '</b>. Please provide Account Id or Account Number.</p>';
            return null;
        }
        if (m.size() > 1) {
            res.message = '<p>Multiple accounts match that name. Reply with the Account Id from this list:</p>' +
                          formatAccountChoices(m, maxToShow);
            return null;
        }

        return m[0];
    }

    private static String formatAccountChoices(List<Account> accts, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, accts.size());
        String html = '<ul>';

        for (Integer i = 0; i < showCount; i++) {
            Account a = accts[i];
            html += '<li><code>' + a.Id + '</code><br/>';
            html += '<b>Name:</b> ' + escapeHtml(a.Name) + '<br/>';
            if (a.AccountNumber != null) html += '<b>Account Number:</b> ' + escapeHtml(a.AccountNumber) + '<br/>';
            html += '</li>';
        }

        html += '</ul>';

        if (accts.size() > showCount) {
            html += '<p>Showing ' + showCount + ' of ' + accts.size() + ' matches. Please provide the Account Id.</p>';
        }

        return html;
    }

    private static Boolean needsChoice(Response res) {
        return res != null && res.message != null && res.message.contains('Reply with the Account Id');
    }

    private static Boolean isBlank(String s) {
        return s == null || s.trim().length() == 0;
    }

    private static String escapeHtml(String s) {
        if (s == null) return '';
        String out = s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;');
        out = out.replace('"','&quot;').replace('\'','&#39;');
        return out;
    }
}