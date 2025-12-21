public with sharing class AF_CreateActivityAction {

    public class Request {
        // --- Relate to Contact (Who) ---
        @InvocableVariable(label='Contact Id' description='18-character Contact Id (preferred) to relate the activity to a contact.' required=false)
        public String contactId;

        @InvocableVariable(label='Contact Email' description='Email to find the contact when Contact Id is not provided.' required=false)
        public String contactEmail;

        @InvocableVariable(label='Contact Name' description='Full name text (example: Sean Forbes). Used when no Id/email is provided.' required=false)
        public String contactName;

        // --- Relate to Account (What) ---
        @InvocableVariable(label='Account Id' description='18-character Account Id to relate the activity to an account.' required=false)
        public String accountId;

        @InvocableVariable(label='Account Number' description='Exact AccountNumber to locate the account.' required=false)
        public String accountNumber;

        @InvocableVariable(label='Account Name' description='Partial account name allowed (contains match). Example: Burlington' required=false)
        public String accountName;

        // --- Relate to Work Item (Case) (What) ---
        @InvocableVariable(label='Work Item Id' description='18-character Case Id to relate the activity to a work item.' required=false)
        public String workItemId;

        @InvocableVariable(label='Work Item Number' description='CaseNumber (exact). Example: 00012345' required=false)
        public String workItemNumber;

        @InvocableVariable(label='Work Item Subject' description='Subject text (contains match). If multiple matches, the action will return a list of work items to pick from.' required=false)
        public String workItemSubject;

        // --- Task fields ---
        @InvocableVariable(label='Subject' description='Task Subject (required). Example: Follow up with client about missing docs.' required=true)
        public String subject;

        @InvocableVariable(label='Due Date' description='Task ActivityDate (yyyy-mm-dd). Optional.' required=false)
        public Date dueDate;

        @InvocableVariable(label='Status' description='Task Status. Optional. Example: Not Started, In Progress, Completed.' required=false)
        public String status;

        @InvocableVariable(label='Priority' description='Task Priority. Optional. Example: Normal, High, Low.' required=false)
        public String priority;

        @InvocableVariable(label='Type' description='Task Type. Optional. Example: Call, Email, Follow Up, Other.' required=false)
        public String type;

        @InvocableVariable(label='Comments' description='Task Description (optional).' required=false)
        public String comments;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when the activity is created; false when more info is needed (for example, multiple matches).')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML result or disambiguation list.')
        public String message;

        @InvocableVariable(label='Task Id' description='Created Task Id when successful.')
        public String taskId;

        @InvocableVariable(label='Related Record Id' description='The record Id used for Task.WhatId/WhoId (primary).')
        public String relatedRecordId;
    }

    @InvocableMethod(
        label='Create Activity'
        description='Creates a Task related to a Contact, Account, or Work Item (Case). If multiple matches are found, returns a list of IDs to choose from.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;

            if (isBlank(req.subject)) {
                res.message = '<p>Please provide a subject for the activity.</p>';
                outList.add(res);
                continue;
            }

            // Resolve related records (optional, but at least one is recommended)
            Contact who = resolveContact(req, res, 5);
            if (who == null && res.message != null && res.message.contains('Please reply with')) {
                outList.add(res);
                continue;
            }

            Account acc = resolveAccount(req, res, 5);
            if (acc == null && res.message != null && res.message.contains('Please reply with')) {
                outList.add(res);
                continue;
            }

            Case wi = resolveWorkItem(req, res, 5);
            if (wi == null && res.message != null && res.message.contains('Please reply with')) {
                outList.add(res);
                continue;
            }

            // If no explicit Account/WorkItem, but we have a Contact with an Account, use it as WhatId.
            if (acc == null && wi == null && who != null && who.AccountId != null) {
                acc = new Account(Id = who.AccountId);
            }

            // Build Task
            Task t = new Task();
            t.Subject = req.subject.trim();

            // Defaults (only set if provided; otherwise let org defaults apply where possible)
            if (req.dueDate != null) t.ActivityDate = req.dueDate;
            if (!isBlank(req.status)) t.Status = req.status.trim();
            if (!isBlank(req.priority)) t.Priority = req.priority.trim();
            if (!isBlank(req.type)) t.Type = req.type.trim();
            if (!isBlank(req.comments)) t.Description = req.comments.trim();

            if (who != null) t.WhoId = who.Id;
            if (wi != null) {
                t.WhatId = wi.Id;
                res.relatedRecordId = wi.Id;
            } else if (acc != null) {
                t.WhatId = acc.Id;
                res.relatedRecordId = acc.Id;
            } else if (who != null) {
                res.relatedRecordId = who.Id;
            }

            // Strongly encourage at least one relationship, but allow un-related task if org permits it
            if (t.WhatId == null && t.WhoId == null) {
                res.message = '<p>Please provide a related record: a contact (Id/email/name), an account (Id/number/name), or a work item (Id/number/subject).</p>';
                outList.add(res);
                continue;
            }

            try {
                SObjectAccessDecision ins = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ t });
                List<SObject> safe = ins.getRecords();
                if (safe.isEmpty()) {
                    res.done = true;
                    res.message = '<p>Activity could not be created due to access restrictions. Please confirm you have permission to create Tasks.</p>';
                    outList.add(res);
                    continue;
                }

                insert safe;
                Id newId = ((Task)safe[0]).Id;
                res.taskId = (String)newId;
                res.done = true;

                res.message =
                    '<p>Activity created.</p>' +
                    '<ul>' +
                    '<li>Task: <a href="' + baseUrl + '/lightning/r/Task/' + newId + '/view" target="_blank" rel="noopener noreferrer"><code>' + newId + '</code></a></li>' +
                    (t.WhoId != null ? '<li>Contact: <a href="' + baseUrl + '/lightning/r/Contact/' + t.WhoId + '/view" target="_blank" rel="noopener noreferrer"><code>' + t.WhoId + '</code></a></li>' : '') +
                    (t.WhatId != null && String.valueOf(t.WhatId).startsWith('001') ? '<li>Account: <a href="' + baseUrl + '/lightning/r/Account/' + t.WhatId + '/view" target="_blank" rel="noopener noreferrer"><code>' + t.WhatId + '</code></a></li>' : '') +
                    (t.WhatId != null && String.valueOf(t.WhatId).startsWith('500') ? '<li>Work Item: <a href="' + baseUrl + '/lightning/r/Case/' + t.WhatId + '/view" target="_blank" rel="noopener noreferrer"><code>' + t.WhatId + '</code></a></li>' : '') +
                    '<li>Subject: ' + escapeHtml(t.Subject) + '</li>' +
                    (t.ActivityDate != null ? '<li>Due Date: ' + String.valueOf(t.ActivityDate) + '</li>' : '') +
                    (!isBlank(t.Status) ? '<li>Status: ' + escapeHtml(t.Status) + '</li>' : '') +
                    (!isBlank(t.Priority) ? '<li>Priority: ' + escapeHtml(t.Priority) + '</li>' : '') +
                    (!isBlank(t.Type) ? '<li>Type: ' + escapeHtml(t.Type) + '</li>' : '') +
                    '</ul>';

                outList.add(res);

            } catch (DmlException dmle) {
                res.done = true;
                res.message = '<p>Activity creation failed: ' + escapeHtml(dmle.getDmlMessage(0)) + '</p>';
                outList.add(res);
            } catch (Exception e) {
                res.done = true;
                res.message = '<p>Activity creation failed: ' + escapeHtml(e.getMessage()) + '</p>';
                outList.add(res);
            }
        }

        return outList;
    }

    // ---------------- Resolution helpers ----------------

    private static Contact resolveContact(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.contactId)) {
            List<Contact> c = [SELECT Id, Name, Email, AccountId FROM Contact WHERE Id = :req.contactId LIMIT 1];
            if (c.isEmpty()) {
                res.message = '<p>No contact found for contactId <code>' + escapeHtml(req.contactId) + '</code>.</p>';
                return null;
            }
            return c[0];
        }

        if (!isBlank(req.contactEmail)) {
            List<Contact> matches = [SELECT Id, Name, Email, AccountId FROM Contact WHERE Email = :req.contactEmail LIMIT 10];
            if (matches.isEmpty()) return null;
            if (matches.size() > 1) {
                res.message = '<p>Multiple contacts match that email. Reply with the Contact Id from this list:</p>' + formatContactChoices(matches, maxToShow);
                return null;
            }
            return matches[0];
        }

        if (!isBlank(req.contactName)) {
            String term = '%' + req.contactName.trim() + '%';
            List<Contact> matches = [SELECT Id, Name, Email, AccountId FROM Contact WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (matches.isEmpty()) return null;
            if (matches.size() > 1) {
                res.message = '<p>Multiple contacts match that name. Reply with the Contact Id from this list:</p>' + formatContactChoices(matches, maxToShow);
                return null;
            }
            return matches[0];
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
                res.message = '<p>Multiple accounts have that account number. Reply with the Account Id.</p>';
                return null;
            }
            return a[0];
        }

        if (!isBlank(req.accountName)) {
            String term = '%' + req.accountName.trim() + '%';
            List<Account> matches = [SELECT Id, Name, AccountNumber FROM Account WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (matches.isEmpty()) return null;
            if (matches.size() > 1) {
                res.message = '<p>Multiple accounts match that name. Reply with the Account Id from this list:</p>' + formatAccountChoices(matches, maxToShow);
                return null;
            }
            return matches[0];
        }

        return null;
    }

    private static Case resolveWorkItem(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.workItemId)) {
            List<Case> c = [SELECT Id, CaseNumber, Subject FROM Case WHERE Id = :req.workItemId LIMIT 1];
            if (c.isEmpty()) {
                res.message = '<p>No work item found for workItemId <code>' + escapeHtml(req.workItemId) + '</code>.</p>';
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
            List<Case> matches = [SELECT Id, CaseNumber, Subject FROM Case WHERE Subject LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (matches.isEmpty()) return null;
            if (matches.size() > 1) {
                res.message = '<p>Multiple work items match that subject. Reply with the Work Item Id from this list:</p>' + formatWorkItemChoices(matches, maxToShow);
                return null;
            }
            return matches[0];
        }

        return null;
    }

    // ---------------- Formatting ----------------

    private static String formatContactChoices(List<Contact> contacts, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, contacts.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Contact c = contacts[i];
            String email = (c.Email != null) ? escapeHtml(c.Email) : '';
            html += '<li><code>' + c.Id + '</code> — ' + escapeHtml(c.Name) + (email != '' ? ' — ' + email : '') + '</li>';
        }
        html += '</ul>';
        if (contacts.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + contacts.size() + ' matches. Please provide the Contact Id.</p>';
        return html;
    }

    private static String formatAccountChoices(List<Account> accts, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, accts.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Account a = accts[i];
            String num = (a.AccountNumber != null) ? escapeHtml(a.AccountNumber) : '';
            html += '<li><code>' + a.Id + '</code> — ' + escapeHtml(a.Name) + (num != '' ? ' — ' + num : '') + '</li>';
        }
        html += '</ul>';
        if (accts.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + accts.size() + ' matches. Please provide the Account Id.</p>';
        return html;
    }

    private static String formatWorkItemChoices(List<Case> cases, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, cases.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Case c = cases[i];
            html += '<li><code>' + c.Id + '</code> — <b>' + escapeHtml(c.CaseNumber) + '</b> — ' + escapeHtml(c.Subject) + '</li>';
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