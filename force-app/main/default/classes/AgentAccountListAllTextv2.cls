public with sharing class AgentAccountListAllTextv2 {
    public class Input  { @InvocableVariable public Integer limitN; } // optional
    public class Out    { @InvocableVariable public String  message; } // single string

    @InvocableMethod(label='List Accounts (Text v2)')
    public static List<Out> run(List<Input> inputs) {
        List<Out> result = new List<Out>();
        try {
            Integer lim = (inputs != null && !inputs.isEmpty() && inputs[0].limitN != null)
                          ? Math.min(200, Math.max(1, inputs[0].limitN))
                          : 20;

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
                if (a.NumberOfEmployees != null) {
                    line += ' (' + String.valueOf(a.NumberOfEmployees) + ' emp)';
                }
                lines.add(line);
            }

            Out o = new Out();
            o.message = String.join(lines, '\n');
            result.add(o);
        } catch (Exception e) {
            Out o = new Out();
            o.message = 'ERROR: ' + e.getTypeName() + ': ' + e.getMessage();
            result.add(o);
        }
        return result; // invocable must return a list
    }
}