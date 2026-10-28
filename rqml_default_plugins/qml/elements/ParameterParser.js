.pragma library

// rcl_interfaces/msg/ParameterValue field by ParameterType.
const valueFields = {
    "1": "bool_value",
    "2": "integer_value",
    "3": "double_value",
    "4": "string_value",
    "6": "bool_array_value",
    "7": "integer_array_value",
    "8": "double_array_value",
    "9": "string_array_value"
};

/**
 * Parses one `name:=value` per line, as `ros2 component load -p` takes them, into rcl_interfaces/msg/Parameter
 * messages. Blank lines are skipped and the value is everything after the first `:=`.
 * Values are typed YAML-like: true/false is a bool, 42 an integer, 1.5 or 1e-3 a double, "quoted" or anything else a
 * string. [a, b] is an array of the item type; integers mixed with doubles make a double array, an empty array is a
 * bool array and other mixes make the whole value a string, as in ros2cli.
 * Returns {parameters, invalidLine} with the 1-based number of the first line that is not `name:=value`, holds an
 * integer beyond ±2^53 or an array item with an unclosed quote, 0 if none.
 */
function parseParameters(text) {
    const parameters = [];
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; ++i) {
        const line = lines[i].trim();
        if (line === "")
            continue;
        const separator = line.indexOf(":=");
        // The line is trimmed, so a separator after the first character means a non-empty name.
        const value = separator < 1 ? null : parseValue(line.slice(separator + 2).trim());
        if (value === null)
            return {
                "parameters": [],
                "invalidLine": i + 1
            };
        parameters.push({
            "name": line.slice(0, separator).trim(),
            "value": value
        });
    }
    return {
        "parameters": parameters,
        "invalidLine": 0
    };
}

// Returns the ParameterValue of text, null if it holds an integer a JS number cannot hold exactly or an array item
// with an unclosed quote.
function parseValue(text) {
    if (!/^\[.*\]$/.test(text)) {
        const [type, value] = parseScalar(text);
        if (type === 0)
            return null;
        return {
            "type": type,
            [valueFields[type]]: value
        };
    }
    // Commas inside quotes do not split items.
    const itemPattern = /(?:"[^"]*"|'[^']*'|[^,"'])+/g;
    const inner = text.slice(1, -1);
    // An unclosed quote is all the item pattern leaves besides separators.
    if (/["']/.test(inner.replace(itemPattern, "")))
        return null;
    const items = (inner.match(itemPattern) ?? []).map(item => item.trim()).filter(item => item !== "").map(parseScalar);
    if (items.some(([itemType]) => itemType === 0))
        return null;
    const type = [1, 2, 3, 4].find(type => items.every(([itemType]) => itemType === type || (type === 3 && itemType === 2)));
    if (type === undefined)
        return {
            "type": 4,
            "string_value": text
        };
    return {
        "type": type + 5,
        [valueFields[type + 5]]: items.map(([, value]) => value)
    };
}

// Returns [ParameterType, value] of a scalar, [0] for an integer a JS number cannot hold exactly.
function parseScalar(text) {
    if (/^(true|True|TRUE|false|False|FALSE)$/.test(text))
        return [1, text.toLowerCase() === "true"];
    if (/^[-+]?\d+$/.test(text))
        return Number.isSafeInteger(Number(text)) ? [2, Number(text)] : [0];
    if (/^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/.test(text))
        return [3, Number(text)];
    const quoted = text.match(/^"(.*)"$|^'(.*)'$/);
    return [4, quoted ? quoted[1] ?? quoted[2] : text];
}
