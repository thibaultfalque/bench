#!/bin/bash -l
#SBATCH --time=00:01:00
#SBATCH --nodes=4
#SBATCH --partition=batch
#SBATCH --ntasks-per-node=32 # when benchmarking sequential solver, we still book the whole node to avoid possible interference.
#SBATCH --exclusive
#SBATCH --mem=0
#SBATCH --export=ALL
#SBATCH --output=slurm-mzn.out

# Exits when an error occurs.
set -e
set -x # useful for debugging.

# Shortcuts of paths to benchmarking directories.
WORKFLOW_PATH=$(dirname $(realpath "run.sh"))
BENCHMARKING_DIR_PATH="$WORKFLOW_PATH/.."
BENCHMARKS_DIR_PATH="$WORKFLOW_PATH/../.."

# Configure the environment.
if [ -z "$1" ]; then
  echo "Usage: $0 <machine.sh>"
  echo "  Name of the machine running the experiments with the configuration of the environment."
  exit 1
fi
source $1
source ${BENCHMARKS_DIR_PATH}/../venv/bin/activate

# If it has an argument, we retry the jobs that failed on a previous run.
# If the experiments were not complete, you can simply rerun the script, parallel will ignore the jobs that are already done.
if [ -n "$2" ]; then
  parallel --retry-failed --joblog $2
  exit 0
fi

# I. Define the campaign to run.

SOLVER="lala-octagon-pc"
SOLVER_EXECUTABLE=/home/falque/Travail/PostDoc-SnT/Softwares/lala-land-octagon-pc/lala-octagaon-vs-pc/build/cpu-release-local/lalaoctagonpc
VERSION="v1.0.0" # Note that this is only for the naming of the output directory, we do not verify the actual version of the solver.
# This is to avoid MiniZinc to kill Turbo before it can print the statistics.
REAL_TIMEOUT=60
CORES=1 # The number of core used on the node.
MACHINE=$(basename "$1" ".sh")
INSTANCES_PATH="$BENCHMARKS_DIR_PATH/benchmarking/all.csv"

# II. Prepare the command lines and output directory.
OUTPUT_DIR="$BENCHMARKS_DIR_PATH/campaign/$MACHINE/$SOLVER-$VERSION"
mkdir -p $OUTPUT_DIR

COMMAND="/home/falque/.softwares/runsolver -C $REAL_TIMEOUT -W $REAL_TIMEOUT -M 4000 -d 5"


# If we are on the HPC, we encapsulate the command in a srun command to reserve the resources needed.
if [ -n "${SLURM_JOB_NODELIST}" ]; then
  SRUN_COMMAND="srun -A project_comoc --exclusive --cpus-per-task=$CORES --nodes=1 --cpu-bind=verbose"
  NUM_PARALLEL_EXPERIMENTS=$((SLURM_JOB_NUM_NODES * 32)) # How many experiments are we running in parallel? One per GPU per default.
else
  NUM_PARALLEL_EXPERIMENTS=1
fi

DUMP_PY_PATH="$WORKFLOW_PATH/dump.py"

# For replicability.
cp -r $WORKFLOW_PATH $OUTPUT_DIR/
cp $INSTANCES_PATH $OUTPUT_DIR/$(basename "$WORKFLOW_PATH")/

# Store the description of the hardware on which this campaign is run.
lshw -json > $OUTPUT_DIR/$(basename "$WORKFLOW_PATH")/hardware-"$MACHINE".json 2> /dev/null

# III. Run the experiments in parallel.
# The `parallel` command spawns one `srun` command per experiment, which executes the minizinc solver with the right resources.

COMMANDS_LOG="$OUTPUT_DIR/$(basename "$WORKFLOW_PATH")/jobs.log"
parallel --verbose --no-run-if-empty --rpl '{} uq()' -k --colsep ',' --skip-first-line -j $NUM_PARALLEL_EXPERIMENTS --resume --joblog $COMMANDS_LOG $SRUN_COMMAND $COMMAND -o $OUTPUT_DIR/runsolver_execution_$SOLVER_{2}_{4}.out" -v "$OUTPUT_DIR/runsolver_statistics_$SOLVER_{2}_{4}.out $SOLVER_EXECUTABLE $BENCHMARKING_DIR_PATH/{3} {4} '2>&1' '|' python3 $DUMP_PY_PATH $OUTPUT_DIR {1} {2} {3} $SOLVER {4} :::: $INSTANCES_PATH ::: "octagon" "pc"
