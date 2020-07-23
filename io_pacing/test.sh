#!/usr/bin/env bash

# Input test parameters
TEST_TIME=${TEST_TIME-60}
RW=${RW-randread}
QD=${QD-32}
IO_SIZE=${IO_SIZE-128k}
FIO_JOB=${FIO_JOB-"fio-16ns"}
FIO_RAMP_TIME=${FIO_RAMP_TIME-5}
KERNEL_DRIVER=${KERNEL_DRIVER-0}

# Test setup configuration
if [ "1" == "$SETUP" ]; then
    HOSTS="spdk08.swx.labs.mlnx spdk03.swx.labs.mlnx"
    TARGET="ubuntu@spdk-tgt-bw-03"
    TARGET_ADDRS="1.1.103.1 2.2.103.1"
    TARGET_SPDK_PATH="/home/evgeniik/spdk"
    TARGET_BF_COUNTERS="/home/evgeniik/bf_counters.py"
elif [ "2" == "$SETUP" ]; then
    HOSTS="spdk04.swx.labs.mlnx spdk05.swx.labs.mlnx"
    TARGET="ubuntu@swx-bw-07"
    TARGET_ADDRS="1.1.107.1 2.2.107.1"
    TARGET_SPDK_PATH="/home/ubuntu/work/spdk"
    TARGET_BF_COUNTERS="/home/ubuntu/work/bf_counters.py"
else
    echo "Unknown setup. Please, set SETUP variable."
    exit 1
fi

# Paths configuration
FIO_PATH="$PWD/../../fio"
SPDK_PATH="$PWD/.."
FIO_JOBS_PATH="$PWD/jobs"
OUT_PATH="$PWD/out"
mkdir -p $OUT_PATH

# Other configurations
ENABLE_DEVICE_COUNTERS=1
ENABLE_DETAILED_STATS=

# Internal variables

function m()
{
    M_SCALE=${M_SCALE-1}
    bc 2>/dev/null <<< "scale=$M_SCALE; $@"
}

function get_device_counters()
{
    ssh $TARGET sudo python /opt/neohost/sdk/get_device_performance_counters.py --dev-uid=0000:17:00.0 --output-format=JSON > $OUT_PATH/device-counters.json
}

function get_bf_counters()
{
    ssh $TARGET sudo python $TARGET_BF_COUNTERS > $OUT_PATH/bf_counters.log
}

function parse_fio()
{
    local LOG=$1; shift

    IOPS_R=$(jq .jobs[].read.iops $LOG 2>/dev/null)
    BW_R=$(jq .jobs[].read.bw_bytes $LOG 2>/dev/null)
    BW_MAX_R=$(jq .jobs[].read.bw_max $LOG 2>/dev/null)
    BW_STDDEV_R=$(jq .jobs[].read.bw_dev $LOG 2>/dev/null)
    LAT_AVG_R=$(jq .jobs[].read.lat_ns.mean $LOG 2>/dev/null)

    IOPS_W=$(jq .jobs[].write.iops $LOG 2>/dev/null)
    BW_W=$(jq .jobs[].write.bw_bytes $LOG 2>/dev/null)
    BW_MAX_W=$(jq .jobs[].write.bw_max $LOG 2>/dev/null)
    BW_STDDEV_W=$(jq .jobs[].write.bw_dev $LOG 2>/dev/null)
    LAT_AVG_W=$(jq .jobs[].write.lat_ns.mean $LOG 2>/dev/null)
}

