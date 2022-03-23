#!/bin/bash

function equals() {
    if [ $# -lt 2 ]; then
        echo "Insuficient amount of arguments ($#): '$@'";
        kill $$;
        exit;
    fi;

    echo "Asserting that '$1' equals '$2':";

    if [ "$1" == "$2" ]; then
        echo "PASS";
    else
        echo "FAIL";
        kill $$;
        exit;
    fi;
}
