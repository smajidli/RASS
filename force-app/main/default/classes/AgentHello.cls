public with sharing class AgentHello {
    public class Input {
        @InvocableVariable public String name; // optional; satisfies "needs at least one input"
    }
    public class Row {
        @InvocableVariable public String message; // simple string output (no Decimal)
    }
    @InvocableMethod(label='Hello World (Test)')
    public static List<List<Row>> run(List<Input> inputs) {
        String n = (inputs != null && !inputs.isEmpty() && !String.isBlank(inputs[0].name))
                   ? inputs[0].name : 'there';
        Row r = new Row();
        r.message = 'Hello, ' + n + '! The agent→action pipeline is working.';
        return new List<List<Row>>{ new List<Row>{ r } };
    }
}