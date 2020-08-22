#!/bin/bash
trap "kill 0" EXIT

echo "Starting the primary"
primaryHttpAddress="127.0.0.1:9092"
primaryTcpAddress="127.0.0.1:3017"
secoundary1HttpAddress="127.0.0.1:9093"
secoundary2HttpAddress="127.0.0.1:9094"

cargo run -- --user mateus -p mateus start --http-address "$primaryHttpAddress" --tcp-address "$primaryTcpAddress" --ws-address "0.0.0.0:3058">primary.log&

echo "Starting secoundary 1"

cargo run -- --user mateus -p mateus start --http-address "$secoundary1HttpAddress" --tcp-address "0.0.0.0:3016" --ws-address "0.0.0.0:3057">secoundary.log&

echo "Starting secoundary 2"

cargo run -- --user mateus -p mateus start --http-address "$secoundary2HttpAddress" --tcp-address "0.0.0.0:3018" --ws-address "0.0.0.0:3059">secoundary23log&


echo "Will Connect the secoundaries to the primary"

sleep 10

joinResult=$(curl -s -X "POST" "$primaryHttpAddress" -d "auth mateus mateus; join 127.0.0.1:3016")
echo "Join 1result $joinResult"

joinResult=$(curl -s -X "POST" "$primaryHttpAddress" -d "auth mateus mateus; join 127.0.0.1:3018")

echo "Join result $joinResult"

sleep 3
curl -s -X "POST" "$primaryHttpAddress" -d "auth mateus mateus; create-db test-db test-db-key;"

start_time="$(date -u +%s)"
for i in {1..20}
do
	echo "Set in the primary"
	r=$(curl -s -X "POST" "$primaryHttpAddress" -d "use-db test-db test-db-key; set state jose-$i-1;")
	echo "Read from the secoundary"
    sleep 1
	get_result=$(curl -s -X "POST" "$secoundary1HttpAddress" -d "use-db test-db test-db-key; get state")
	get_result2=$(curl -s -X "POST" "$secoundary2HttpAddress" -d "use-db test-db test-db-key; get state")
	if [ "$get_result" != "empty;value jose-$i-1" ]; then
		echo "Invalid value value in the secoundary 1: $get_result $i"
		exit 1
	else
		if [ "$get_result2" != "empty;value jose-$i-1" ]; then
			echo "Invalid value value in the secoundary 2: $get_result $i"
			exit 1
		else
			echo "Request $i Ok"
		fi 
	fi
done
end_time="$(date -u +%s)"
elapsed="$(($end_time-$start_time))"
echo "Total of $elapsed seconds elapsed for process"
exit 0

