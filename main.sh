#!/bin/bash
#
source .env;
source functions.sh;

for assertion in `ls -1 assertions/*`; do
    source ${assertion};
done;

for assertion in `ls -1 callbacks/*`; do
    source ${assertion};
done;

# normalize IFS
export IFS=$' \t\n'

rules=( $(scan_rules) );

for rules_file in ${rules[@]}; do
    endpoint_url=$(extract_endpoint ${rules_file});
    method=$(extract_method ${rules_file});

    # This will be something like "post_payment_capture_001-success"
    testcase_id=$(extract_prefix ${rules_file});

    # From this point on, we are telling bash that new lines (\n) and
    # semicolons (;) define entries in a file or in word expansion. Not
    # tabs (\t), as we need them as part of the syntax in rule files.
    IFS=$'\n;';

    # Creating a dictionary of rules by test cases:
    loaded_rules[${testcase_id}]=$(load_rules ${rules_file});

    # Fixtures dictionary
    loaded_fixtures[${testcase_id}]=$(load_fixtures ${testcase_id});

    echo -e "Sending request payload for rules file: ${rules_file}\n";

    # Endpoint response body
    response_body=$(get_response_body ${method} ${endpoint_url} "${loaded_fixtures[$testcase_id]}");

    # Validating response body
    _validate_json "${response_body}";

    # HTTP response status. This is not the same (although it should match) the
    # value included in the JSON response under the 'code' element
    response_status_code=$(get_status_code ${method} ${endpoint_url} "${loaded_fixtures[$testcase_id]}");

    echo "Response: ${response_body}";
    echo -e "------------------------\n";

    for test_rule in ${loaded_rules[$testcase_id]}; do
        apply_rule ${test_rule} "${response_body}";
    done;
done;

exit 0;
