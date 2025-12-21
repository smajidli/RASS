public with sharing class AF_ListAccountsAction {

    public class Request {
        @InvocableVariable(label='Max Results' description='Optional. Maximum number of accounts to return (1-25). Default 10.' required=false)
        public Integer maxResults;

        @InvocableVariable(label='Assigned To Me' description='Optional. true to list only accounts owned by the current user.' required=false)
        public Boolean assignedToMe;

        @InvocableVariable(label='Owner Id' description='Optional. 18-character User Id (005...) to list accounts owned by a specific user.' required=false)
        public String ownerId;

        @InvocableVariable(label='Owner Name' description='Optional. Owner name text (contains). Example: "Steve Williams". Used if ownerId not provided.' required=false)
        public String ownerName;

        @InvocableVariable(label='Account Id' description='Optional. 18-character Account Id. If provided, returns that single account.' required=false)
        public String accountId;

        @InvocableVariable(label='Account Number' description='Optional. Exact AccountNumber match.' required=false)
        public String accountNumber;

        @InvocableVariable(label='Account Name' description='Optional. Account name contains search. Example: "Edge" or "Burlington".' required=false)
        public String accountName;

        @InvocableVariable(label='Billing City' description='Optional. BillingCity contains search.' required=false)
        public String billingCity;

        @InvocableVariable(label='Industry' description='Optional. Account.Industry exact match (picklist value).' required=false)
        public String industry;
    }

    public class Response {
        @InvocableVariable(label='Done' description='true when results are returned; false when more info is needed (ambiguous owner).')
        public Boolean done;

        @InvocableVariable(label='Message' description='User-facing HTML list of accounts (with Account IDs).')
        public String message;

        @InvocableVariable(label='Account Ids' description='List of Account Ids returned in the message (up to Max Results).')
        public List<String> accountIds;
    }

    @InvocableMethod(
        label='List Accounts'
        description='Lists Account records with optional filters and returns Account IDs for easy selection.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> outList = new List<Response>();
        if (requests == null || requests.isEmpty()) return outList;

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Request req : requests) {
            Response res = new Response();
            res.done = false;
            res.accountIds = new List<String>();

            Integer limitSize = (req.maxResults == null ? 10 : req.maxResults);
            if (limitSize < 1) limitSize = 1;
            if (limitSize > 25) limitSize = 25;

            // If accountId provided, return just that
            if (!isBlank(req.accountId)) {
                List<Account> one = [
                    SELECT Id, Name, AccountNumber, Phone, Website, Industry, BillingCity, Owner.Name
                    FROM Account
                    WHERE Id = :req.accountId
                    LIMIT 1
                ];
                if (one.isEmpty()) {
                    res.done = true;
                    res.message = '<p>No account found for Account Id <code>' + escapeHtml(req.accountId) + '</code>.</p>';
                    outList.add(res);
                    continue;
                }

                Account a = one[0];
                res.accountIds.add((String)a.Id);

                res.done = true;
                res.message =
                    '<p>Account:</p>' +
                    '<ul>' +
                    formatAccountBlock(a, baseUrl) +
                    '</ul>';

                outList.add(res);
                continue;
            }

            // Resolve owner filter (optional)
            Id resolvedOwnerId = null;

            if (req.assignedToMe == true) {
                resolvedOwnerId = UserInfo.getUserId();
            } else if (!isBlank(req.ownerId)) {
                resolvedOwnerId = (Id)req.ownerId.trim();
            } else if (!isBlank(req.ownerName)) {
                String ownerTerm = '%' + req.ownerName.trim() + '%';
                List<User> owners = [
                    SELECT Id, Name, Username
                    FROM User
                    WHERE IsActive = true AND Name LIKE :ownerTerm
                    ORDER BY Name
                    LIMIT 10
                ];

                if (owners.size() > 1) {
                    res.message =
                        '<p>Multiple active users match that owner name. Reply with the Owner Id (005...) from this list:</p>' +
                        formatUserChoices(owners, 6);
                    outList.add(res);
                    continue;
                }
                if (owners.size() == 1) {
                    resolvedOwnerId = owners[0].Id;
                }
            }

            // Build simple-binds dynamic SOQL
            String acctNum = isBlank(req.accountNumber) ? null : req.accountNumber.trim();
            String nameTerm = isBlank(req.accountName) ? null : ('%' + req.accountName.trim() + '%');
            String cityTerm = isBlank(req.billingCity) ? null : ('%' + req.billingCity.trim() + '%');
            String industry = isBlank(req.industry) ? null : req.industry.trim();

            String soql =
                'SELECT Id, Name, AccountNumber, Phone, Website, Industry, BillingCity, Owner.Name, LastModifiedDate ' +
                'FROM Account ' +
                'WHERE IsDeleted = false ';

            if (resolvedOwnerId != null) soql += 'AND OwnerId = :resolvedOwnerId ';
            if (acctNum != null) soql += 'AND AccountNumber = :acctNum ';
            if (nameTerm != null) soql += 'AND Name LIKE :nameTerm ';
            if (cityTerm != null) soql += 'AND BillingCity LIKE :cityTerm ';
            if (industry != null) soql += 'AND Industry = :industry ';

            soql += 'ORDER BY LastModifiedDate DESC LIMIT :limitSize';

            List<Account> accounts = Database.query(soql);

            if (accounts.isEmpty()) {
                res.done = true;
                res.message = '<p>No accounts found for that filter.</p>';
                outList.add(res);
                continue;
            }

            String html = '<p>Here are the most recent matching accounts:</p><ul>';

            for (Account a : accounts) {
                res.accountIds.add((String)a.Id);
                html += formatAccountBlock(a, baseUrl);
            }

            html += '</ul><p>Reply with the Account Id if you want to update or use it in another action.</p>';

            res.done = true;
            res.message = html;
            outList.add(res);
        }

        return outList;
    }

    // --- Rendering: each info point on its own line ---
    private static String formatAccountBlock(Account a, String baseUrl) {
        String html = '<li>';

        html += '<a href="' + baseUrl + '/lightning/r/Account/' + a.Id + '/view" target="_blank" rel="noopener noreferrer"><code>' +
                a.Id + '</code></a><br/>';

        html += '<b>Name:</b> ' + escapeHtml(a.Name) + '<br/>';

        if (!isBlank(a.AccountNumber)) html += '<b>Account Number:</b> ' + escapeHtml(a.AccountNumber) + '<br/>';
        if (!isBlank(a.Phone)) html += '<b>Phone:</b> ' + escapeHtml(a.Phone) + '<br/>';
        if (!isBlank(a.Website)) html += '<b>Website:</b> ' + escapeHtml(a.Website) + '<br/>';
        if (!isBlank(a.BillingCity)) html += '<b>Billing City:</b> ' + escapeHtml(a.BillingCity) + '<br/>';
        if (!isBlank(a.Industry)) html += '<b>Industry:</b> ' + escapeHtml(a.Industry) + '<br/>';
        if (a.Owner != null && !isBlank(a.Owner.Name)) html += '<b>Owner:</b> ' + escapeHtml(a.Owner.Name) + '<br/>';

        // Trim trailing <br/> visually by ending the list item cleanly
        html += '</li>';
        return html;
    }

    private static String formatUserChoices(List<User> users, Integer maxToShow) {
        Integer showCount = Math.min(maxToShow, users.size());
        String html = '<ul>';

        for (Integer i = 0; i < showCount; i++) {
            User u = users[i];
            html += '<li>';
            html += '<code>' + u.Id + '</code><br/>';
            html += '<b>Name:</b> ' + escapeHtml(u.Name) + '<br/>';
            if (u.Username != null) html += '<b>Username:</b> ' + escapeHtml(u.Username) + '<br/>';
            html += '</li>';
        }

        html += '</ul>';

        if (users.size() > showCount) {
            html += '<p>Showing ' + showCount + ' of ' + users.size() + ' matches. Please provide the Owner Id.</p>';
        }

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