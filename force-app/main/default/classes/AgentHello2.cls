public with sharing class AgentHello2 {
    public class Input {
        @InvocableVariable public String name; // optional
    }
    public class Row {
        @InvocableVariable public String message;
    }
    @InvocableMethod(label='Hello World (Test v2)')
    public static List<Row> run(List<Input> inputs) {
        String n = (inputs != null && !inputs.isEmpty() && !String.isBlank(inputs[0].name))
                   ? inputs[0].name : 'there';
        Row r = new Row();
        r.message = 'Hello, ' + n + '! The pipeline is working.';
        return new List<Row>{ r };
    }
}