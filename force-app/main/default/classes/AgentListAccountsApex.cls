public with sharing class AgentListAccountsApex {
    public class Input { @InvocableVariable public Integer limitN; }
    public class Out   { @InvocableVariable public String message; @InvocableVariable public Boolean done; }

    @InvocableMethod(label='List Accounts (Apex)')
    public static List<Out> run(List<Input> inputs) {
        Integer lim = 10;
        if (inputs != null && !inputs.isEmpty() && inputs[0].limitN != null) {
            lim = Math.max(1, Math.min(200, inputs[0].limitN));
        }
        List<Account> accs = [
            SELECT Name, NumberOfEmployees
            FROM Account
            ORDER BY Name
            LIMIT :lim
        ];
        List<String> lines = new List<String>();
        lines.add('Showing ' + accs.size() + ' account(s):');
        for (Account a : accs) {
            String line = '- ' + a.Name;
            if (a.NumberOfEmployees != null) line += ' (' + String.valueOf(a.NumberOfEmployees) + ' emp)';
            lines.add(line);
        }
        Out o = new Out();
        o.message = String.join(lines, '\n');
        o.done = true;
        return new List<Out>{ o };
    }
}