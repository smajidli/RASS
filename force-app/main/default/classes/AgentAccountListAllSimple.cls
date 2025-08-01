public with sharing class AgentAccountListAllSimple {

    // Optional input (so the Agent Action has at least one input)
    public class Input {
        @InvocableVariable public Integer limitN; // default 200, max 2000
    }

    // Output row — NOTE: no Decimal types
    public class Row {
        @InvocableVariable public Id      Id;
        @InvocableVariable public String  Name;
        @InvocableVariable public Integer NumberOfEmployees;
        @InvocableVariable public String  AnnualRevenueText; // String instead of Decimal
        @InvocableVariable public String  Type;
        @InvocableVariable public String  OwnerName;
    }

    @InvocableMethod(label='List All Accounts (Simple, No Decimals)')
    public static List<List<Row>> run(List<Input> inputs) {
        Integer lim = (inputs != null && !inputs.isEmpty() && inputs[0].limitN != null)
                      ? Math.min(2000, Math.max(1, inputs[0].limitN)) : 200;

        List<Account> accs = [
            SELECT Id, Name, NumberOfEmployees, AnnualRevenue, Type, Owner.Name
            FROM Account
            ORDER BY Name
            LIMIT :lim
        ];

        List<Row> out = new List<Row>();
        for (Account a : accs) {
            Row r = new Row();
            r.Id = a.Id;
            r.Name = a.Name;
            r.NumberOfEmployees = a.NumberOfEmployees;
            r.AnnualRevenueText = (a.AnnualRevenue == null) ? null : String.valueOf(a.AnnualRevenue);
            r.Type = a.Type;
            r.OwnerName = (a.Owner != null) ? a.Owner.Name : null;
            out.add(r);
        }
        return new List<List<Row>>{ out }; // invocable must return list-of-lists
    }
}