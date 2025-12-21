public with sharing class AF_ListActivitiesAction {

    public class Request {
        @InvocableVariable(label='Assigned To Me' description='Optional. true to list only tasks owned by the current user.' required=false)
        public Boolean assignedToMe;

        @InvocableVariable(label='Include Completed' description='Optional. true to include completed tasks; false/blank lists only open tasks.' required=false)
        public Boolean includeCompleted;

        @InvocableVariable(label='Max Results' description='Optional. Maximum number of tasks to return (1-25). Default 10.' required=false)
        public Integer maxResults;

        // Narrow by Contact (Who)
        @InvocableVariable(label='Contact Id' description='18-character Contact Id (preferred) to list tasks related to a contact.' required=false)
        public String contactId;

        @InvocableVariable(label='Contact Email' description='Email to find the contact when Contact Id is not provided.' required=false)
        public String contactEmail;

        @InvocableVariable(label='Contact Name' description='Full name text (example: Sean Forbes). Used when no Id/email is provided.' required=false)
        public String contactName;

        // Narrow by Account (What)
        @InvocableVariable(label='Account Id' description='18-character Account Id to list tasks related to an account.' required=false)
        public String accountId;

        @InvocableVariable(label='Account Number' description='Exact AccountNumber to locate the account.' required=false)
        public String accountNumber;

        @InvocableVariable(label='Account Name' description='Partial account name allowed (contains match). Example: Burlington' required=false)
        public String accountName;

        // Narrow by Work Item / Case (What)
        @InvocableVariable(label='Work Item Id' description='18-character Case Id to list tasks related to a work item.' required=false)
        public String workItemId;

        @InvocableVariable(label='Work Item Number' description='CaseNumber. Can be full (00001058) or short numeric (1058); short values are left-padded with zeros.' required=false)
        public String workItemNumber;

        @InvocableVariable(label='Work Item Subject' description='Subject search text (contains match). If multiple matches, returns a list of work items to pick from.' required=false)
        public String workItemSubject;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when results are returned; false when more info is needed (ambiguous matches).')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML list of tasks (with Task IDs).')
        public String message;

        @InvocableVariable(label='Task Ids' description='List of Task Ids returned in the message (up to Max Results).')
        public List<String> taskIds;
    }

    @InvocableMethod(
        label='List Activities'
        description='Lists Tasks (activities) optionally filtered by Contact/Account/Work Item and assignment. Returns Task IDs for easy selection.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;
            res.taskIds = new List<String>();

            Integer limitSize = (req.maxResults == null ? 10 : req.maxResults);
            if (limitSize < 1) limitSize = 1;
            if (limitSize > 25) limitSize = 25;

            if (!isBlank(req.workItemNumber)) {
                req.workItemNumber = normalizeCaseNumber(req.workItemNumber);
            }

            Contact who = resolveContact(req, res, 5);
            if (who == null && needsChoice(res)) { outList.add(res); continue; }

            Account acc = resolveAccount(req, res, 5);
            if (acc == null && needsChoice(res)) { outList.add(res); continue; }

            Case wi = resolveWorkItem(req, res, 5);
            if (wi == null && needsChoice(res)) { outList.add(res); continue; }

            Id whoId = (who != null ? who.Id : null);
            Id whatId = (wi != null ? wi.Id : (acc != null ? acc.Id : null));
            Id ownerId = (req.assignedToMe == true ? UserInfo.getUserId() : null);
            Boolean includeCompleted = (req.includeCompleted == true);

            String soql =
                'SELECT Id, Subject, Status, Priority, Type, ActivityDate, Owner.Name, WhoId, WhatId, LastModifiedDate ' +
                'FROM Task ' +
                'WHERE IsDeleted = false ';

            if (ownerId != null) soql += 'AND OwnerId = :ownerId ';
            if (whoId != null) soql += 'AND WhoId = :whoId ';
            if (whatId != null) soql += 'AND WhatId = :whatId ';
            if (!includeCompleted) soql += 'AND IsClosed = false ';

            soql += 'ORDER BY LastModifiedDate DESC LIMIT :limitSize';

            List<Task> tasks = Database.query(soql);

            if (tasks.isEmpty()) {
                res.done = true;
                res.message = '<p>No activities found for that filter.</p>';
                outList.add(res);
                continue;
            }

            String html = '<p>Here are the most recent ' + (includeCompleted ? '' : 'open ') + 'activities:</p><ul>';

            for (Task t : tasks) {
                res.taskIds.add((String)t.Id);
                html += formatTaskBlock(t, baseUrl);
            }

            html += '</ul><p>Reply with the Task Id if you want to update one.</p>';

            res.done = true;
            res.message = html;
            outList.add(res);
        }

        return outList;
    }

    private static String formatTaskBlock(Task t, String baseUrl) {
        String html = '<li>';

        html += '<a href="' + baseUrl + '/lightning/r/Task/' + t.Id + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                t.Id + '</code></a><br/>';

        html += '<b>Subject:</b> ' + escapeHtml(t.Subject) + '<br/>';

        if (!isBlank(t.Status)) html += '<b>Status:</b> ' + escapeHtml(t.Status) + '<br/>';
        if (t.ActivityDate != null) html += '<b>Due Date:</b> ' + escapeHtml(String.valueOf(t.ActivityDate)) + '<br/>';
        if (!isBlank(t.Priority)) html += '<b>Priority:</b> ' + escapeHtml(t.Priority) + '<br/>';
        if (!isBlank(t.Type)) html += '<b>Type:</b> ' + escapeHtml(t.Type) + '<br/>';
        if (t.Owner != null && !isBlank(t.Owner.Name)) html += '<b>Owner:</b> ' + escapeHtml(t.Owner.Name) + '<br/>';

        html += '</li>';
        return html;
    }

    // --------- Resolution helpers ---------

    private static Contact resolveContact(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.contactId)) {
            List<Contact> c = [SELECT Id, Name, Email FROM Contact WHERE Id = :req.contactId LIMIT 1];
            if (c.isEmpty()) {
                res.message = '<p>No contact found for contactId <code>' + escapeHtml(req.contactId) + '</code>.</p>';
                return null;
            }
            return c[0];
        }

        if (!isBlank(req.contactEmail)) {
            List<Contact> m = [SELECT Id, Name, Email FROM Contact WHERE Email = :req.contactEmail LIMIT 10];
            if (m.isEmpty()) return null;
            if (m.size() > 1) {
                res.message = '<p>Multiple contacts match that email. Reply with the Contact Id from this list:</p>' + formatContacts(m, maxToShow);
                return null;
            }
            return m[0];
        }

        if (!isBlank(req.contactName)) {
            String term = '%' + req.contactName.trim() + '%';
            List<Contact> m = [SELECT Id, Name, Email FROM Contact WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (m.isEmpty()) return null;
            if (m.size() > 1) {
                res.message = '<p>Multiple contacts match that name. Reply with the Contact Id from this list:</p>' + formatContacts(m, maxToShow);
                return null;
            }
            return m[0];
        }

        return null;
    }

    private static Account resolveAccount(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.accountId)) {
            List<Account> a = [SELECT Id, Name, AccountNumber FROM Account WHERE Id = :req.accountId LIMIT 1];
            if (a.isEmpty()) {
                res.message = '<p>No account found for accountId <code>' + escapeHtml(req.accountId) + '</code>.</p>';
                return null;
            }
            return a[0];
        }

        if (!isBlank(req.accountNumber)) {
            List<Account> a = [SELECT Id, Name, AccountNumber FROM Account WHERE AccountNumber = :req.accountNumber LIMIT 2];
            if (a.isEmpty()) return null;
            if (a.size() > 1) {
                res.message = '<p>Multiple accounts have that Account Number. Reply with the Account Id.</p>';
                return null;
            }
            return a[0];
        }

        if (!isBlank(req.accountName)) {
            String term = '%' + req.accountName.trim() + '%';
            List<Account> m = [SELECT Id, Name, AccountNumber FROM Account WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (m.size() > 1) {
                res.message = '<p>Multiple accounts match that name. Reply with the Account Id from this list:</p>' + formatAccounts(m, maxToShow);
                return null;
            }
            if (m.isEmpty()) return null;
            return m[0];
        }

        return null;
    }

    private static Case resolveWorkItem(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.workItemId)) {
            List<Case> c = [SELECT Id, CaseNumber, Subject FROM Case WHERE Id = :req.workItemId LIMIT 1];
            if (c.isEmpty()) {
                res.message = '<p>No work item found for Work Item Id <code>' + escapeHtml(req.workItemId) + '</code>.</p>';
                return null;
            }
            return c[0];
        }

        if (!isBlank(req.workItemNumber)) {
            List<Case> c = [SELECT Id, CaseNumber, Subject FROM Case WHERE CaseNumber = :req.workItemNumber LIMIT 2];
            if (c.isEmpty()) return null;
            if (c.size() > 1) {
                res.message = '<p>Multiple work items share that number (unexpected). Reply with the Work Item Id.</p>';
                return null;
            }
            return c[0];
        }

        if (!isBlank(req.workItemSubject)) {
            String term = '%' + req.workItemSubject.trim() + '%';
            List<Case> m = [SELECT Id, CaseNumber, Subject FROM Case WHERE Subject LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (m.size() > 1) {
                res.message = '<p>Multiple work items match that subject. Reply with the Work Item Id from this list:</p>' + formatWorkItems(m, maxToShow);
                return null;
            }
            if (m.isEmpty()) return null;
            return m[0];
        }

        return null;
    }

    private static Boolean needsChoice(Response res) {
        return res != null && res.message != null && res.message.contains('Reply with');
    }

    // --------- CaseNumber normalization ---------

    private static String normalizeCaseNumber(String raw) {
        if (isBlank(raw)) return raw;
        String s = raw.trim();
        String digitsOnly = s.replaceAll('[^0-9]', '');
        if (digitsOnly.length() == 0) return s;

        Integer targetLen = getOrgCaseNumberLength();
        if (targetLen == null || targetLen <= 0) return digitsOnly;
        if (digitsOnly.length() >= targetLen) return digitsOnly;

        Integer zeros = targetLen - digitsOnly.length();
        String pad = '';
        for (Integer i = 0; i < zeros; i++) pad += '0';
        return pad + digitsOnly;
    }

    private static Integer getOrgCaseNumberLength() {
        try {
            Case c = [SELECT CaseNumber FROM Case WHERE CaseNumber != null LIMIT 1];
            if (c != null && c.CaseNumber != null) return c.CaseNumber.length();
        } catch (Exception e) {}
        return 8;
    }

    // --------- Formatting lists (for disambiguation) ---------

    private static String formatContacts(List<Contact> contacts, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, contacts.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Contact c = contacts[i];
            html += '<li><code>' + c.Id + '</code><br/><b>Name:</b> ' + escapeHtml(c.Name) +
                    (c.Email != null ? '<br/><b>Email:</b> ' + escapeHtml(c.Email) : '') +
                    '</li>';
        }
        html += '</ul>';
        if (contacts.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + contacts.size() + ' matches. Please provide the Contact Id.</p>';
        return html;
    }

    private static String formatAccounts(List<Account> accts, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, accts.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Account a = accts[i];
            html += '<li><code>' + a.Id + '</code><br/><b>Name:</b> ' + escapeHtml(a.Name) +
                    (a.AccountNumber != null ? '<br/><b>Account Number:</b> ' + escapeHtml(a.AccountNumber) : '') +
                    '</li>';
        }
        html += '</ul>';
        if (accts.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + accts.size() + ' matches. Please provide the Account Id.</p>';
        return html;
    }

    private static String formatWorkItems(List<Case> cases, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, cases.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Case c = cases[i];
            html += '<li><code>' + c.Id + '</code><br/><b>Case Number:</b> ' + escapeHtml(c.CaseNumber) +
                    '<br/><b>Subject:</b> ' + escapeHtml(c.Subject) +
                    '</li>';
        }
        html += '</ul>';
        if (cases.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + cases.size() + ' matches. Please provide the Work Item Id.</p>';
        return html;
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