function print_report()
{
    local HOSTS=$@
    local SUM_IOPS_R=0
    local SUM_BW_R=0
    local SUM_BW_MAX_R=0
    local SUM_BW_STDDEV_R=0
    local SUM_LAT_AVG_R=0
    local SUM_IOPS_W=0
    local SUM_BW_W=0
    local SUM_BW_MAX_W=0
    local SUM_BW_STDDEV_W=0
    local SUM_LAT_AVG_W=0

    echo "Test parameters"
    echo "Time        : $TEST_TIME"
    echo "Read/write  : $RW"
    echo "Queue depth : $QD"
    echo "IO size     : $IO_SIZE"
    echo "Fio job     : $FIO_JOB"
    echo ""

    echo Results
    local FORMAT="%-30s | %-10s | %-10s | %-10s | %-15s | %-15s | %-15s | %-15s | %-15s | %-20s\n"
    printf "$FORMAT" "Host" "kIOPS" "BW,Gb/s" "BW Max" "AVG_LAT,us" "Wire BW,Gb/s" "BW STDDEV" "L3 Hit Rate, %" "Bufs in-flight" "Pacer period, us"
    printf "$FORMAT" | tr " " "-"

    local count=0
    for host in $HOSTS; do
	parse_fio $OUT_PATH/fio-$host.json

	SUM_IOPS_R=$(m $SUM_IOPS_R + $IOPS_R)
	SUM_BW_R=$(m $SUM_BW_R + $BW_R)
	SUM_BW_MAX_R=$(m $SUM_BW_MAX_R + $BW_MAX_R)
	SUM_BW_STDDEV_R=$(m $SUM_BW_STDDEV_R + $BW_STDDEV_R^2)
	SUM_LAT_AVG_R=$(m $SUM_LAT_AVG_R + $LAT_AVG_R)

	SUM_IOPS_W=$(m $SUM_IOPS_W + $IOPS_W)
	SUM_BW_W=$(m $SUM_BW_W + $BW_W)
	SUM_BW_MAX_W=$(m $SUM_BW_MAX_W + $BW_MAX_W)
	SUM_BW_STDDEV_W=$(m $SUM_BW_STDDEV_W + $BW_STDDEV_W^2)
	SUM_LAT_AVG_W=$(m $SUM_LAT_AVG_W + $LAT_AVG_W)

	# @todo: add support for mixed case
	if [[ "$RW" == *"read"* ]]; then
	    printf "$FORMAT" $host $(m $IOPS_R/1000) $(m $BW_R*8/1000^3) "$(m $BW_MAX_R*8*1024/1000^3)" $(m $LAT_AVG_R/1000) "" "$(m $BW_STDDEV_R*8*1024/1000^3)"
	elif  [[ "$RW" == *"write"* ]]; then
	    printf "$FORMAT" $host $(m $IOPS_W/1000) $(m $BW_W*8/1000^3) "$(m $BW_MAX_W*8*1024/1000^3)" $(m $LAT_AVG_W/1000) "" "$(m $BW_STDDEV_W*8*1024/1000^3)"
	else
	    printf "$FORMAT" "$host" "N/A"
	fi

	((count+=1))
    done
    SUM_LAT_AVG_R=$(m $SUM_LAT_AVG_R / $count)
    SUM_BW_STDDEV_R=$(m "sqrt($SUM_BW_STDDEV_R / $count)")
    SUM_LAT_AVG_W=$(m $SUM_LAT_AVG_W / $count)
    SUM_BW_STDDEV_W=$(m "sqrt($SUM_BW_STDDEV_W / $count)")

    printf "$FORMAT" | tr " " "-"

    if [ "1" == "$ENABLE_DEVICE_COUNTERS" ]; then
	local TX_BW_WIRE=$(jq '.analysis[].analysisAttribute | select(.name=="TX BandWidth") | .value' $OUT_PATH/device-counters.json 2>/dev/null)
	local RX_BW_WIRE=$(jq '.analysis[].analysisAttribute | select(.name=="RX BandWidth") | .value' $OUT_PATH/device-counters.json 2>/dev/null)

	local L3_HIT_RATE=0
	for l3hr in $(grep -Po "(?<=Hit Rate: )[0-9]*\.[0-9]*(?=%)" $OUT_PATH/bf_counters.log); do
	    L3_HIT_RATE=$(m $L3_HIT_RATE + $l3hr)
	done
	L3_HIT_RATE=$(m $L3_HIT_RATE/4)

	local BUFFERS_ALLOCATED=0
	for ba in $(jq .poll_groups[].transports[].buffers_allocated $OUT_PATH/nvmf_stats.log); do
	    BUFFERS_ALLOCATED=$((BUFFERS_ALLOCATED + ba))
	done
	BUFFERS_ALLOCATED=$(m $BUFFERS_ALLOCATED/3)

	local TOTAL_TICKS=0
	for tt in $(jq .poll_groups[].transports[].io_pacer.total_ticks $OUT_PATH/nvmf_stats_final.log); do
	    TOTAL_TICKS=$((TOTAL_TICKS + tt))
	done
	local TOTAL_POLLS=0
	for tp in $(jq .poll_groups[].transports[].io_pacer.polls $OUT_PATH/nvmf_stats_final.log); do
	    TOTAL_POLLS=$((TOTAL_POLLS + tp))
	done
	local TICK_RATE=$(jq .tick_rate $OUT_PATH/nvmf_stats_final.log)
	local PACER_PERIOD=$(m 10^6*$TOTAL_TICKS/$TICK_RATE/$TOTAL_POLLS)

    fi

    # @todo: add support for mixed case
    if [[ "$RW" == *"read"* ]]; then
	printf "$FORMAT" "Total" $(m $SUM_IOPS_R/1000) $(m $SUM_BW_R*8/1000^3)  $(m $SUM_BW_MAX_R*8*1024/1000^3) "$(m $SUM_LAT_AVG_R/1000)" "$TX_BW_WIRE" "$(m $SUM_BW_STDDEV_R*8*1024/1000^3)" "$L3_HIT_RATE" "$BUFFERS_ALLOCATED" "$PACER_PERIOD"
    elif  [[ "$RW" == *"write"* ]]; then
	printf "$FORMAT" "Total" $(m $SUM_IOPS_W/1000) $(m $SUM_BW_W*8/1000^3)  $(m $SUM_BW_MAX_W*8*1024/1000^3) "$(m $SUM_LAT_AVG_W/1000)" "$RX_BW_WIRE" "$(m $SUM_BW_STDDEV_W*8*1024/1000^3)" "$L3_HIT_RATE" "$BUFFERS_ALLOCATED" "$PACER_PERIOD"
    else
	printf "$FORMAT" "$host" "N/A"
    fi
}

function run_fio()
{
    local HOST=$1; shift
    local JOB=$1; shift

    [ -z "$JOB" ] && JOB=$FIO_JOBS_PATH/$FIO_JOB-$HOST.job

    local SSH=
    [ "$HOST" != "$HOSTNAME" ] && SSH="ssh $HOST"

    local FIO_PARAMS="--stats=1 --group_reporting=1 --thread=1 --direct=1 --norandommap \
    --time_based=1 --runtime=$TEST_TIME --ramp_time=$FIO_RAMP_TIME --file_service_type=roundrobin:1 \
    --readwrite=$RW --bssplit=$IO_SIZE --iodepth=$QD"

    [ -z "$FIO_NO_JSON" ] && FIO_PARAMS="--output-format=json --output=$OUT_PATH/fio-$HOST.json $FIO_PARAMS"

    echo "$HOST"
    echo "$JOB"
    echo "$FIO_PARAMS"
    $SSH sudo LD_PRELOAD=$SPDK_PATH/install-$HOST/lib/fio_plugin $FIO_PATH/install-$HOST/bin/fio $FIO_PARAMS $JOB
}

function progress_bar()
{
    local TIME=$1
    for i in $(seq $TIME); do
	sleep 1
	echo -n .
    done
}

