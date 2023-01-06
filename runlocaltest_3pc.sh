# --------------------------------------------------------------------------------
# SYNOPSIS
# --------------------------------------------------------------------------------

RUNDIR=`pwd`/run.`date +'%Y%m%d.%H:%M:%S'`
LOGDIR=$RUNDIR/mylogs
BUILDDIR=/Users/abj/mitdci.arm/opencbdc-tx/build

mkdir $RUNDIR
mkdir $LOGDIR

# --------------------------------------------------------------------------------
cd $RUNDIR

# --------------------------------------------------------------------------------
RUN () {
    CMD=$1
    SLEEP_SECS=$2
    PRINT_ONLY=$3

    echo "----------"
    echo "Run Dir: `pwd`"
    if [[ -z "$PRINT_ONLY" ]]; then
        echo "Running: $CMD"
        eval $CMD
        echo "Waiting $SLEEP_SECS secs ..."
        sleep $SLEEP_SECS
    else
        echo "Skipping: $CMD"        
    fi
}

CONFIG_ARGS=\
"--shard_count=1 \
 --shard0_count=1 \
 --shard00_endpoint=localhost:5556 \
 --node_id=0 \
 --component_id=0 \
 --agent_count=1 \
 --agent0_endpoint=localhost:6666 \
 --ticket_machine_count=1 \
 --ticket_machine0_endpoint=localhost:7777"

RUN "$BUILDDIR/src/3pc/runtime_locking_shard/runtime_locking_shardd $CONFIG_ARGS \
 --loglevel=WARN \
 > $LOGDIR/shardd.out 2>&1 &" 3

RUN "$BUILDDIR/src/3pc/ticket_machine/ticket_machined $CONFIG_ARGS \
 --loglevel=WARN \
 > $LOGDIR/ticketm.out 2>&1 &" 3

RUN "$BUILDDIR/src/3pc/agent/agentd $CONFIG_ARGS \
 --loglevel=WARN \
 > $LOGDIR/agentd.out 2>&1 &" 3

RUN "$BUILDDIR/tools/bench/3pc/evm/evm_bench $CONFIG_ARGS \
 --loadgen_accounts=128 \
 --loadgen_txtype=erc20 \
 --telemetry=1 \
 > $LOGDIR/evm_bench.out 2>&1 &" 0 1

RUN "ps -aefww | grep -v grep | grep shard0" 0

# kill `ps -aefww | grep -v grep | grep shard0 | awk {'print $2'}`
