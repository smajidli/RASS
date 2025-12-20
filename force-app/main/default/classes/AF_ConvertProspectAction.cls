public with sharing class AF_ConvertProspectAction {

    public class Request {
        @InvocableVariable(label='Lead Id' description='18-character Lead Id (preferred). Example: 00QXXXXXXXXXXXXXXX' required=false)
        public String leadId;

        @InvocableVariable(label='Lead Email' description='Email address to locate the Prospect (Lead) if Lead Id not provided' required=false)
        public String leadEmail;

        @InvocableVariable(label='Lead Name' description='Full name text (example: Thomas Smith). Used when no Id/email is provided' required=false)
        public String leadName;

        @InvocableVariable(label='Company (for lookup)' description='Optional company name to narrow name-based lead matches' required=false)
        public String company;

        // Existing account resolution (optional)
        @InvocableVariable(label='Existing Account Id' description='18-character Account Id. If provided, convert into this existing Account.' required=false)
        public String existingAccountId;

        @InvocableVariable(label='Existing Account Number' description='Optional. Convert into the Account with this AccountNumber (exact match).' required=false)
        public String existingAccountNumber;

        @InvocableVariable(label='Existing Account Name' description='Optional. Partial account name allowed (contains match). Example: Burlington' required=false)
        public String existingAccountName;

        @InvocableVariable(label='Create Opportunity' description='Optional. true only if the user explicitly wants an Opportunity created.' required=false)
        public Boolean createOpportunity;

        @InvocableVariable(label='Opportunity Name' description='Optional Opportunity Name (used only if Create Opportunity = true)' required=false)
        public String opportunityName;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when conversion completed; false when user must choose an Id')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML result or disambiguation list')
        public String message;

        @InvocableVariable(label='Lead Id' description='Resolved Lead Id (when resolved)')
        public String leadId;

        @InvocableVariable(label='Account Id' description='Converted Account Id (when converted)')
        public String accountId;

        @InvocableVariable(label='Contact Id' description='Converted Contact Id (when converted)')
        public String contactId;

        @InvocableVariable(label='Opportunity Id' description='Opportunity Id if created (when converted)')
        public String opportunityId;
    }

    private class NameParts {
        public String firstName;
        public String lastName;
    }

    @InvocableMethod(label='Convert Prospect' description='Convert a Prospect (Lead) into an Account/Contact (and optionally an Opportunity). If ambiguous, returns picklists with IDs.')
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String convertedStatusValue = resolveConvertedStatusValue();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;

            Boolean hasIdentifier = !isBlank(req.leadId) || !isBlank(req.leadEmail) || !isBlank(req.leadName);
            if (!hasIdentifier) {
                res.message = '<p>Please provide Lead Id (preferred), leadEmail, or leadName so I can convert the correct prospect.</p>';
                outList.add(res);
                continue;
            }

            // Resolve Lead
            Lead leadRec = resolveLead(req, res, 5);
            if (leadRec == null) {
                outList.add(res);
                continue;
            }
            res.leadId = leadRec.Id;

            // If already converted, show links (including PersonContactId fix)
            if (leadRec.IsConverted) {
                res.done = true;
                res.accountId = (String)leadRec.get('ConvertedAccountId');
                res.contactId = (String)leadRec.get('ConvertedContactId');
                res.opportunityId = (String)leadRec.get('ConvertedOpportunityId');

                // Fix contact id for person accounts if needed
                res.contactId = normalizeContactId(res.accountId, res.contactId);

                res.message =
                    '<p>This prospect is already converted.</p>' +
                    buildConvertedLinks(baseUrl, res.accountId, res.contactId, res.opportunityId);

                outList.add(res);
                continue;
            }

            if (isBlank(convertedStatusValue)) {
                res.done = true;
                res.message = '<p>Lead conversion failed: no converted Lead Status value is available in this org. Please check Setup → Lead Status and ensure at least one status is marked as Converted.</p>';
                outList.add(res);
                continue;
            }

            // Optional: resolve existing account (Id/Number/Name contains)
            Id targetAccountId = resolveExistingAccount(req, res, 5);
            if (res.done == false && res.message != null && (
                res.message.contains('Multiple accounts') ||
                res.message.contains('No account found')
            )) {
                outList.add(res);
                continue;
            }

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadRec.Id);
            lc.setConvertedStatus(convertedStatusValue);

            // Opportunity handling (default = do not create)
            Boolean createOpp = (req.createOpportunity == true);
            lc.setDoNotCreateOpportunity(!createOpp);
            if (createOpp && !isBlank(req.opportunityName)) lc.setOpportunityName(req.opportunityName.trim());

            if (targetAccountId != null) lc.setAccountId(targetAccountId);

            try {
                Database.LeadConvertResult lcr = Database.convertLead(lc);

                if (!lcr.isSuccess()) {
                    String errMsg = 'Lead conversion failed.';
                    if (lcr.getErrors() != null && lcr.getErrors().size() > 0) errMsg = lcr.getErrors()[0].getMessage();
                    res.done = true;
                    res.message = '<p>' + escapeHtml(errMsg) + '</p>';
                    outList.add(res);
                    continue;
                }

                res.done = true;
                res.accountId = lcr.getAccountId();
                res.contactId = lcr.getContactId();
                res.opportunityId = lcr.getOpportunityId();

                // Fix contact id for person accounts if needed
                res.contactId = normalizeContactId(res.accountId, res.contactId);

                res.message =
                    '<p>Converted prospect.</p>' +
                    buildConvertedLinks(baseUrl, res.accountId, res.contactId, res.opportunityId);

                outList.add(res);
            } catch (Exception e) {
                res.done = true;
                res.message = '<p>Lead conversion failed: ' + escapeHtml(e.getMessage()) + '</p>';
                outList.add(res);
            }
        }

        return outList;
    }

    // ---------------- Converted Status ----------------

    private static String resolveConvertedStatusValue() {
        List<LeadStatus> converted = [
            SELECT ApiName, MasterLabel, SortOrder, IsConverted
            FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY SortOrder ASC
            LIMIT 50
        ];
        if (converted.isEmpty()) return null;

        for (LeadStatus ls : converted) {
            if (!isBlank(ls.ApiName) && ls.ApiName == 'Converted') return ls.ApiName;
        }
        for (LeadStatus ls : converted) {
            if (ls.MasterLabel == 'Converted' && !isBlank(ls.ApiName)) return ls.ApiName;
        }
        LeadStatus first = converted[0];
        return !isBlank(first.ApiName) ? first.ApiName : first.MasterLabel;
    }

    // ---------------- Lead Resolution ----------------

    private static Lead resolveLead(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.leadId)) {
            List<Lead> leads = [
                SELECT Id, Name, Email, Company, Status, IsConverted,
                       ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId
                FROM Lead
                WHERE Id = :req.leadId
                LIMIT 1
            ];
            if (leads.isEmpty()) {
                res.message = '<p>No prospect found for leadId <code>' + escapeHtml(req.leadId) + '</code>.</p>';
                return null;
            }
            return leads[0];
        }

        if (!isBlank(req.leadEmail)) {
            List<Lead> matches = [
                SELECT Id, Name, Email, Company, Status, IsConverted
                FROM Lead
                WHERE Email = :req.leadEmail
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
            if (matches.isEmpty()) {
                res.message = '<p>No prospect found with email <b>' + escapeHtml(req.leadEmail) + '</b>. Please provide a Lead Id.</p>';
                return null;
            }
            if (matches.size() > 1) {
                res.message =
                    '<p>Multiple prospects match that email. Reply with the Lead Id from this list:</p>' +
                    formatLeadChoices(matches, maxToShow);
                return null;
            }
            return matches[0];
        }

        // Name-based lookup (requires last name, but we parse "First Last")
        NameParts np = parseName(req.leadName);
        if (isBlank(np.lastName)) np.lastName = (req.leadName != null) ? req.leadName.trim() : null;

        if (isBlank(np.lastName)) {
            res.message = '<p>Please provide a prospect name (for example: “First Last”) or a Lead Id/email.</p>';
            return null;
        }

        List<Lead> nameMatches;
        if (!isBlank(np.firstName) && !isBlank(req.company)) {
            nameMatches = [
                SELECT Id, Name, Email, Company, Status, IsConverted
                FROM Lead
                WHERE FirstName = :np.firstName AND LastName = :np.lastName AND Company = :req.company
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
        } else if (!isBlank(np.firstName)) {
            nameMatches = [
                SELECT Id, Name, Email, Company, Status, IsConverted
                FROM Lead
                WHERE FirstName = :np.firstName AND LastName = :np.lastName
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
        } else if (!isBlank(req.company)) {
            nameMatches = [
                SELECT Id, Name, Email, Company, Status, IsConverted
                FROM Lead
                WHERE LastName = :np.lastName AND Company = :req.company
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
        } else {
            nameMatches = [
                SELECT Id, Name, Email, Company, Status, IsConverted
                FROM Lead
                WHERE LastName = :np.lastName
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
        }

        if (nameMatches.isEmpty()) {
            res.message = '<p>No prospect found matching that name. Please provide a Lead Id or email.</p>';
            return null;
        }
        if (nameMatches.size() > 1) {
            res.message =
                '<p>Multiple prospects match that name. Reply with the Lead Id from this list:</p>' +
                formatLeadChoices(nameMatches, maxToShow);
            return null;
        }
        return nameMatches[0];
    }

    private static NameParts parseName(String nameText) {
        NameParts np = new NameParts();
        if (isBlank(nameText)) return np;

        String full = nameText.trim();
        if (full.contains(',')) {
            List<String> parts = full.split(',', 2);
            if (parts.size() == 2) {
                np.lastName = parts[0].trim();
                np.firstName = parts[1].trim();
                return np;
            }
        }

        if (full.contains(' ')) {
            String[] tokens = full.split('\\s+');
            if (tokens.size() >= 2) {
                np.firstName = tokens[0].trim();
                List<String> rest = new List<String>();
                for (Integer i = 1; i < tokens.size(); i++) if (!isBlank(tokens[i])) rest.add(tokens[i].trim());
                np.lastName = String.join(rest, ' ').trim();
            }
        } else {
            np.lastName = full;
        }
        return np;
    }

    // ---------------- Existing Account Resolution ----------------

    private static Id resolveExistingAccount(Request req, Response res, Integer maxToShow) {
        if (!isBlank(req.existingAccountId)) return (Id)req.existingAccountId.trim();

        if (!isBlank(req.existingAccountNumber)) {
            List<Account> a = [
                SELECT Id, Name, AccountNumber, PersonContactId, IsPersonAccount
                FROM Account
                WHERE AccountNumber = :req.existingAccountNumber
                LIMIT 2
            ];
            if (a.isEmpty()) {
                res.done = false;
                res.message = '<p>No account found with Account Number <b>' + escapeHtml(req.existingAccountNumber) + '</b>. Provide an Account Id or a different name.</p>';
                return null;
            }
            if (a.size() > 1) {
                res.done = false;
                res.message = '<p>Multiple accounts have that Account Number. Please provide the Account Id.</p>';
                return null;
            }
            return a[0].Id;
        }

        if (!isBlank(req.existingAccountName)) {
            String term = '%' + req.existingAccountName.trim() + '%';

            List<Account> matches = [
                SELECT Id, Name, AccountNumber, PersonContactId, IsPersonAccount
                FROM Account
                WHERE Name LIKE :term
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];

            if (matches.isEmpty()) {
                res.done = false;
                res.message = '<p>No accounts found containing <b>' + escapeHtml(req.existingAccountName) + '</b>. Please provide an Account Id.</p>';
                return null;
            }

            if (matches.size() > 1) {
                res.done = false;
                res.message = '<p>Multiple accounts match that name. Reply with the Account Id from this list:</p>' + formatAccountChoices(matches, maxToShow);
                return null;
            }

            return matches[0].Id;
        }

        return null;
    }

    // ---------------- Person Account Contact Fix ----------------

    private static String normalizeContactId(String accountId, String contactId) {
        // If contact id missing OR looks like an Account Id, attempt to use PersonContactId.
        if (isBlank(accountId)) return contactId;

        Boolean contactLooksLikeAccount = (!isBlank(contactId) && contactId.startsWith('001'));
        if (isBlank(contactId) || contactLooksLikeAccount) {
            try {
                Account a = [
                    SELECT Id, IsPersonAccount, PersonContactId
                    FROM Account
                    WHERE Id = :accountId
                    LIMIT 1
                ];
                if (a.IsPersonAccount && a.PersonContactId != null) return (String)a.PersonContactId;
            } catch (Exception e) {
                // ignore and return original
            }
        }
        return contactId;
    }

    // ---------------- Formatting ----------------

    private static String formatLeadChoices(List<Lead> leads, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, leads.size());
        String html = '<ul>';
        for (Integer i = 0; i < showCount; i++) {
            Lead l = leads[i];
            String emailPart = (l.Email != null) ? escapeHtml(l.Email) : '';
            String companyPart = (l.Company != null) ? escapeHtml(l.Company) : '';
            String statusPart = (l.Status != null) ? escapeHtml(l.Status) : '';
            html += '<li><code>' + l.Id + '</code> — ' + escapeHtml(l.Name) +
                (companyPart != '' ? ' — ' + companyPart : '') +
                (emailPart != '' ? ' — ' + emailPart : '') +
                (statusPart != '' ? ' — ' + statusPart : '') +
                (l.IsConverted ? ' — Converted' : '') +
                '</li>';
        }
        html += '</ul>';
        if (leads.size() > showCount) html += '<p>Showing ' + showCount + ' of ' + leads.size() + ' matches. Please provide the Lead Id.</p>';
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

    private static String buildConvertedLinks(String baseUrl, String accountId, String contactId, String oppId) {
        String html = '<ul>';
        if (!isBlank(accountId)) {
            html += '<li>Account: <a href="' + baseUrl + '/lightning/r/Account/' + accountId + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                accountId + '</code></a></li>';
        }
        if (!isBlank(contactId)) {
            html += '<li>Contact: <a href="' + baseUrl + '/lightning/r/Contact/' + contactId + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                contactId + '</code></a></li>';
        }
        if (!isBlank(oppId)) {
            html += '<li>Opportunity: <a href="' + baseUrl + '/lightning/r/Opportunity/' + oppId + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                oppId + '</code></a></li>';
        }
        html += '</ul>';
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