function run_test()
{
    local HOSTS=$@

    echo "" > $OUT_PATH/nvmf_stats.log

    local PIDS=
    for host in $HOSTS; do
	run_fio $host > $OUT_PATH/fio-$host.log 2>&1 &
	PIDS="$PIDS $!"
	sleep 1
    done

    progress_bar $FIO_RAMP_TIME

    if [ "1" == "$ENABLE_DEVICE_COUNTERS" ]; then
	# Get nvmf stats 3 times and other stats one time
	progress_bar $((TEST_TIME/5))
	RPC_OUT=$OUT_PATH/nvmf_stats.log rpc nvmf_get_stats
	progress_bar $((TEST_TIME/5))
	get_device_counters
	get_bf_counters
	RPC_OUT=$OUT_PATH/nvmf_stats.log rpc nvmf_get_stats
	echo -n "-"
	progress_bar $((TEST_TIME/5))
	RPC_OUT=$OUT_PATH/nvmf_stats.log rpc nvmf_get_stats
    else
	progress_bar $((TEST_TIME))
    fi
    echo "!"
    wait $PIDS

    # Collect some stats
    echo "" > $OUT_PATH/thread_stats_final.log
    echo "" > $OUT_PATH/nvmf_stats_final.log
    echo "" > $OUT_PATH/bdev_stats_final.log

    RPC_OUT=$OUT_PATH/thread_stats_final.log rpc thread_get_stats
    RPC_OUT=$OUT_PATH/nvmf_stats_final.log rpc nvmf_get_stats
    RPC_OUT=$OUT_PATH/bdev_stats_final.log rpc bdev_get_iostat
}

function start_tgt()
{
    local CPU_MASK=$1; shift

    ssh $TARGET sudo $TARGET_SPDK_PATH/install/bin/spdk_tgt --wait-for-rpc -m $CPU_MASK > $OUT_PATH/tgt.log 2>&1 &
    sleep 10
}

function stop_tgt()
{
    ssh $TARGET 'sudo kill -15 $(pidof spdk_tgt)' >> $OUT_PATH/rpc.log 2>&1
    sleep 5
}

function connect_hosts()
{
    local HOSTS=$@
    NUM_QUEUES=${NUM_QUEUES-8}

    for host in $HOSTS; do
	local SSH=
	[ "$host" != "$HOSTNAME" ] && SSH="ssh $host"

	# Assuming that each host has path to only one listener and
	# another one will fail to connect
	for addr in $TARGET_ADDRS; do
	    $SSH sudo nvme connect -t rdma -a $addr  -s 4420 -n nqn.2016-06.io.spdk:cnode1 -i $NUM_QUEUES >> $OUT_PATH/rpc.log 2>&1
	done
    done
}

function disconnect_hosts()
{
    local HOSTS=$@

    for host in $HOSTS; do
	local SSH=
	[ "$host" != "$HOSTNAME" ] && SSH="ssh $host"

	$SSH sudo nvme disconnect -n nqn.2016-06.io.spdk:cnode1 >> $OUT_PATH/rpc.log 2>&1
    done
}

function rpc()
{
    RPC_OUT=${RPC_OUT-"$OUT_PATH/rpc.log"}
    ssh $TARGET sudo $TARGET_SPDK_PATH/scripts/rpc.py $@ >> $RPC_OUT 2>&1
}

function rpc_start()
{
    [ -e rpc_pipe ] && rm rpc_pipe
    mkfifo rpc_pipe
    tail -f > rpc_pipe &
    RPC_PID=$!
    ssh $TARGET sudo $TARGET_SPDK_PATH/scripts/rpc.py -v --server >> $OUT_PATH/rpc.log 2>&1 < rpc_pipe &
    SSH_PID=$!
}

function rpc_send()
{
    echo "$@" > rpc_pipe
}

function rpc_stop()
{
    kill $RPC_PID >> $OUT_PATH/rpc.log 2>&1
    wait $SSH_PID
    rm rpc_pipe
}

function basic_test()
{
    REPEAT=${REPEAT-1}
    BUFFER_SIZE=${BUFFER_SIZE-131072}

    local FORMAT="| %-10s | %-10s |  %-10s | %-10s | %-15s | %-10s | %-15s | %-20s | %-20s\n"
    printf "$FORMAT" "QD" "BW" "BW Max" "WIRE BW" "AVG LAT, us" "BW STDDEV" "L3 Hit Rate" "Bufs in-flight (MiB)" "Pacer period, us"

    for qd in $QD_LIST; do
	for rep in $(seq $REPEAT); do
	    QD=$qd run_test $HOSTS > /dev/null
	    OUT=$(print_report $HOSTS | tee $OUT_PATH/basic_test.log)
	    BW="$(echo "$OUT" | grep Total | awk '{print $5}')"
	    BW_MAX="$(echo "$OUT" | grep Total | awk '{print $7}')"
	    LAT_AVG="$(echo "$OUT" | grep Total | awk '{print $9}')"
	    WIRE_BW="$(echo "$OUT" | grep Total | awk '{print $11}')"
	    BW_STDDEV="$(echo "$OUT" | grep Total | awk '{print $13}')"
	    L3_HIT_RATE="$(echo "$OUT" | grep Total | awk '{print $15}')"
	    BUFFERS_ALLOCATED="$(echo "$OUT" | grep Total | awk '{print $17}')"
	    PACER_PERIOD="$(echo "$OUT" | grep Total | awk '{print $19}')"
	    printf "$FORMAT" "$qd" "$BW" "$BW_MAX" "$WIRE_BW" "$LAT_AVG" "$BW_STDDEV" "$L3_HIT_RATE" "$BUFFERS_ALLOCATED ($(m $BUFFERS_ALLOCATED*$BUFFER_SIZE/1024/1024))" "$PACER_PERIOD"
	    if [ -n "$ENABLE_DETAILED_STATS" ]; then
		./parse_stats.sh
	    fi
	done
    done
}

