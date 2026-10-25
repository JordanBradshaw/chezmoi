# Shared helpers for the zsh tests of the files under
# home/private_dot_config/zsh (moved here from the yupps-zsh plugin). Each test
# file sets ZDOT, defines load_conf and test_* functions, then calls run_all.

emulate -L zsh
setopt extended_glob

typeset -gi PASS=0 FAIL=0

fail() {
  print -u2 "    $*"
  exit 1
}

assert_eq() {
  [[ $1 == $2 ]] || fail "${3:-assert_eq}: expected [$2], got [$1]"
}

# stub_cmd NAME [BODY]: create an executable in $STUB_BIN.
stub_cmd() {
  print -r -- "#!/bin/sh
${2:-exit 0}" >| $STUB_BIN/$1
  # Absolute paths: tests may narrow PATH to $STUB_BIN.
  /bin/chmod +x $STUB_BIN/$1
}

# stub_echo NAME...: stubs that print their name and arguments.
stub_echo() {
  local name
  for name in "$@"; do
    stub_cmd $name "echo $name \"\$@\""
  done
}

# stub_comp NAME COMMANDS...: create a completion function in $STUB_FPATH.
stub_comp() {
  local name=$1; shift
  print -r -- "#compdef $*
return 0" >| $STUB_FPATH/$name
}

sandbox() {
  SANDBOX=$(mktemp -d)
  # XDG_CONFIG_HOME too: git and delta must not read the real config.
  export HOME=$SANDBOX/home XDG_CACHE_HOME=$SANDBOX/cache XDG_CONFIG_HOME=$SANDBOX/config
  STUB_BIN=$SANDBOX/bin STUB_FPATH=$SANDBOX/fpath
  mkdir -p $HOME/.ssh $XDG_CACHE_HOME $STUB_BIN $STUB_FPATH
  path=($STUB_BIN /usr/bin /bin)
  fpath=($STUB_FPATH $fpath)
}

run_test() {
  local name=$1
  (
    sandbox
    trap '/bin/rm -rf $SANDBOX' EXIT
    $name
  )
  if (( $? == 0 )); then
    (( PASS++ ))
    print "  ok   $name"
  else
    (( FAIL++ ))
    print "  FAIL $name"
  fi
}

run_all() {
  local t
  for t in ${(ok)functions[(I)test_*]}; do
    run_test $t
  done
  print "\n$PASS passed, $FAIL failed"
  (( FAIL == 0 ))
}
