# -*- coding: utf-8 -*-


# save scripts and funcs in subdirectory, lest they be modified while we run
TMPDIR=.scripter.tmp
if [ ! -d $TMPDIR ]; then
  mkdir $TMPDIR
fi
cp scripter.*.{conf,funcs} $TMPDIR

# load configs
for conf in $TMPDIR/scripter.*.conf; do
  echo "::: Loading configuration $conf"
  source $conf
done

# parse args
ms_names=""
ms_specs=""
processing_steps=""
args="$*"

while [ "$1" != "" ]; do
  # *.{ms,MS}, with an optional var=value suffix, is an MS name
  if echo $1 | egrep '^[^=]*\.(ms|MS)(:.*)?$' >/dev/null; then
    ms_specs="$ms_specs $1"
  # -f skips initial confirmation
  elif [ "$1" == "-f" ]; then
    unset CONFIRMATION_PROMPT
  # -i enables interactive mode
  elif [ "$1" == "-i" ]; then
    INTERACTIVE=1
    echo "::: Enabling interactive mode"
  # -d sets the default processing sequence
  elif [ "$1" == "-d" ]; then
    processing_steps="$DEFAULT_PROCESSING_SEQUENCE"
  # -a sets the MS list to ALL_MS
  elif [ "$1" == "-a" ]; then
    ms_specs="$ALL_MS"
  # +oper specifies a global operation, same with operations that start with _
  else
    processing_steps="$processing_steps $1"
  fi
  shift;
done

# if no steps specified, use default list
if [ "$processing_steps" == "" ]; then
  echo "No processing steps specified. Use -d to run default sequence:"
  echo "$DEFAULT_PROCESSING_SEQUENCE"
  exit 1
fi

# make list of MS names (by stripping of :var=value from MS specs)
ms_names=""
for ms in $ms_specs; do
  ms_names="$ms_names ${ms%%:*}"
done

echo "::: MSs: $ms_specs"
echo "::: processing sequence: $processing_steps";

if [ "$CONFIRMATION_PROMPT" != "" ]; then
  echo -n "$CONFIRMATION_PROMPT"
  read
fi

echo `date`: $0 $args >>.scripter.log

# this displays a prompt, if interactive mode is enabled with -i
interactive_prompt ()
{
  if [ "$INTERACTIVE" != "" ]; then
    echo -n "Press Enter to continue, or enter 'go' to run non-interactively from now... "
    read answer
    if [ "$answer" == "go" ]; then
      echo "::: Disabling interactive mode"
      unset INTERACTIVE
    fi
  fi
}

# function to iterate over a series of steps
iterate_steps ()
{
  echo "::: Iterating over steps: $*";
  if [ "$*" == "" ]; then
    return
  fi
  for oper in $*; do
    # var=value argument: directly assign to local variable
    if echo $oper | egrep '^[[:alnum:]]+=.*$' >/dev/null; then
      echo "::: Changing variable: $oper"
      eval $oper
    else
      # does oper have arguments, as oper[args]?
      if [ "${oper#*[}" != "$oper" -a "${oper:${#oper}-1:1}" == "]" ]; then
        args=${oper#*[}
        args=${args%]}
        oper=${oper%%[*}
        if [ "${args#*,,}" != "$args" ]; then
          args=${args//,,/ }
        else
          args=${args//,/ }
        fi
      else
        args="";
      fi
      echo "::: Running $oper $args (step=$step)"
      interactive_prompt
      if ! eval $oper $args; then
        echo "::: Operation '$oper $args' (step $step) failed";
        exit 1;
      fi
    fi
  done
}

# load functions
for func in $TMPDIR/scripter.*.funcs; do
  echo "::: Loading function set $func"
  source $func
done

ddid=0
field=0
step=0
MSNAME="$FULLMS"

per_ms ()
{
  # now start outer loop over MSs
  for MSNAMESPEC in $ms_specs; do
    # setup variables based on MS
    MSNAME="${MSNAMESPEC%%:*}"
    vars=${MSNAMESPEC#*:}
    if [ "$vars" != "$MSNAMESPEC" ]; then
      echo "::: Changing variables: $vars"
      eval ${vars//:/;}
    fi
    MS="ms_sel.msname=$MSNAME ms_sel.ddid_index=$ddid ms_sel.field_index=$field"
    CHANS="ms_sel.ms_channel_start=${CHAN0[$ddid]} ms_sel.ms_channel_end=${CHAN1[$ddid]}"
    FQSLICE=${CHAN0[$ddid]}~${CHAN1[$ddid]}:2
    FIELD="field=$field"
    msbase=`basename ${MSNAME} .MS`
    eval msbase=$FILENAME_PATTERN

    echo "::: MS $MSNAME ddid=$ddid field=$field steps:$*"
    alias
    interactive_prompt

    # load functions
    for func in $TMPDIR/scripter.*.funcs; do
      echo "::: Loading function set $func"
      source $func
    done

    iterate_steps $*
  done
  MSNAME="$FULLMS"
}

iterate_steps $processing_steps

exit 0;