function config_null_1()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_CREDIT=${IO_PACER_CREDIT-131072}
    IO_PACER_THRESHOLD=${IO_PACER_THRESHOLD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    IO_PACER_TUNER_THRESHOLD=${IO_PACER_TUNER_THRESHOLD-12582912}
    IO_PACER_TUNER_FACTOR=${IO_PACER_TUNER_FACTOR-1}
    IO_UNIT_SIZE=${IO_UNIT_SIZE-131072}
    IO_PACER_DISK_CREDIT=${IO_PACER_DISK_CREDIT-0}
    IN_CAPSULE_DATA=${IN_CAPSULE_DATA-0}

    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size $IN_CAPSULE_DATA \
	     --max-io-size 131072 \
	     --io-unit-size $IO_UNIT_SIZE \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-credit $IO_PACER_CREDIT \
	     --io-pacer-threshold $IO_PACER_THRESHOLD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP \
	     --io-pacer-tuner-threshold $IO_PACER_TUNER_THRESHOLD \
	     --io-pacer-tuner-factor $IO_PACER_TUNER_FACTOR \
	     --io-pacer-disk-credit $IO_PACER_DISK_CREDIT
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    rpc_send bdev_null_create Null0 8192 4096
    rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Null0
    rpc_stop
    sleep 1
}

function config_null_16()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-32}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_CREDIT=${IO_PACER_CREDIT-131072}
    IO_PACER_THRESHOLD=${IO_PACER_THRESHOLD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    IO_PACER_TUNER_THRESHOLD=${IO_PACER_TUNER_THRESHOLD-12582912}
    IO_PACER_TUNER_FACTOR=${IO_PACER_TUNER_FACTOR-1}
    IO_UNIT_SIZE=${IO_UNIT_SIZE-131072}
    IO_PACER_DISK_CREDIT=${IO_PACER_DISK_CREDIT-0}
    IN_CAPSULE_DATA=${IN_CAPSULE_DATA-0}

    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size $IN_CAPSULE_DATA \
	     --max-io-size 131072 \
	     --io-unit-size $IO_UNIT_SIZE \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-credit $IO_PACER_CREDIT \
	     --io-pacer-threshold $IO_PACER_THRESHOLD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP \
	     --io-pacer-tuner-threshold $IO_PACER_TUNER_THRESHOLD \
	     --io-pacer-tuner-factor $IO_PACER_TUNER_FACTOR \
	     --io-pacer-disk-credit $IO_PACER_DISK_CREDIT
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    for i in $(seq 16); do
	rpc_send bdev_null_create Null$i 8192 4096
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Null$i
    done
    rpc_stop
    sleep 1
}

function config_nvme()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-128}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_CREDIT=${IO_PACER_CREDIT-131072}
    IO_PACER_THRESHOLD=${IO_PACER_THRESHOLD-0}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    IO_PACER_TUNER_THRESHOLD=${IO_PACER_TUNER_THRESHOLD-12582912}
    IO_PACER_TUNER_FACTOR=${IO_PACER_TUNER_FACTOR-1}
    IO_UNIT_SIZE=${IO_UNIT_SIZE-131072}
    IO_PACER_DISK_CREDIT=${IO_PACER_DISK_CREDIT-0}
    IN_CAPSULE_DATA=${IN_CAPSULE_DATA-0}
    local DISKS="05 06 07 08 09 0a 0b 0c 0f 10 11 12 13 14 15 16"

    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size $IN_CAPSULE_DATA \
	     --max-io-size 131072 \
	     --io-unit-size $IO_UNIT_SIZE \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-credit $IO_PACER_CREDIT \
	     --io-pacer-threshold $IO_PACER_THRESHOLD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP \
	     --io-pacer-tuner-threshold $IO_PACER_TUNER_THRESHOLD \
	     --io-pacer-tuner-factor $IO_PACER_TUNER_FACTOR \
	     --io-pacer-disk-credit $IO_PACER_DISK_CREDIT
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    local i=0
    for pci in $DISKS; do
	rpc_send bdev_nvme_attach_controller --name Nvme$i \
		 --trtype pcie \
		 --traddr 0000:$pci:00.0
	rpc_send nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Nvme${i}n1
	((i+=1))
    done
    rpc_stop
    sleep 1
}

