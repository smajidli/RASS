public with sharing class AF_AddWorkItemNoteAction {

    public class Request {
        @InvocableVariable(label='Work Item Id' description='18-character Case Id (preferred). Example: 500XXXXXXXXXXXXXXX' required=false)
        public String workItemId;

        @InvocableVariable(label='Work Item Number' description='CaseNumber. Can be full (00001058) or short numeric (1058); short values are left-padded with zeros.' required=false)
        public String workItemNumber;

        @InvocableVariable(label='Work Item Subject' description='Subject search text (contains match). If multiple matches, the action returns a list of choices.' required=false)
        public String workItemSubject;

        @InvocableVariable(label='Note' description='The note text to add to the work item. Plain text.' required=true)
        public String note;

        @InvocableVariable(label='Public Comment' description='Optional. true to publish (external); false or blank for internal note.' required=false)
        public Boolean isPublic;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when the note is added; false when the user must choose a work item.')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML summary or disambiguation list. Show as-is.')
        public String message;

        @InvocableVariable(label='Work Item Id' description='Resolved Case Id.')
        public String workItemId;

        @InvocableVariable(label='Case Comment Id' description='Created CaseComment Id when Case Comments are used (may be blank if appended to Case.Comments).')
        public String caseCommentId;
    }

    @InvocableMethod(
        label='Add Work Item Note'
        description='Adds an internal note/comment to a Work Item (Case). Uses CaseComment if available; otherwise appends to Case.Comments.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;

            if (isBlank(req.note)) {
                res.message = '<p>Please provide the note text to add.</p>';
                outList.add(res);
                continue;
            }

            if (isBlank(req.workItemId) && isBlank(req.workItemNumber) && isBlank(req.workItemSubject)) {
                res.message = '<p>Please provide the Work Item Id (preferred) or Work Item Number (CaseNumber). If neither is available, provide a subject to search.</p>';
                outList.add(res);
                continue;
            }

            // ✅ Normalize short case numbers like "1058" -> "00001058"
            if (!isBlank(req.workItemNumber)) {
                req.workItemNumber = normalizeCaseNumber(req.workItemNumber);
            }

            Case wi = resolveWorkItem(req, res, 5);
            if (wi == null) {
                outList.add(res);
                continue;
            }

            res.workItemId = wi.Id;

            String header = '[' + DateTime.now().format('yyyy-MM-dd HH:mm') + ' - ' + UserInfo.getName() + '] ';
            String body = header + req.note.trim();

            Boolean wantPublic = (req.isPublic == true);
            Boolean caseCommentSupported = Schema.getGlobalDescribe().containsKey('CaseComment');

            try {
                if (caseCommentSupported) {
                    CaseComment cc = new CaseComment();
                    cc.ParentId = wi.Id;
                    cc.CommentBody = body;
                    cc.IsPublished = wantPublic;

                    SObjectAccessDecision ins = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ cc });
                    List<SObject> safe = ins.getRecords();

                    if (safe.isEmpty()) {
                        appendToCaseCommentsField(wi, body);
                        res.done = true;
                        res.message = buildSuccessMessage(baseUrl, wi, null, wantPublic, true);
                        outList.add(res);
                        continue;
                    }

                    insert safe;
                    Id newId = ((CaseComment)safe[0]).Id;
                    res.caseCommentId = (String)newId;

                    res.done = true;
                    res.message = buildSuccessMessage(baseUrl, wi, newId, wantPublic, false);
                    outList.add(res);
                } else {
                    appendToCaseCommentsField(wi, body);
                    res.done = true;
                    res.message = buildSuccessMessage(baseUrl, wi, null, wantPublic, true);
                    outList.add(res);
                }
            } catch (Exception e) {
                try {
                    appendToCaseCommentsField(wi, body);
                    res.done = true;
                    res.message = buildSuccessMessage(baseUrl, wi, null, wantPublic, true) +
                        '<p>Note: CaseComment was unavailable; appended to Case.Comments instead.</p>';
                    outList.add(res);
                } catch (Exception e2) {
                    res.done = true;
                    res.message = '<p>Failed to add note: ' + escapeHtml(e.getMessage()) + '</p>';
                    outList.add(res);
                }
            }
        }

        return outList;
    }

    // -------- CaseNumber normalization --------

    private static String normalizeCaseNumber(String raw) {
        if (isBlank(raw)) return raw;
        String s = raw.trim();

        // keep only digits if user typed "work item 1058" etc.
        // (but do not destroy non-numeric case numbers; only normalize when purely numeric)
        String digitsOnly = s.replaceAll('[^0-9]', '');
        if (digitsOnly.length() == 0) return s;

        // Only normalize if input is purely numeric after cleanup
        // If user provided something like "ABC-1058", we leave it alone (not your org’s format)
        if (digitsOnly.length() != s.length() && s.replaceAll('\\s+', '') != digitsOnly) {
            // s had non-digits; if digitsOnly exists but s isn't just those digits, don't change it
            // EXCEPT when the user clearly typed only digits with spaces (handled by trim)
            // So we just use digitsOnly when the trimmed string is digitsOnly.
            if (s != digitsOnly) return s;
        }

        Integer targetLen = getOrgCaseNumberLength();
        if (targetLen == null || targetLen <= 0) return digitsOnly;

        if (digitsOnly.length() >= targetLen) return digitsOnly;

        Integer zeros = targetLen - digitsOnly.length();
        String pad = '';
        for (Integer i = 0; i < zeros; i++) pad += '0';
        return pad + digitsOnly;
    }

    private static Integer getOrgCaseNumberLength() {
        // Try to read any existing CaseNumber and use its length.
        // This avoids hardcoding "8".
        try {
            Case c = [SELECT CaseNumber FROM Case WHERE CaseNumber != null LIMIT 1];
            if (c != null && c.CaseNumber != null) return c.CaseNumber.length();
        } catch (Exception e) { }
        // Fallback: common default
        return 8;
    }

    // -------- Work Item resolution --------

    private static Case resolveWorkItem(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.workItemId)) {
            List<Case> c = [
                SELECT Id, CaseNumber, Subject, Comments, Status, AccountId, Account.Name
                FROM Case
                WHERE Id = :req.workItemId
                LIMIT 1
            ];
            if (c.isEmpty()) {
                res.message = '<p>No work item found for Work Item Id <code>' + escapeHtml(req.workItemId) + '</code>.</p>';
                return null;
            }
            return c[0];
        }

        if (!isBlank(req.workItemNumber)) {
            List<Case> c = [
                SELECT Id, CaseNumber, Subject, Comments, Status, AccountId, Account.Name
                FROM Case
                WHERE CaseNumber = :req.workItemNumber
                LIMIT 2
            ];
            if (c.isEmpty()) {
                res.message = '<p>No work item found with Work Item Number <b>' + escapeHtml(req.workItemNumber) + '</b>.</p>';
                return null;
            }
            if (c.size() > 1) {
                res.message = '<p>Multiple work items share that number (unexpected). Please provide the Work Item Id.</p>';
                return null;
            }
            return c[0];
        }

        String term = '%' + req.workItemSubject.trim() + '%';
        List<Case> matches = [
            SELECT Id, CaseNumber, Subject, Comments, Status, AccountId, Account.Name
            FROM Case
            WHERE Subject LIKE :term
            ORDER BY LastModifiedDate DESC
            LIMIT 10
        ];

        if (matches.isEmpty()) {
            res.message = '<p>No work items found with a subject containing <b>' + escapeHtml(req.workItemSubject) + '</b>. Please provide Work Item Id or Work Item Number.</p>';
            return null;
        }

        if (matches.size() > 1) {
            res.message =
                '<p>Multiple work items match that subject. Reply with the Work Item Id from this list:</p>' +
                formatWorkItemChoices(matches, maxToShow);
            return null;
        }

        return matches[0];
    }

    private static void appendToCaseCommentsField(Case wi, String body) {
        Case c = [SELECT Id, Comments FROM Case WHERE Id = :wi.Id LIMIT 1];

        String existing = c.Comments;
        String combined = (existing == null || existing.trim().length() == 0)
            ? body
            : (existing + '\n\n' + body);

        Case upd = new Case(Id = c.Id, Comments = combined);

        SObjectAccessDecision updSafe = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ upd });
        List<SObject> safe = updSafe.getRecords();
        if (!safe.isEmpty()) update safe;
    }

    private static String buildSuccessMessage(String baseUrl, Case wi, Id caseCommentId, Boolean isPublic, Boolean usedCaseCommentsField) {
        String mode = isPublic ? 'Public comment' : 'Internal note';

        String html =
            '<p>' + mode + ' added to work item.</p>' +
            '<ul>' +
            '<li>Work Item: <a href="' + baseUrl + '/lightning/r/Case/' + wi.Id + '/view" target="_blank" rel="noopener noreferrer"><code>' +
            escapeHtml(wi.CaseNumber) + '</code></a> — ' + escapeHtml(wi.Subject) + '</li>';

        if (caseCommentId != null) html += '<li>Case Comment: <code>' + String.valueOf(caseCommentId) + '</code></li>';

        html += usedCaseCommentsField
            ? '<li>Saved to: <code>Case.Comments</code> (append)</li>'
            : '<li>Saved to: <code>CaseComment</code></li>';

        html += '</ul>';
        return html;
    }

    private static String formatWorkItemChoices(List<Case> cases, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, cases.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Case c = cases[i];
            String acc = (c.Account != null ? escapeHtml(c.Account.Name) : '');
            html += '<li><code>' + c.Id + '</code> — <b>' + escapeHtml(c.CaseNumber) + '</b> — ' +
                    escapeHtml(c.Subject) +
                    (acc != '' ? ' — ' + acc : '') +
                    ' — ' + escapeHtml(c.Status) +
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