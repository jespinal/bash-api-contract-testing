#!/usr/bin/env bash

function not_equals() {
    if [ $# -lt 2 ]; then
        echo "Insuficient amount of arguments ($#): '$@'";
        kill $$;
        exit;
    fi;

    echo "Asserting that '$1' is NOT equal to '$2':";

    if [ "$1" != "$2" ]; then
        echo "PASS";
    else
        echo "FAIL";
        kill $$;
        exit;
    fi;
}