function config_nvme_split3_delay()
{
    NUM_SHARED_BUFFERS=${NUM_SHARED_BUFFERS-4095}
    BUF_CACHE_SIZE=${BUF_CACHE_SIZE-128}
    NUM_DELAY_BDEVS=${NUM_DELAY_BDEVS-0}
    IO_PACER_PERIOD=${IO_PACER_PERIOD-0}
    IO_PACER_THRESHOLD=${IO_PACER_THRESHOLD-0}
    IO_PACER_CREDIT=${IO_PACER_CREDIT-131072}
    IO_PACER_TUNER_PERIOD=${IO_PACER_TUNER_PERIOD-10000}
    IO_PACER_TUNER_STEP=${IO_PACER_TUNER_STEP-1000}
    IO_PACER_TUNER_THRESHOLD=${IO_PACER_TUNER_THRESHOLD-12582912}
    IO_PACER_TUNER_FACTOR=${IO_PACER_TUNER_FACTOR-1}
    IO_UNIT_SIZE=${IO_UNIT_SIZE-131072}
    IO_PACER_DISK_CREDIT=${IO_PACER_DISK_CREDIT-0}
    IN_CAPSULE_DATA=${IN_CAPSULE_DATA-0}
    local DISKS="05 06 07 08 09 0a 0b 0c 0f 10 11 12 13 14 15 16"

    rpc_start
    rpc_send nvmf_set_config --conn-sched transport
    rpc_send framework_start_init
    sleep 3
    rpc_send nvmf_create_transport --trtype RDMA \
	     --max-queue-depth 128 \
	     --max-qpairs-per-ctrlr 64 \
	     --in-capsule-data-size $IN_CAPSULE_DATA \
	     --max-io-size 131072 \
	     --io-unit-size $IO_UNIT_SIZE \
	     --num-shared-buffers $NUM_SHARED_BUFFERS \
	     --buf-cache-size $BUF_CACHE_SIZE \
	     --max-srq-depth 4096 \
	     --io-pacer-period $IO_PACER_PERIOD \
	     --io-pacer-credit $IO_PACER_CREDIT \
	     --io-pacer-threshold $IO_PACER_THRESHOLD \
	     --io-pacer-tuner-period $IO_PACER_TUNER_PERIOD \
	     --io-pacer-tuner-step $IO_PACER_TUNER_STEP \
	     --io-pacer-tuner-threshold $IO_PACER_TUNER_THRESHOLD \
	     --io-pacer-tuner-factor $IO_PACER_TUNER_FACTOR \
	     --io-pacer-disk-credit $IO_PACER_DISK_CREDIT
    rpc_send nvmf_create_subsystem --allow-any-host \
	     --max-namespaces 48 \
	     nqn.2016-06.io.spdk:cnode1

    for addr in $TARGET_ADDRS; do
	rpc_send nvmf_subsystem_add_listener --trtype rdma \
		 --traddr "$addr" \
		 --adrfam ipv4 \
		 --trsvcid 4420 \
		 nqn.2016-06.io.spdk:cnode1
    done

    local i=0
    for pci in $DISKS; do
	rpc_send bdev_nvme_attach_controller --name Nvme$i \
		 --trtype pcie \
		 --traddr 0000:$pci:00.0
	rpc_send bdev_split_create Nvme${i}n1 3
	((i+=1))
    done
    local num_disks=$i
    i=0
    for part in 0 1 2; do
	for disk in $(seq 0 $((num_disks-1))); do
	    local ns_id=$((disk*3 + part + 1))
	    if [ "$i" -lt "$NUM_DELAY_BDEVS" ]; then
		rpc_send bdev_delay_create --base-bdev-name Nvme${disk}n1p${part} \
			 --name Nvme${disk}n1p${part}d \
			 --avg-read-latency 1000 \
			 --nine-nine-read-latency 1000 \
			 --avg-write-latency 1000 \
			 --nine-nine-write-latency 1000
		rpc_send nvmf_subsystem_add_ns -n $ns_id nqn.2016-06.io.spdk:cnode1 Nvme${disk}n1p${part}d
	    else
		rpc_send nvmf_subsystem_add_ns -n $ns_id nqn.2016-06.io.spdk:cnode1 Nvme${disk}n1p${part}
	    fi
	    ((i+=1))
	done
    done
    rpc_stop
    sleep 1
}

function test_base()
{
    start_tgt $TGT_CPU_MASK
    $CONFIG
    basic_test
    stop_tgt
}

function test_base_kernel()
{
    start_tgt $TGT_CPU_MASK
    $CONFIG
    connect_hosts $HOSTS
    basic_test
    disconnect_hosts $HOSTS
    stop_tgt
}

function test_1()
{
    CONFIG=config_null_1 \
	  TGT_CPU_MASK=0xF \
	  FIO_JOB=fio-1ns \
	  QD_LIST="32 64 128 1024 2048" \
	  test_base
}

function test_2()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xF \
	  FIO_JOB=fio-16ns \
	  QD_LIST="32 64 128 1024 2048" \
	  test_base
}

function test_2_4k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  BUF_CACHE_SIZE=128 \
	  QD_LIST="32" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  test_base
}

function test_2_8k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  BUF_CACHE_SIZE=128 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_2_16k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  BUF_CACHE_SIZE=128 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_3()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xF \
	  FIO_JOB=fio-16ns \
	  QD_LIST="32 36 40 44 48 64 128 256 1024 2048" \
	  test_base
}

function test_3_4k()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  BUF_CACHE_SIZE=128 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  test_base
}

function test_3_8k()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  BUF_CACHE_SIZE=128 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_3_16k()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  BUF_CACHE_SIZE=128 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_4()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xF \
	  FIO_JOB=fio-16ns \
	  NUM_SHARED_BUFFERS=96 \
	  BUF_CACHE_SIZE=24 \
	  QD_LIST="32 64 128 1024 2048" \
	  test_base
}

function test_4_4k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=1536 \
	  BUF_CACHE_SIZE=96 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  test_base
}

function test_4_8k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=1024 \
	  BUF_CACHE_SIZE=64 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_4_16k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=1024 \
	  BUF_CACHE_SIZE=64 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_5()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xF \
	  FIO_JOB=fio-16ns \
	  NUM_SHARED_BUFFERS=96 \
	  BUF_CACHE_SIZE=24 \
	  QD_LIST="32 64 128 1024 2048" \
	  test_base
}

function test_5_4k()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=1536 \
	  BUF_CACHE_SIZE=96 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  test_base
}

function test_5_8k()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=1024 \
	  BUF_CACHE_SIZE=64 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_5_16k()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=1024 \
	  BUF_CACHE_SIZE=64 \
	  QD_LIST="32 64 128 256 512" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  test_base
}

function test_6()
{
    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xF \
	  FIO_JOB=fio-16ns \
	  NUM_SHARED_BUFFERS=96 \
	  BUF_CACHE_SIZE=24 \
	  QD_LIST="32 256 1024 2048" \
	  REPEAT=10 \
	  test_base
}

