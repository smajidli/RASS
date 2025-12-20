public with sharing class AF_UpdateContactAction {

    public class Request {
        // --- Contact identification ---
        @InvocableVariable(label='Contact Id' description='18-character Contact Id (preferred). Example: 003XXXXXXXXXXXXXXX' required=false)
        public String contactId;

        @InvocableVariable(label='Contact Email' description='Email to locate the contact if Contact Id not provided' required=false)
        public String contactEmail;

        @InvocableVariable(label='Contact Name' description='Full name from the user. Example: Sean Forbes' required=false)
        public String contactName;

        @InvocableVariable(label='Contact First Name' description='Optional disambiguation for name lookup' required=false)
        public String contactFirstName;

        @InvocableVariable(label='Contact Last Name' description='Last name for name lookup (used if no Id/email). If a full name is passed here, the class will parse it.' required=false)
        public String contactLastName;

        // Account identifier used only to disambiguate name-based lookup
        @InvocableVariable(label='Account Id (for lookup)' description='Account Id to help locate the contact when searching by name' required=false)
        public String accountId;

        @InvocableVariable(label='Account Number (for lookup)' description='AccountNumber to help locate the contact when searching by name' required=false)
        public String accountNumber;

        @InvocableVariable(label='Account Name (for lookup)' description='Exact Account Name to help locate the contact when searching by name' required=false)
        public String accountName;

        // --- Fields to update ---
        @InvocableVariable(label='New Email' description='New Contact.Email value' required=false)
        public String newEmail;

        @InvocableVariable(label='New Phone' description='New Contact.Phone value' required=false)
        public String newPhone;

        @InvocableVariable(label='New Title' description='New Contact.Title value' required=false)
        public String newTitle;

        @InvocableVariable(label='New Level' description='New Contact.Level__c value (Primary/Secondary/Tertiary)' required=false)
        public String newLevel;

        @InvocableVariable(label='New Languages' description='New Contact.Languages__c value (semicolon-separated for multi-select)' required=false)
        public String newLanguages;

        // Optional: move contact to a new account
        @InvocableVariable(label='New Account Id' description='Move the contact to this Account Id' required=false)
        public String newAccountId;

        @InvocableVariable(label='New Account Number' description='Move the contact to the account with this AccountNumber' required=false)
        public String newAccountNumber;

        @InvocableVariable(label='New Account Name' description='Move the contact to the account with this exact Name' required=false)
        public String newAccountName;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when update completed; false when more info is needed')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing result message (HTML allowed)')
        public String message;

        @InvocableVariable(label='Contact Id' description='Updated Contact Id (when resolved)')
        public String contactId;
    }

    private class NameParts {
        public String fullName;
        public String firstName;
        public String lastName;
    }

    @InvocableMethod(
        label='Update Contact'
        description='Updates one Contact (email/phone/title/level/languages and optionally moves to a new account).'
    )
    public static List<Response> updateContact(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;

            // Validate: need some way to identify contact
            Boolean hasIdentifier =
                !isBlank(req.contactId) ||
                !isBlank(req.contactEmail) ||
                !isBlank(req.contactName) ||
                !isBlank(req.contactLastName) ||
                !isBlank(req.contactFirstName);

            if (!hasIdentifier) {
                res.message = '<p>Please provide Contact Id (preferred), contactEmail, or contactName (or at least contactLastName).</p>';
                outList.add(res);
                continue;
            }

            // Validate: need at least one update value
            Boolean hasUpdate =
                !isBlank(req.newEmail) ||
                !isBlank(req.newPhone) ||
                !isBlank(req.newTitle) ||
                !isBlank(req.newLevel) ||
                !isBlank(req.newLanguages) ||
                !isBlank(req.newAccountId) ||
                !isBlank(req.newAccountNumber) ||
                !isBlank(req.newAccountName);

            if (!hasUpdate) {
                res.message = '<p>What would you like to update on the contact? Provide one or more of: newEmail, newPhone, newTitle, newLevel, newLanguages, or a new account.</p>';
                outList.add(res);
                continue;
            }

            // Resolve contact
            Contact c = resolveContact(req, res);
            if (c == null) {
                outList.add(res);
                continue;
            }

            // Resolve new account (optional)
            Id newAccId = null;
            if (!isBlank(req.newAccountId) || !isBlank(req.newAccountNumber) || !isBlank(req.newAccountName)) {
                Account newAcc = resolveAccount(req.newAccountId, req.newAccountNumber, req.newAccountName, res);
                if (newAcc == null) {
                    outList.add(res);
                    continue;
                }
                newAccId = newAcc.Id;
            }

            // Apply updates WITHOUT overwriting with blanks
            if (!isBlank(req.newEmail)) c.Email = req.newEmail.trim();
            if (!isBlank(req.newPhone)) c.Phone = req.newPhone.trim();
            if (!isBlank(req.newTitle)) c.Title = req.newTitle.trim();
            if (!isBlank(req.newLevel)) c.put('Level__c', req.newLevel.trim());
            if (!isBlank(req.newLanguages)) c.put('Languages__c', req.newLanguages.trim());
            if (newAccId != null) c.AccountId = newAccId;

            try {
                SObjectAccessDecision upd = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ c });
                List<SObject> safe = upd.getRecords();
                if (safe.isEmpty()) {
                    res.done = true;
                    res.contactId = c.Id;
                    res.message = '<p>Update failed due to access restrictions. Please confirm you have permission to edit this contact.</p>';
                    outList.add(res);
                    continue;
                }
                update safe;
            } catch (DmlException dmle) {
                res.done = true;
                res.contactId = c.Id;
                res.message = '<p>Update failed: ' + escapeHtml(dmle.getDmlMessage(0)) + '</p>';
                outList.add(res);
                continue;
            } catch (Exception e) {
                res.done = true;
                res.contactId = c.Id;
                res.message = '<p>Update failed: ' + escapeHtml(e.getMessage()) + '</p>';
                outList.add(res);
                continue;
            }

            res.done = true;
            res.contactId = c.Id;
            res.message =
                '<p>Updated contact.</p>' +
                '<p>Contact: <a href="' + baseUrl + '/lightning/r/Contact/' + c.Id + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                c.Id + '</code></a></p>';
            outList.add(res);
        }

        return outList;
    }

    // --- Helpers ---

    private static Contact resolveContact(Request req, Response res) {
        // 1) By Contact Id
        if (!isBlank(req.contactId)) {
            try {
                Contact c = [
                    SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                    FROM Contact
                    WHERE Id = :req.contactId
                    LIMIT 1
                ];
                res.contactId = c.Id;
                return c;
            } catch (Exception e) {
                res.message = '<p>No contact found for contactId <code>' + escapeHtml(req.contactId) + '</code>. Please provide a valid Contact Id.</p>';
                return null;
            }
        }

        // 2) By Email (must be unique)
        if (!isBlank(req.contactEmail)) {
            List<Contact> matches = [
                SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                FROM Contact
                WHERE Email = :req.contactEmail
                LIMIT 6
            ];
            if (matches.isEmpty()) {
                res.message = '<p>No contact found with email <b>' + escapeHtml(req.contactEmail) + '</b>. Please provide the Contact Id.</p>';
                return null;
            }
            if (matches.size() > 1) {
                res.done = false;
                res.message =
                    '<p>Multiple contacts have that email. Please reply with the Contact Id from this list:</p>' +
                    formatContactChoices(matches, 5);
                return null;
            }
            res.contactId = matches[0].Id;
            return matches[0];
        }

        // 3) By Name (supports contactName OR last/first, and also parses full name if it was passed into contactLastName)
        NameParts np = parseName(req);

        if (isBlank(np.fullName) && isBlank(np.lastName)) {
            res.message = '<p>Please provide contactName (preferred) or contactLastName (or contactId/contactEmail) so I can locate the correct contact.</p>';
            return null;
        }

        // Optional: resolve account for disambiguation
        Id disambigAccountId = null;
        if (!isBlank(req.accountId) || !isBlank(req.accountNumber) || !isBlank(req.accountName)) {
            Account a = resolveAccount(req.accountId, req.accountNumber, req.accountName, res);
            if (a == null) return null;
            disambigAccountId = a.Id;
        }

        // 3a) Try exact full name first
        if (!isBlank(np.fullName)) {
            List<Contact> fullMatches;
            if (disambigAccountId != null) {
                fullMatches = [
                    SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                    FROM Contact
                    WHERE Name = :np.fullName AND AccountId = :disambigAccountId
                    LIMIT 6
                ];
            } else {
                fullMatches = [
                    SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                    FROM Contact
                    WHERE Name = :np.fullName
                    LIMIT 6
                ];
            }

            if (fullMatches.size() == 1) {
                res.contactId = fullMatches[0].Id;
                return fullMatches[0];
            }
            if (fullMatches.size() > 1) {
                res.done = false;
                res.message =
                    '<p>Multiple contacts match that name. Please reply with the Contact Id from this list (or provide an account identifier to narrow it):</p>' +
                    formatContactChoices(fullMatches, 5);
                return null;
            }
        }

        // 3b) Try First + Last (if available)
        List<Contact> nameMatches;
        String ln = np.lastName;
        String fn = np.firstName;

        if (!isBlank(fn) && !isBlank(ln) && disambigAccountId != null) {
            nameMatches = [
                SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                FROM Contact
                WHERE FirstName = :fn AND LastName = :ln AND AccountId = :disambigAccountId
                LIMIT 6
            ];
        } else if (!isBlank(fn) && !isBlank(ln)) {
            nameMatches = [
                SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                FROM Contact
                WHERE FirstName = :fn AND LastName = :ln
                LIMIT 6
            ];
        } else if (!isBlank(ln) && disambigAccountId != null) {
            // 3c) Last name only (covers “only one Forbes”)
            nameMatches = [
                SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                FROM Contact
                WHERE LastName = :ln AND AccountId = :disambigAccountId
                LIMIT 6
            ];
        } else if (!isBlank(ln)) {
            nameMatches = [
                SELECT Id, Name, Email, Phone, AccountId, Account.Name, Account.AccountNumber
                FROM Contact
                WHERE LastName = :ln
                LIMIT 6
            ];
        } else {
            nameMatches = new List<Contact>();
        }

        if (nameMatches.isEmpty()) {
            res.message = '<p>I couldn’t find a contact matching that info. Please provide the Contact Id (preferred) or an email.</p>';
            return null;
        }
        if (nameMatches.size() > 1) {
            res.done = false;
            res.message =
                '<p>Multiple contacts match that name. Please reply with the Contact Id from this list (or provide an account identifier to narrow it):</p>' +
                formatContactChoices(nameMatches, 5);
            return null;
        }

        res.contactId = nameMatches[0].Id;
        return nameMatches[0];
    }

    private static NameParts parseName(Request req) {
        NameParts np = new NameParts();

        String full = null;

        // Preferred: contactName
        if (!isBlank(req.contactName)) {
            full = req.contactName.trim();
        } else if (!isBlank(req.contactFirstName) && !isBlank(req.contactLastName)) {
            full = (req.contactFirstName.trim() + ' ' + req.contactLastName.trim()).trim();
        } else if (!isBlank(req.contactLastName)) {
            // In practice, the agent sometimes dumps the full name here.
            full = req.contactLastName.trim();
        }

        if (isBlank(full)) return np;

        // Handle "Last, First"
        if (full.contains(',')) {
            List<String> parts = full.split(',', 2);
            if (parts.size() == 2) {
                String ln = parts[0].trim();
                String fn = parts[1].trim();
                if (!isBlank(fn) && !isBlank(ln)) {
                    np.firstName = fn;
                    np.lastName = ln;
                    np.fullName = (fn + ' ' + ln).trim();
                    return np;
                }
            }
        }

        np.fullName = full;

        // Handle "First Last" (or just one token)
        if (full.contains(' ')) {
            String[] tokens = full.split('\\s+');
            if (tokens.size() >= 2) {
                np.firstName = tokens[0].trim();

                List<String> rest = new List<String>();
                for (Integer i = 1; i < tokens.size(); i++) {
                    if (!isBlank(tokens[i])) rest.add(tokens[i].trim());
                }
                np.lastName = String.join(rest, ' ').trim();
            }
        } else {
            // single token -> treat as last name
            np.lastName = full.trim();
        }

        return np;
    }

    private static Account resolveAccount(String accountId, String accountNumber, String accountName, Response res) {
        if (!isBlank(accountId)) {
            try {
                return [
                    SELECT Id, Name, AccountNumber
                    FROM Account
                    WHERE Id = :accountId
                    LIMIT 1
                ];
            } catch (Exception e) {
                res.message = '<p>No account found for accountId <code>' + escapeHtml(accountId) + '</code>. Please provide a valid Account Id.</p>';
                return null;
            }
        }

        if (!isBlank(accountNumber)) {
            List<Account> a = [
                SELECT Id, Name, AccountNumber
                FROM Account
                WHERE AccountNumber = :accountNumber
                LIMIT 2
            ];
            if (a.isEmpty()) {
                res.message = '<p>No account found with Account Number <b>' + escapeHtml(accountNumber) + '</b>.</p>';
                return null;
            }
            if (a.size() > 1) {
                res.message = '<p>Multiple accounts have that Account Number. Please provide Account Id.</p>';
                return null;
            }
            return a[0];
        }

        if (!isBlank(accountName)) {
            List<Account> a = [
                SELECT Id, Name, AccountNumber
                FROM Account
                WHERE Name = :accountName
                LIMIT 6
            ];
            if (a.isEmpty()) {
                res.message = '<p>No account found with exact name <b>' + escapeHtml(accountName) + '</b>.</p>';
                return null;
            }
            if (a.size() > 1) {
                res.message = '<p>Multiple accounts match that name. Please provide Account Number or Account Id.</p>';
                return null;
            }
            return a[0];
        }

        res.message = '<p>Please provide Account Id, Account Number, or exact Account Name.</p>';
        return null;
    }

    private static Boolean isBlank(String s) {
        return s == null || s.trim().length() == 0;
    }

    private static String formatContactChoices(List<Contact> contacts, Integer maxToShow) {
        if (contacts == null || contacts.isEmpty()) return '';

        Integer showCount = Math.min(maxToShow, contacts.size());
        String html = '<ul>';

        for (Integer i = 0; i < showCount; i++) {
            Contact c = contacts[i];

            String accName = (c.Account != null && c.Account.Name != null) ? escapeHtml(c.Account.Name) : 'No Account';
            String accNum = (c.Account != null && c.Account.AccountNumber != null) ? escapeHtml(c.Account.AccountNumber) : '';
            String accPart = (accNum != '') ? (accName + ' (' + accNum + ')') : accName;

            String emailPart = (c.Email != null) ? escapeHtml(c.Email) : '';
            String phonePart = (c.Phone != null) ? escapeHtml(c.Phone) : '';

            html += '<li><code>' + c.Id + '</code> — ' + escapeHtml(c.Name) +
                    ' — ' + accPart +
                    (emailPart != '' ? ' — ' + emailPart : '') +
                    (phonePart != '' ? ' — ' + phonePart : '') +
                    '</li>';
        }

        html += '</ul>';

        if (contacts.size() > showCount) {
            html += '<p>Showing ' + showCount + ' of ' + contacts.size() + ' matches. Please narrow by account identifier or provide the Contact Id.</p>';
        }

        return html;
    }

    private static String escapeHtml(String s) {
        if (s == null) return '';
        String out = s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;');
        out = out.replace('"','&quot;').replace('\'','&#39;');
        return out;
    }
}