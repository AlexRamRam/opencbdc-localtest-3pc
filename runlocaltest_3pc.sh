# --------------------------------------------------------------------------------
# USER TEST SETUP
DO_SKIP_AGENT=0
DO_SKIP_LOADGEN=1
LOADGEN_RUN_DURATION=3
LOGLEVEL=INFO

# --------------------------------------------------------------------------------

RUNDIR=`pwd`/run.`date +'%Y%m%d.%H:%M:%S'`
REPODIR=$HOME/mitdci/repos
BUILDDIR=$REPODIR/opencbdc-tx/build

mkdir $RUNDIR
# --------------------------------------------------------------------------------
# A consistent link point for current run:
rm -f run.current
ln -s $RUNDIR run.current

# LOGDIR=$RUNDIR/mylogs
LOGDIR=`pwd`/run.current/mylogs
mkdir $LOGDIR

# --------------------------------------------------------------------------------
echo "----------"
echo "Test Specs:"
echo "    DO_SKIP_AGENT=$DO_SKIP_AGENT"
echo "    DO_SKIP_LOADGEN=$DO_SKIP_LOADGEN"
echo "    LOADGEN_RUN_DURATION=$LOADGEN_RUN_DURATION"
echo ""
echo "Build dir: $BUILDDIR"
echo "Run dir (run.current): $RUNDIR"
echo "Log dir: $LOGDIR"
# --------------------------------------------------------------------------------
cd run.current
# --------------------------------------------------------------------------------

RUN () {
    CMD=$1
    SLEEP_SECS=$2
    PRINT_ONLY=$3

    echo "----------"
    if [[ -z "$PRINT_ONLY" || "$PRINT_ONLY" = "0" ]]; then
        echo `date`
        echo "Running: $CMD"
        eval $CMD
        echo "Waiting $SLEEP_SECS secs ..."
        sleep $SLEEP_SECS
    else
        echo "SKIPPING: $CMD"        
    fi
}

KILL_ALL () {
    PCOUNT=`ps -aefww | grep -v grep | grep shard0 | awk {'print $2'} | wc -l`
    if (( $PCOUNT == 0 )); then
        echo "OK: No server processes running."
    else
        echo "`date`: Stopping $PCOUNT server processes ..."
        kill `ps -aefww | grep -v grep | grep shard0 | awk {'print $2'}`
        sleep 1

        PCOUNT=`ps -aefww | grep -v grep | grep shard0 | awk {'print $2'} | wc -l`
        if (( $PCOUNT == 0 )); then
            echo "OK: Killed all processes."
        else
            echo "ERROR: Could not kill server processes"
        fi
    fi
    
    echo "Checking for any remaining processes ..."
    RUN "ps -aefww | grep -v grep | grep shard0" 0        
}

CONFIG_ARGS=\
"--shard_count=1 \
 --shard0_count=1 \
 --shard00_endpoint=localhost:5556 \
 --node_id=0 \
 --component_id=0 \
 --agent_count=1 \
 --agent0_endpoint=localhost:8080 \
 --ticket_machine_count=1 \
 --ticket_machine0_endpoint=localhost:7777 \
 --loglevel=$LOGLEVEL"

KILL_ALL

SLEEP_AFTER=3
RUN "$BUILDDIR/src/parsec/runtime_locking_shard/runtime_locking_shardd $CONFIG_ARGS > $LOGDIR/shardd.out 2>&1 &" \
    $SLEEP_AFTER

RUN "$BUILDDIR/src/parsec/ticket_machine/ticket_machined $CONFIG_ARGS > $LOGDIR/ticketm.out 2>&1 &" \
    $SLEEP_AFTER

RUN "$BUILDDIR/src/parsec/agent/agentd $CONFIG_ARGS > $LOGDIR/agentd.out 2>&1 &" \
    $SLEEP_AFTER $DO_SKIP_AGENT

SLEEP_AFTER=0
RUN "$BUILDDIR/tools/bench/parsec/evm/evm_bench $CONFIG_ARGS \
 --loadgen_accounts=16 \
 --loadgen_txtype=erc20 \
 --telemetry=1 \
 > $LOGDIR/evm_bench.out 2>&1 &" \
    $SLEEP_AFTER $DO_SKIP_LOADGEN

RUN "ps -aefww | grep -v grep | grep shard0" 0

# --------------------------------------------------------------------------------
# Make it easy to clean up processes:
echo "----------"
if [[ "$DO_SKIP_LOADGEN" = "0" ]]; then
    echo "`date`: Running test for $LOADGEN_RUN_DURATION seconds ..."
    sleep $LOADGEN_RUN_DURATION
    KILL_ALL
else
    echo "Processes are running. Enter 'q' to kill all processes and quit."
    read USERINPUT
    if [[ $USERINPUT = "q" ]]
    then
        KILL_ALL
    else
        echo "Quitting this shell, underlying processes are still running (see above)"
    fi
fi

# --------------------------------------------------------------------------------
echo "----------"
# sed is to fix corrupt lines: put newline where there should be one
cat $LOGDIR/*.out | sed -E 's/(.)(\[202)/\1\n\2/g' | sort > $LOGDIR/combined.out
echo "Made $LOGDIR/combined.out"

echo "ALL DONE"
