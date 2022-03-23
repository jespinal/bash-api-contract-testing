#!/bin/bash

function is_numeric() {
    if [ $# -lt 1 ]; then
        echo "Insuficient amount of arguments ($#): '$@'";
        kill $$;
        exit;
    fi;

    echo "Asserting that $1 is numeric:";

    # Catching _only_ characters not including in 0-9
    value=$(printf $1 | grep '[^0-9]\+' -o | tr -d '\n');

    if [ -z "$value" ]; then
        echo "PASS";
    else
        echo "FAIL";
        kill $$;
        exit;
    fi;
}