function test_7()
{
    for cpu_mask in FFFF FF F 3 1; do
	local bin_mask=$(m "ibase=16; obase=2; $cpu_mask")
	bin_mask=${bin_mask//0/}
	local core_count=${#bin_mask}
	local num_buffers=96
	local cache_size=$((num_buffers/core_count))
	echo "Target cores $core_count (0x$cpu_mask). Buffer cache size $cache_size"

	CONFIG=config_nvme \
	      TGT_CPU_MASK="0x$cpu_mask" \
	      FIO_JOB=fio-16ns \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$cache_size \
	      QD_LIST="2048" \
	      test_base
	sleep 3
    done
}

function test_7_4k()
{
    for cpu_mask in FFFF FF F 3 1; do
	local bin_mask=$(m "ibase=16; obase=2; $cpu_mask")
	bin_mask=${bin_mask//0/}
	local core_count=${#bin_mask}
	local num_buffers=1536
	local cache_size=$((num_buffers/core_count))
	echo "Target cores $core_count (0x$cpu_mask). Buffer cache size $cache_size"

	CONFIG=config_nvme \
	      TGT_CPU_MASK="0x$cpu_mask" \
	      FIO_JOB=fio-16ns-16jobs \
	      IO_UNIT_SIZE=8192 \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$cache_size \
	      QD_LIST="512" \
	      IO_SIZE=4k \
	      BUFFER_SIZE=4096 \
	      test_base
	sleep 3
    done
}

function test_7_8k()
{
    for cpu_mask in FFFF FF F 3 1; do
	local bin_mask=$(m "ibase=16; obase=2; $cpu_mask")
	bin_mask=${bin_mask//0/}
	local core_count=${#bin_mask}
	local num_buffers=1024
	local cache_size=$((num_buffers/core_count))
	echo "Target cores $core_count (0x$cpu_mask). Buffer cache size $cache_size"

	CONFIG=config_nvme \
	      TGT_CPU_MASK="0x$cpu_mask" \
	      FIO_JOB=fio-16ns-16jobs \
	      IO_UNIT_SIZE=8192 \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$cache_size \
	      QD_LIST="512" \
	      IO_SIZE=8k \
	      BUFFER_SIZE=8192 \
	      test_base
	sleep 3
    done
}

function test_7_16k()
{
    for cpu_mask in FFFF FF F 3 1; do
	local bin_mask=$(m "ibase=16; obase=2; $cpu_mask")
	bin_mask=${bin_mask//0/}
	local core_count=${#bin_mask}
	local num_buffers=1024
	local cache_size=$((num_buffers/core_count))
	echo "Target cores $core_count (0x$cpu_mask). Buffer cache size $cache_size"

	CONFIG=config_nvme \
	      TGT_CPU_MASK="0x$cpu_mask" \
	      FIO_JOB=fio-16ns-16jobs \
	      IO_UNIT_SIZE=8192 \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$cache_size \
	      QD_LIST="512" \
	      IO_SIZE=16k \
	      BUFFER_SIZE=8192 \
	      test_base
	sleep 3
    done
}

function test_8()
{
    for cache_size in 6 3 1 0; do
	echo "Buffer cache size $cache_size"
	start_tgt 0xFFFF
	NUM_SHARED_BUFFERS=96 BUF_CACHE_SIZE=$cache_size config_nvme
	FIO_JOB=fio-16ns basic_test
	stop_tgt
	sleep 3
    done
}

function test_9()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for num_buffers in 128 96 64 48 44 40 36 32 24 16; do
	local cache_size=$((num_buffers/NUM_CORES))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"

	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$cache_size \
	      QD_LIST="2048" \
	      test_base
	sleep 3
    done
}

function test_9_4k()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for num_buffers in 4096 3072 2560 2048 1536 1024 512 256; do
	local cache_size=$((num_buffers/NUM_CORES))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"

	CONFIG=config_nvme \
	  TGT_CPU_MASK=$TGT_CPU_MASK \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=$num_buffers \
	  BUF_CACHE_SIZE=$cache_size \
	  QD_LIST="512" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  test_base
	sleep 3
    done
}


function test_9_8k()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for num_buffers in 2048 1536 1280 1024 768 512 256 128; do
	local cache_size=$((num_buffers/NUM_CORES))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"

	CONFIG=config_nvme \
	  TGT_CPU_MASK=$TGT_CPU_MASK \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=$num_buffers \
	  BUF_CACHE_SIZE=$cache_size \
	  QD_LIST="512" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  test_base
	sleep 3
    done
}

function test_9_16k()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for num_buffers in 2048 1536 1280 1024 768 512 256 128; do
	local cache_size=$((num_buffers/NUM_CORES))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"

	CONFIG=config_nvme \
	  TGT_CPU_MASK=$TGT_CPU_MASK \
	  FIO_JOB=fio-16ns-16jobs \
	  IO_UNIT_SIZE=8192 \
	  NUM_SHARED_BUFFERS=$num_buffers \
	  BUF_CACHE_SIZE=$cache_size \
	  QD_LIST="512" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  test_base
	sleep 3
    done
}

function test_10()
{
    local TGT_CPU_MASK=0xF
    local NUM_CORES=4

    for num_buffers in 128 96 64 48 44 40 36 32 24 16; do
	local cache_size=$((num_buffers/NUM_CORES))
	echo "Num shared buffers $num_buffers. Buffer cache size $cache_size"

	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$cache_size \
	      QD_LIST="256 2048" \
	      test_base
	sleep 3
    done
}

function test_11()
{
    local TGT_CPU_MASK=0xF
    local NUM_CORES=4

    for num_buffers in 96 48; do
	for num_delay in 0 16 32; do
	    local cache_size=$((num_buffers/NUM_CORES))
	    echo "| $TGT_CPU_MASK | $num_buffers | $num_delay"
	    CONFIG=config_nvme_split3_delay \
		  TGT_CPU_MASK=$TGT_CPU_MASK \
		  FIO_JOB=fio-48ns \
		  NUM_SHARED_BUFFERS=$num_buffers \
		  BUF_CACHE_SIZE=$cache_size \
		  NUM_DELAY_BDEVS=$num_delay \
		  QD_LIST="85 341" \
		  test_base
	    sleep 3
	done
    done
}

# Uncomment line "iodepth=1024" in job3 in fio-48ns job files to run this test
function test_12()
{
    local TGT_CPU_MASK=0xF
    local NUM_CORES=4

    for num_buffers in 48; do
	for num_delay in 16 32; do
	    local cache_size=$((num_buffers/NUM_CORES))
	    echo "| $TGT_CPU_MASK | $num_buffers | $num_delay"
	    CONFIG=config_nvme_split3_delay \
		  TGT_CPU_MASK=$TGT_CPU_MASK \
		  FIO_JOB=fio-48ns \
		  NUM_SHARED_BUFFERS=$num_buffers \
		  BUF_CACHE_SIZE=$cache_size \
		  NUM_DELAY_BDEVS=$num_delay \
		  QD_LIST="1 2 4 8 16 32 64" \
		  test_base
	    sleep 3
	done
    done
}

# Test latencies
function test_13()
{
    local TGT_CPU_MASK=0xF
    local NUM_CORES=4
    HOSTS="spdk03.swx.labs.mlnx"

    CONFIG=config_null_16 \
	  TGT_CPU_MASK=$TGT_CPU_MASK \
	  FIO_JOB=fio-16ns \
	  QD_LIST="1" \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    CONFIG=config_nvme \
	  TGT_CPU_MASK=$TGT_CPU_MASK \
	  FIO_JOB=fio-16ns \
	  QD_LIST="1" \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    for num_delay in 0 48; do
	CONFIG=config_nvme_split3_delay \
	      NUM_DELAY_BDEVS=$num_delay \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns \
	      QD_LIST="1" \
	      HOSTS="spdk03.swx.labs.mlnx" \
	      test_base
    done
}

function test_13_4k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns \
	  IO_UNIT_SIZE=8192 \
	  QD_LIST="1" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns \
	  IO_UNIT_SIZE=8192 \
	  QD_LIST="1" \
	  IO_SIZE=4k \
	  BUFFER_SIZE=4096 \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    for num_delay in 0 48; do
	CONFIG=config_nvme_split3_delay \
	      NUM_DELAY_BDEVS=$num_delay \
	      TGT_CPU_MASK=0xFFFF \
	      FIO_JOB=fio-16ns \
	      IO_UNIT_SIZE=8192 \
	      QD_LIST="1" \
	      IO_SIZE=4k \
	      BUFFER_SIZE=4096 \
	      HOSTS="spdk03.swx.labs.mlnx" \
	      test_base
    done
}

function test_13_8k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns \
	  IO_UNIT_SIZE=8192 \
	  QD_LIST="1" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns \
	  IO_UNIT_SIZE=8192 \
	  QD_LIST="1" \
	  IO_SIZE=8k \
	  BUFFER_SIZE=8192 \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    for num_delay in 0 48; do
	CONFIG=config_nvme_split3_delay \
	      NUM_DELAY_BDEVS=$num_delay \
	      TGT_CPU_MASK=0xFFFF \
	      FIO_JOB=fio-16ns \
	      IO_UNIT_SIZE=8192 \
	      QD_LIST="1" \
	      IO_SIZE=8k \
	      BUFFER_SIZE=8192 \
	      HOSTS="spdk03.swx.labs.mlnx" \
	      test_base
    done
}

function test_13_16k()
{
    CONFIG=config_null_16 \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns \
	  IO_UNIT_SIZE=8192 \
	  QD_LIST="1" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    CONFIG=config_nvme \
	  TGT_CPU_MASK=0xFFFF \
	  FIO_JOB=fio-16ns \
	  IO_UNIT_SIZE=8192 \
	  QD_LIST="1" \
	  IO_SIZE=16k \
	  BUFFER_SIZE=8192 \
	  HOSTS="spdk03.swx.labs.mlnx" \
	  test_base

    for num_delay in 0 48; do
	CONFIG=config_nvme_split3_delay \
	      NUM_DELAY_BDEVS=$num_delay \
	      TGT_CPU_MASK=0xFFFF \
	      FIO_JOB=fio-16ns \
	      IO_UNIT_SIZE=8192 \
	      QD_LIST="1" \
	      IO_SIZE=16k \
	      BUFFER_SIZE=8192 \
	      HOSTS="spdk03.swx.labs.mlnx" \
	      test_base
    done
}

function test_14()
{
    local TGT_CPU_MASK=0xF0
    local NUM_CORES=4

    for io_pacer in 5600 5650 5700 5750 5800 6000; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD"
	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns \
	      QD_LIST="256 2048" \
	      IO_SIZE=128k \
	      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
	      test_base
	sleep 3
    done
}

function test_14_16_cores()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for io_pacer in 2800 2875 3000; do
#    for io_pacer in 2875; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	num_buffers=131072
	buf_cache=$((num_buffers/NUM_CORES))
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, num buffers $num_buffers, buf cache $buf_cache"

	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns-16jobs \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$buf_cache \
	      IO_UNIT_SIZE=8192 \
	      BUFFER_SIZE=8192 \
	      QD_LIST="256" \
	      IO_SIZE=128k \
	      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
	      IO_PACER_CREDIT=65536 \
	      test_base
	sleep 3
    done
}

function test_14_4k()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for io_pacer in 2875; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	num_buffers=131072
	buf_cache=$((num_buffers/NUM_CORES))
	echo "CPU mask $TGT_CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, num buffers $num_buffers, buf cache $buf_cache"
	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns-16jobs \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$buf_cache \
	      IO_UNIT_SIZE=8192 \
	      QD_LIST="256 2048" \
	      IO_SIZE=4k \
	      BUFFER_SIZE=4096 \
	      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
	      IO_PACER_CREDIT=65536 \
	      IO_PACER_TUNER_PERIOD=0 \
	      test_base
	sleep 3
    done
}

