public with sharing class AF_UpdateActivityAction {

    public class Request {
        // --- Task identification ---
        @InvocableVariable(label='Task Id' description='18-character Task Id (preferred). Example: 00TXXXXXXXXXXXXXXX' required=false)
        public String taskId;

        @InvocableVariable(label='Task Subject' description='Subject search text (contains match). If multiple matches, the action returns a list of tasks to pick from.' required=false)
        public String taskSubject;

        // Optional narrowing (recommended if searching by subject)
        @InvocableVariable(label='Contact Id' description='18-character Contact Id to narrow task search by related contact (WhoId).' required=false)
        public String contactId;

        @InvocableVariable(label='Contact Email' description='Email to find the contact if Contact Id not provided. Used to narrow task search.' required=false)
        public String contactEmail;

        @InvocableVariable(label='Contact Name' description='Full name text (example: Sean Forbes). Used to narrow task search when no Id/email is provided.' required=false)
        public String contactName;

        @InvocableVariable(label='Account Id' description='18-character Account Id to narrow task search by related account (WhatId).' required=false)
        public String accountId;

        @InvocableVariable(label='Account Number' description='Exact AccountNumber to locate account for narrowing task search.' required=false)
        public String accountNumber;

        @InvocableVariable(label='Account Name' description='Partial account name allowed (contains match). Used to narrow task search.' required=false)
        public String accountName;

        @InvocableVariable(label='Work Item Id' description='18-character Case Id to narrow task search by related work item (WhatId).' required=false)
        public String workItemId;

        @InvocableVariable(label='Work Item Number' description='CaseNumber (exact). Used to narrow task search.' required=false)
        public String workItemNumber;

        @InvocableVariable(label='Work Item Subject' description='Work item subject text (contains). Used to narrow task search.' required=false)
        public String workItemSubject;

        // --- Convenience operation ---
        @InvocableVariable(label='Mark Complete' description='Optional. true to set Status=Completed.' required=false)
        public Boolean markComplete;

        // --- Fields to update (only applied if provided) ---
        @InvocableVariable(label='New Subject' description='New Task.Subject value.' required=false)
        public String newSubject;

        @InvocableVariable(label='New Due Date' description='New Task.ActivityDate (yyyy-mm-dd).' required=false)
        public Date newDueDate;

        @InvocableVariable(label='New Status' description='New Task.Status value. Example: Not Started, In Progress, Completed.' required=false)
        public String newStatus;

        @InvocableVariable(label='New Priority' description='New Task.Priority value. Example: Low, Normal, High.' required=false)
        public String newPriority;

        @InvocableVariable(label='New Type' description='New Task.Type value. Example: Call, Email, Follow Up, Other.' required=false)
        public String newType;

        @InvocableVariable(label='New Comments' description='New Task.Description. Optional. Replaces existing description.' required=false)
        public String newComments;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when the task is updated; false when the user must choose a task from a list.')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML result or disambiguation list. Show as-is.')
        public String message;

        @InvocableVariable(label='Task Id' description='Updated Task Id when resolved.')
        public String taskId;
    }

    @InvocableMethod(
        label='Update Activity'
        description='Updates a Task. Can mark complete, reschedule, or update subject/status/priority/type/comments. If multiple tasks match, returns a list of task IDs to pick from.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;

            // Need task identifier
            if (isBlank(req.taskId) && isBlank(req.taskSubject)) {
                res.message = '<p>Please provide the Task Id (preferred) or a taskSubject to search.</p>';
                outList.add(res);
                continue;
            }

            // Need at least one update
            Boolean hasUpdate =
                (req.markComplete == true) ||
                !isBlank(req.newSubject) ||
                (req.newDueDate != null) ||
                !isBlank(req.newStatus) ||
                !isBlank(req.newPriority) ||
                !isBlank(req.newType) ||
                !isBlank(req.newComments);

            if (!hasUpdate) {
                res.message = '<p>What would you like to update on the activity? Provide markComplete=true or one or more of: newSubject, newDueDate, newStatus, newPriority, newType, newComments.</p>';
                outList.add(res);
                continue;
            }

            Task t = resolveTask(req, res, 6);
            if (t == null) {
                outList.add(res);
                continue;
            }
            res.taskId = t.Id;

            // Apply updates (do not overwrite with blanks)
            if (req.markComplete == true) t.Status = 'Completed';
            if (!isBlank(req.newSubject)) t.Subject = req.newSubject.trim();
            if (req.newDueDate != null) t.ActivityDate = req.newDueDate;
            if (!isBlank(req.newStatus)) t.Status = req.newStatus.trim();
            if (!isBlank(req.newPriority)) t.Priority = req.newPriority.trim();
            if (!isBlank(req.newType)) t.Type = req.newType.trim();
            if (!isBlank(req.newComments)) t.Description = req.newComments.trim();

            try {
                SObjectAccessDecision upd = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ t });
                List<SObject> safe = upd.getRecords();
                if (safe.isEmpty()) {
                    res.done = true;
                    res.message = '<p>Activity update failed due to access restrictions. Please confirm you have permission to edit Tasks.</p>';
                    outList.add(res);
                    continue;
                }
                update safe;

                Task t2 = [
                    SELECT Id, Subject, Status, Priority, Type, ActivityDate, WhoId, WhatId
                    FROM Task
                    WHERE Id = :t.Id
                    LIMIT 1
                ];

                res.done = true;
                res.message =
                    '<p>Updated activity.</p>' +
                    '<ul>' +
                    '<li>Task: <a href="' + baseUrl + '/lightning/r/Task/' + t2.Id + '/view" target="_blank" rel="noopener noreferrer"><code>' + t2.Id + '</code></a></li>' +
                    '<li>Subject: ' + escapeHtml(t2.Subject) + '</li>' +
                    (t2.ActivityDate != null ? '<li>Due Date: ' + String.valueOf(t2.ActivityDate) + '</li>' : '') +
                    (!isBlank(t2.Status) ? '<li>Status: ' + escapeHtml(t2.Status) + '</li>' : '') +
                    (!isBlank(t2.Priority) ? '<li>Priority: ' + escapeHtml(t2.Priority) + '</li>' : '') +
                    (!isBlank(t2.Type) ? '<li>Type: ' + escapeHtml(t2.Type) + '</li>' : '') +
                    '</ul>';

                outList.add(res);

            } catch (DmlException dmle) {
                res.done = true;
                res.message = '<p>Activity update failed: ' + escapeHtml(dmle.getDmlMessage(0)) + '</p>';
                outList.add(res);
            } catch (Exception e) {
                res.done = true;
                res.message = '<p>Activity update failed: ' + escapeHtml(e.getMessage()) + '</p>';
                outList.add(res);
            }
        }

        return outList;
    }

    // ---------------- Task resolution ----------------

    private static Task resolveTask(Request req, Response res, Integer maxToShow) {
        // 1) By Task Id
        if (!isBlank(req.taskId)) {
            List<Task> tasks = [
                SELECT Id, Subject, Status, Priority, Type, ActivityDate, WhoId, WhatId, LastModifiedDate
                FROM Task
                WHERE Id = :req.taskId
                LIMIT 1
            ];
            if (tasks.isEmpty()) {
                res.message = '<p>No activity found for Task Id <code>' + escapeHtml(req.taskId) + '</code>.</p>';
                return null;
            }
            return tasks[0];
        }

        // 2) By Subject (contains), optionally narrowed
        Id whoId = resolveContactIdForNarrowing(req, res, 5);
        if (whoId == null && res.message != null && res.message.contains('Please reply with')) return null;

        Id whatId = resolveWhatIdForNarrowing(req, res, 5);
        if (whatId == null && res.message != null && res.message.contains('Please reply with')) return null;

        String term = '%' + req.taskSubject.trim() + '%';

        String soql =
            'SELECT Id, Subject, Status, Priority, Type, ActivityDate, WhoId, WhatId, LastModifiedDate ' +
            'FROM Task ' +
            'WHERE Subject LIKE :term ';

        if (whoId != null) soql += 'AND WhoId = :whoId ';
        if (whatId != null) soql += 'AND WhatId = :whatId ';

        soql += 'ORDER BY LastModifiedDate DESC LIMIT 10';

        List<Task> matches = Database.query(soql);

        if (matches.isEmpty()) {
            res.message = '<p>No activities found matching that subject. Please provide the Task Id.</p>';
            return null;
        }

        if (matches.size() > 1) {
            res.message =
                '<p>Multiple activities match that subject. Reply with the Task Id from this list:</p>' +
                formatTaskChoices(matches, maxToShow);
            return null;
        }

        return matches[0];
    }

    // Narrowing helpers
    private static Id resolveContactIdForNarrowing(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.contactId)) return (Id)req.contactId.trim();

        if (!isBlank(req.contactEmail)) {
            List<Contact> c = [SELECT Id, Name, Email FROM Contact WHERE Email = :req.contactEmail LIMIT 10];
            if (c.isEmpty()) return null;
            if (c.size() > 1) {
                res.message = '<p>Multiple contacts match that email. Reply with the Contact Id from this list:</p>' + formatContactChoices(c, maxToShow);
                return null;
            }
            return c[0].Id;
        }

        if (!isBlank(req.contactName)) {
            String term = '%' + req.contactName.trim() + '%';
            List<Contact> c = [SELECT Id, Name, Email FROM Contact WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (c.isEmpty()) return null;
            if (c.size() > 1) {
                res.message = '<p>Multiple contacts match that name. Reply with the Contact Id from this list:</p>' + formatContactChoices(c, maxToShow);
                return null;
            }
            return c[0].Id;
        }

        return null;
    }

    private static Id resolveWhatIdForNarrowing(Request req, Response res, Integer maxToShow) {
        // Work Item wins if provided
        if (!isBlank(req.workItemId) || !isBlank(req.workItemNumber) || !isBlank(req.workItemSubject)) {
            Case wi = resolveWorkItem(req, res, maxToShow);
            return (wi == null ? null : wi.Id);
        }

        // Otherwise Account
        if (!isBlank(req.accountId)) return (Id)req.accountId.trim();

        if (!isBlank(req.accountNumber)) {
            List<Account> a = [SELECT Id, Name, AccountNumber FROM Account WHERE AccountNumber = :req.accountNumber LIMIT 2];
            if (a.isEmpty()) return null;
            if (a.size() > 1) {
                res.message = '<p>Multiple accounts have that Account Number. Reply with the Account Id.</p>';
                return null;
            }
            return a[0].Id;
        }

        if (!isBlank(req.accountName)) {
            String term = '%' + req.accountName.trim() + '%';
            List<Account> a = [SELECT Id, Name, AccountNumber FROM Account WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 10];
            if (a.isEmpty()) return null;
            if (a.size() > 1) {
                res.message = '<p>Multiple accounts match that name. Reply with the Account Id from this list:</p>' + formatAccountChoices(a, maxToShow);
                return null;
            }
            return a[0].Id;
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
            if (m.isEmpty()) return null;
            if (m.size() > 1) {
                res.message = '<p>Multiple work items match that subject. Reply with the Work Item Id from this list:</p>' + formatWorkItemChoices(m, maxToShow);
                return null;
            }
            return m[0];
        }

        return null;
    }

    // Formatting
    private static String formatTaskChoices(List<Task> tasks, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, tasks.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Task t = tasks[i];
            String due = (t.ActivityDate != null ? String.valueOf(t.ActivityDate) : '');
            html += '<li><code>' + t.Id + '</code> — ' + escapeHtml(t.Subject) +
                    (!isBlank(t.Status) ? ' — ' + escapeHtml(t.Status) : '') +
                    (due != '' ? ' — due ' + escapeHtml(due) : '') +
                    '</li>';
        }
        html += '</ul>';
        if (tasks.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + tasks.size() + ' matches. Please provide the Task Id.</p>';
        return html;
    }

    private static String formatContactChoices(List<Contact> contacts, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, contacts.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Contact c = contacts[i];
            String email = (c.Email != null ? escapeHtml(c.Email) : '');
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
            String num = (a.AccountNumber != null ? escapeHtml(a.AccountNumber) : '');
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