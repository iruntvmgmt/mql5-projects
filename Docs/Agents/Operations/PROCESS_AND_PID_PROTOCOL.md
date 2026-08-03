# MT5 Process and PID Protocol

## 1. Objective

Prevent an agent from killing the user's main terminal, confusing the main terminal with an isolated portable runtime, or attributing logs and artifacts to the wrong process.

## 2. Process classes

### Main terminal

A preexisting connected process associated with the installed MT5 root.

### Ticket-owned portable terminal

A process launched from an isolated root with a command line containing:

```text
/portable /config:<ticket-specific-ini>
```

### MetaEditor process

A compile process launched for one exact source path.

### Tester agent

A child process and filesystem sandbox created by Strategy Tester.

## 3. Session baseline

Before launching anything:

```bash
ps aux | grep '[t]erminal64.exe'
ps aux | grep '[m]etaeditor64.exe'
```

Record:

- PID;
- parent PID when available;
- executable path or command representation;
- full arguments;
- start time;
- whether the process existed before the ticket;
- ownership classification.

Write the preexisting main PID to an external evidence file, not the repository:

```bash
printf 'MAIN_TERMINAL_PID=%s\n' "$MAIN_PID" > "$EVIDENCE_DIR/main_terminal_pid.env"
```

## 4. Launch ownership

For every launch record:

- ticket ID;
- launch timestamp;
- exact command with secrets redacted;
- shell launcher PID;
- resulting Wine/Windows process PID;
- full command line;
- expected INI;
- expected executable root.

The process is ticket-owned only when its executable root and command-line arguments match the ticket.

## 5. Polling

Use bounded polling:

```bash
for i in $(seq 1 60); do
  if ps -p "$PID" >/dev/null 2>&1; then
    sleep 1
  else
    break
  fi
done
```

Process survival alone does not indicate test progress. Poll logs and artifacts separately.

## 6. Safe termination

Terminate only after:

- completion or failure is established;
- logs and artifacts are copied or hashed;
- the PID is proven ticket-owned;
- the main PID is known.

Preferred sequence:

```bash
kill "$TEST_PID"
sleep 2
if ps -p "$TEST_PID" >/dev/null 2>&1; then
  kill -TERM "$TEST_PID"
fi
```

Escalate force termination only when the ticket permits it and the process remains confirmed ticket-owned.

Never use:

```text
killall terminal64.exe
pkill -f terminal64.exe
```

unless the user explicitly authorizes termination of every MT5 process.

## 7. Post-cleanup verification

After cleanup:

- ticket-owned process absent;
- no orphaned process contains the ticket INI argument;
- main terminal PID still alive if it was alive before the task;
- no unrelated terminal was terminated;
- evidence records final process state.

## 8. Multiple portable terminals

Only one portable process may use the same isolated runtime at a time.

Parallel runtime work requires:

- separate isolated roots;
- separate INIs;
- separate output namespaces;
- separate evidence directories;
- explicit ticket authorization.

Disjoint source files do not make simultaneous access to one runtime safe.

## 9. Ambiguous PID handling

If `$!` identifies a Wine launcher that exits while `terminal64.exe` continues:

1. capture `$!` as launcher PID;
2. discover the final process by exact executable root and `/config:` argument;
3. ensure exactly one matching process exists;
4. record both PIDs;
5. stop if multiple matching processes exist.

## 10. Stop conditions

Stop and report `RUNTIME_EVIDENCE_AMBIGUOUS` when:

- the main PID cannot be distinguished from the portable PID;
- more than one process uses the same ticket INI;
- the executable root is not visible or verifiable;
- another agent launches into the same runtime;
- a process appears without a matching staging/launch record.
