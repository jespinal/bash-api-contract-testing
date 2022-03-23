#!/bin/bash

# Count Arguments
#
# @param int Number of arguments received in the calling function
# @param int Expected number of arguments
_count_arguments() {
    arg_num=$1;
    arg_expected=$2;

    if [ ${arg_num} -lt ${arg_expected} ]; then
        echo "${FUNCNAME[1]}: Insuficient amount of arguments (${arg_num}), $1 expected.";
        kill $$;
        exit;
    fi;
}

# Scan Rules
#
# Get the list of rules files, with the exception of those listed in the `rules-blacklist.conf` file
#
# @return list of rules files
scan_rules() {
    for file_name in $(find rules/ -maxdepth 1 -name "*.rlz" -printf "%f\n" | grep -v '^#' | grep -v '^$' | sort); do
        # If the rules file name is included in the blacklist, skip it.
        #
        # -x: Select only those matches that exactly match the whole line.
        # -F: Interpret PATTERN as a list of fixed strings (instead of regular expressions)
        # -c: Suppress normal output; instead print a count of matching lines for each input file.
        if [ $(grep -x -F -c ${file_name} ./rules-blacklist.conf) -gt 0 ]; then
            continue;
        else
            printf "${file_name}\n";
        fi;
    done;
}

# Load Rules
#
# @return string content of a given rules file, filtering out
# all commented and empty lines.
load_rules() {
    cat "rules/$1" | grep -v '^#' | grep -v '^$';
}

# Load Fixtures
#
# @param string Prefix (testcase id)
# @return string JSON body in the fixture file
load_fixtures() {
    fixture_id=$(echo $1 | sed -e 's|_|.|g');
    fixture_file="./rules/fixtures/${fixture_id}.json";

    if [ ! -f ${fixture_file} ]; then
        echo "Unable to load fixture: '${fixture_file}'" > /dev/stderr;
        kill $$;
    fi

    cat "./rules/fixtures/${fixture_id}.json" | tr -d '\n\t'
}

# Extract Prefix
#
# @param string Rule file
# @return string Basename of rule file with some processing applied
extract_prefix() {
    basename $1 .rlz | sed -e 's|\.|_|g'
}

# Extract Method
#
# @param string Rule file
# @return string endpoint
extract_method() {
    printf $1 | cut -d. -f1 | tr [a-z] [A-Z];
}

# Extract Endpoint
#
# @param string Rule file
# @return string endpoint
extract_endpoint() {
    printf $1 | cut -d. -f3
}

#
# Validate JSON
#
# @param string JSON response
_validate_json() {
    _count_arguments $# 1;

    json_response=$1;
    jq . >/dev/null 2>&1 <<JSON
        $json_response
JSON

    if [ $? -gt 0 ]; then
      echo
      echo "+=====================+";
      echo "| Invalid JSON format |";
      echo "+=====================+";
      echo
      cat <<BAD_JSON
$json_response
BAD_JSON
      kill $$;
      exit 1;
    fi;
}

# Get Status Code
#
# By default, HTTPie exits with 0 when no network or other fatal errors occur.
#
# In this method we instruct HTTPie to also check the HTTP status code and
# exit with an error if the status indicates one.
#
# When the server replies with a 4xx (Client Error) or 5xx (Server Error)
# status code, HTTPie exits with 4 or 5 respectively. If the response is a
# 3xx (Redirect) and --follow hasn't been set, then the exit status is 3.
#
# @param string method - HTTP method (POST, GET, etc.)
# @param string url
# @return int
get_status_code() {
    _count_arguments $# 3;

    method=$1;
    url=$2;
    json_payload=$3;

    if [ -z ${ENVIRONMENT} ]; then
        ENVIRONMENT=DEV;
    else
        ENVIRONMENT=$(printf ${ENVIRONMENT} | tr '[a-z]' '[A-Z]');
    fi

    # This are indirect references: variables which point to the value
    # of another variable. The final variable name will depend on the
    # envinronment, and the value is set in the `.env` file
    declare -n kongapi_id="API_ID_${ENVIRONMENT}";
    declare -n kongapi_key="API_KEY_${ENVIRONMENT}";
    declare -n endpoint_base_url="ENDPOINT_BASE_URL_${ENVIRONMENT}";

    # Extracting only the headers and passing them as a 'herestring' to awk.
    # In awk we print the second field ($2) of the Number Row=1.
    awk 'NR==1 { print $2 }' <<<$(http ${method} "${endpoint_base_url}/$url" "${kongapi_id}:${kongapi_key}" --headers <<RQST
        $json_payload
RQST
);
}

# Get Response Body
#
# @param string HTTP method
# @param string Endpoint URI (E.g. payment/capture)
# @param string JSON payload: request body
# @return string JSON response
get_response_body() {
    _count_arguments $# 3;
    method=$1;
    url=$2;
    json_payload=$3;

    if [ -z ${ENVIRONMENT} ]; then
        ENVIRONMENT=DEV;
    else
        ENVIRONMENT=$(printf ${ENVIRONMENT} | tr '[a-z]' '[A-Z]');
    fi

    # This are indirect references: variables which point to the value
    # of another variable. The final variable name will depend on the
    # envinronment, and the value is set in the `.env` file
    declare -n kongapi_id="API_ID_${ENVIRONMENT}";
    declare -n kongapi_key="API_KEY_${ENVIRONMENT}";
    declare -n endpoint_base_url="ENDPOINT_BASE_URL_${ENVIRONMENT}";

    http ${method} "${endpoint_base_url}/$url" "${kongapi_id}:${kongapi_key}" --body <<RQST
    $json_payload
RQST
}

# Apply Rule
#
# Given a JSON response and a rule, this method will apply the
# indicated assertion to the response.
#
# @param string Test rule
# @param string JSON response
apply_rule() {
    _count_arguments $# 2;
    rule=$1;
    response=$2;

    jq_filter=$(echo ${rule} | awk -F"\t" '{ print $1 }');
    assertion_name=$(echo ${rule} | awk  -F"\t" '{ print $2 }');
    expected_value=$(echo ${rule} | awk -F"\t" '{ print $3 }');
    assertion_comment=$(echo ${rule} | awk -F"\t" '{ print $4 }');

    # Is this a callback being called?
    if [ "$(grep -c 'callback_' <<<"${jq_filter}")" != "0" ]; then

      # Extract the name of the callback (removing "callback_")
      callback_name=$(sed -e 's|callback_||g' <<<"${jq_filter}");

      # Calling the callback and passing the expected value as argument.
      #
      # This value might be null/empty (according to the rules file) when
      # the callback won't really use it.
      value_from_response=$(
        ${callback_name} "${expected_value}";
      );
    else
      value_from_response=$(
          jq ${jq_filter} <<RESPONSE
  ${response}
RESPONSE
      );
    fi;

    # If there's a comment for this rule, print it. It might add some
    # clarity to the output
    if [ ! -z "${assertion_comment}" ]; then
      echo "Comment: ${assertion_comment}";
    fi;

    ${assertion_name} "${value_from_response}" "${expected_value}";
}