function test_14_8k()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for io_pacer in 2875; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	num_buffers=131072
	buf_cache=$((num_buffers/NUM_CORES))
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, num buffers $num_buffers, buf cache $buf_cache"
	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns-16jobs \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$buf_cache \
	      IO_UNIT_SIZE=8192 \
	      QD_LIST="256 2048" \
	      IO_SIZE=8k \
	      BUFFER_SIZE=8192 \
	      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
	      IO_PACER_CREDIT=65536 \
	      test_base
	sleep 3
    done
}
function test_14_16k()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for io_pacer in 1425 1500; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	num_buffers=131072
	buf_cache=$((num_buffers/NUM_CORES))
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, num buffers $num_buffers, buf cache $buf_cache"
	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns-16jobs \
	      NUM_SHARED_BUFFERS=$num_buffers \
	      BUF_CACHE_SIZE=$buf_cache \
	      IO_UNIT_SIZE=8192 \
	      QD_LIST="128 1024" \
	      IO_SIZE=16k \
	      BUFFER_SIZE=8192 \
	      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
	      IO_PACER_CREDIT=32768 \
	      test_base
	sleep 3
    done
}

function test_15()
{
    local TGT_CPU_MASK=0xF0
    local NUM_CORES=4

    for io_pacer in 5600 5650 5700 5750 5800 6000; do
	ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
	echo "CPU mask $CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD"
	CONFIG=config_nvme \
	      TGT_CPU_MASK=$TGT_CPU_MASK \
	      FIO_JOB=fio-16ns \
	      QD_LIST="256 2048" \
	      IO_SIZE=128k \
	      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
	      IO_PACER_TUNER_PERIOD=0 \
	      test_base
	sleep 3
    done
}

