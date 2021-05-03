#!/bin/bash

command=$1
echo $command;

primaryHttpAddress="127.0.0.1:9092"
primaryTcpAddress="127.0.0.1:3017"
secoundary1HttpAddress="127.0.0.1:9093"
secoundary2HttpAddress="127.0.0.1:9094"
user="mateus"
password="$user"
timeoutSpeep=3
replicaSetAddrs="127.0.0.1:3016,127.0.0.1:3017,127.0.0.1:3018"


cargo build


if [ $command = "kill" ] || [ $command = "all" ]
then
    cat .primary.pid | xargs -I '{}' kill -9 {}
    cat .secoundary.pid | xargs -I '{}' kill -9 {}

fi
if [ $command = "clean" ] || [ $command = "all" ]
then
    echo "Clean!"
    rm .secoundary.pid
    rm .primary.pid
    rm dbs/*
    rm dbs1/*
    rm dbs2/*
fi

if [ $command = "all" ]
then
    echo "Add trap if all"
    trap "kill 0" EXIT
fi


if [ $command = "start-1" ] || [ $command = "all" ]
then
    echo "Starting the primary"
    NUN_DBS_DIR=./dbs RUST_BACKTRACE=1 ./target/debug/nun-db --user $user -p $user start --http-address "$primaryHttpAddress" --tcp-address "$primaryTcpAddress" --ws-address "127.0.0.1:3058" --replicate-address "$replicaSetAddrs" >primary.log&
    PRIMARY_PID=$!
    echo $PRIMARY_PID >> .primary.pid
    sleep $timeoutSpeep
fi

sleep $timeoutSpeep

if [ $command = "start-2" ] || [ $command = "all" ]
then
    echo "Starting secoundary 1"
    NUN_DBS_DIR=./dbs1 RUST_BACKTRACE=1 ./target/debug/nun-db --user $user -p $user start --http-address "$secoundary1HttpAddress" --tcp-address "127.0.0.1:3016" --ws-address "127.0.0.1:3057" --replicate-address "$replicaSetAddrs">secoundary.log&
    SECOUNDARY_PID=$!
    echo $SECOUNDARY_PID >> .secoundary.pid
    sleep $timeoutSpeep
fi

sleep $timeoutSpeep

if [ $command = "start-3" ] || [ $command = "all" ]
then
    echo "Starting secoundary 2"
    NUN_DBS_DIR=./dbs2 RUST_BACKTRACE=1 ./target/debug/nun-db --user $user -p $user start --http-address "$secoundary2HttpAddress" --tcp-address "127.0.0.1:3018" --ws-address "127.0.0.1:3059" --replicate-address "$replicaSetAddrs">secoundary.2.log&
    SECOUNDARY_2_PID=$!
    echo $SECOUNDARY_2_PID >> .secoundary.pid
    sleep $timeoutSpeep 

fi
sleep $timeoutSpeep
if [ $command = "all" ]
then
    echo "Giving time to election!!!"
    sleep 10
fi

if [ $command = "save-admin" ] || [ $command = "all" ]
then
        RUST_BACKTRACE=1 ./target/debug/nun-db -p $password -u $user --host "http://$primaryHttpAddress" exec "auth mateus mateus; use-db \$admin mateus; snapshot;"
        RUST_BACKTRACE=1 ./target/debug/nun-db -p $password -u $user --host "http://$secoundary1HttpAddress" exec "auth mateus mateus; use-db \$admin mateus; snapshot;"
        RUST_BACKTRACE=1 ./target/debug/nun-db -p $password -u $user --host "http://$secoundary2HttpAddress" exec "auth mateus mateus; use-db \$admin mateus; snapshot;"
fi


exit 0
