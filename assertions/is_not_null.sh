#!/bin/bash

function is_not_null() {
    if [ $# -lt 1 ]; then
        echo "Insuficient amount of arguments ($#): '$@'";
        kill $$;
        exit;
    fi;

    echo "Asserting that '$1' is NOT null:";

    if [ "$1" != "null" ]; then
        echo "PASS";
    else
        echo "FAIL";
        kill $$;
        exit;
    fi;
}