function test_16()
{
    local TGT_CPU_MASK=0xF0
    local NUM_CORES=4

    for io_pacer in 5750; do
	for disk_credit in 0 2 6; do
	    for num_delay in 0 16 32; do
		ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
		echo "CPU mask $TGT_CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, num delay $num_delay, disk credit $disk_credit"

		CONFIG=config_nvme_split3_delay \
		      NUM_DELAY_BDEVS=$num_delay \
		      TGT_CPU_MASK=$TGT_CPU_MASK \
		      FIO_JOB=fio-48ns \
		      QD_LIST="1 2 4 8 16 32 64" \
		      IO_SIZE=128k \
		      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
		      IO_PACER_DISK_CREDIT=$disk_credit \
		      test_base
		sleep 3
	    done
	done
    done
}

function test_17()
{
    local TGT_CPU_MASK=0xF0
    local NUM_CORES=4

    for io_pacer in 5750; do
	for disk_credit in 0 2 6; do
	    for num_delay in 0 16 32; do
		ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
		echo "CPU mask $TGT_CPU_MASK, num cores $NUM_CORES, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, num delay bdevs $num_delay, disk credit $disk_credit"

		CONFIG=config_nvme_split3_delay \
		      NUM_DELAY_BDEVS=$num_delay \
		      TGT_CPU_MASK=$TGT_CPU_MASK \
		      FIO_JOB=fio-48ns \
		      QD_LIST="1 2 4 8 16 32 64" \
		      IO_SIZE=128k \
		      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
		      IO_PACER_DISK_CREDIT=$disk_credit \
		      test_base
		sleep 3
	    done
	done
    done
}

function test_18()
{
    local TGT_CPU_MASK=0xFFFF
    local NUM_CORES=16

    for io_pacer in 0 2875; do
	for threshold in 0 16384; do
	    if [ "0" -eq "$io_pacer" -a "0" -ne "$threshold" ]; then
		continue
	    fi

#	    for io_size in "128k" "4k" "128k/80:4k/20" "128k/20:4k/80" "8k" "128k/80:8k/20" "128k/20:8k/80" "16k" "128k/80:16k/20" "128k/20:16k/80"; do
	    for io_size in "128k" "4k" "128k/80:4k/20" "128k/20:4k/80" "128k/3:4k/97"; do
#	    for io_size in "8k" "128k/80:8k/20" "128k/20:8k/80" "128k/3:8k/97"; do
#	    for io_size in "128k/80:4k/20"; do
		local factor=3
		ADJUSTED_PERIOD="$(M_SCALE=0 m $io_pacer*$NUM_CORES/1)"
		num_buffers=131072
		buf_cache=$((num_buffers/NUM_CORES))
		echo "CPU mask $TGT_CPU_MASK, IO pacer period $io_pacer, adjusted period $ADJUSTED_PERIOD, IO size $io_size, pacer threshold $threshold, num buffers $num_buffers, buf cache $buf_cache"
		CONFIG=config_nvme \
		      TGT_CPU_MASK=$TGT_CPU_MASK \
		      FIO_JOB=fio-16ns-16jobs \
		      NUM_SHARED_BUFFERS=$num_buffers \
		      BUF_CACHE_SIZE=$buf_cache \
		      IO_UNIT_SIZE=8192 \
		      QD_LIST="16 32 256" \
		      IO_SIZE="$io_size" \
		      BUFFER_SIZE=8192 \
		      IO_PACER_PERIOD=$ADJUSTED_PERIOD \
		      IO_PACER_CREDIT=65536 \
		      IO_PACER_THRESHOLD=$threshold \
		      IO_PACER_TUNER_FACTOR=$factor \
		      IN_CAPSULE_DATA=4096 \
		      test_base
		sleep 3
	    done
	done
    done
}

function test_tgt()
{
    local CPU_MASK=0xF0
    local NUM_CORES=4
    local IO_PACER="6000"

    start_tgt $CPU_MASK
    IO_PACER_PERIOD="$(M_SCALE=0 m $IO_PACER \* $NUM_CORES / 1)" config_nvme
    echo "Running"
    progress_bar $TEST_TIME
    echo "Stopping"
    stop_tgt
}

function test_fio()
{
    QD=2048 FIO_NO_JSON=1 FIO_JOB=fio-16ns run_fio $HOSTNAME
}

if [ -z "$1" ]; then
    declare -F | grep ' -f test' | cut -d " " -f 3
    exit 0
fi

for test in $@; do
    echo "$test"
    $test
done
