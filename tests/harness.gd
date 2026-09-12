class_name TestHarness
extends SceneTree
## Common entry point for every test script, with the one thing none of them had:
## a way to die.
##
## A script error inside an awaited `run()` aborts the coroutine without ever
## reaching `quit()`. The scene tree stays up, the headless process keeps
## spinning at a tenth of a core, and nothing anywhere says so. One mistyped
## method name left three of these running for hours, quietly competing for the
## GPU with the benchmarks that were trying to measure it — and the benchmarks
## duly reported frame spikes that had nothing to do with the game.
##
## So: whatever happens inside `run()`, the process exits. A hung test is a
## failed test and says so, rather than becoming a background tax on the machine
## that nobody connects to the test that caused it.

## Wall-clock seconds a test may take before it is assumed to have hung.
const DEADLINE: float = 300.0
## Exit code for a hang, kept distinct from 1 so a timeout is never mistaken for
## an ordinary assertion failure.
const HUNG: int = 2

func _initialize() -> void:
	watchdog(deadline())
	call_deferred("run")

func deadline() -> float:
	## Override in a test that legitimately runs longer than five minutes.
	return DEADLINE

func watchdog(seconds: float) -> void:
	await create_timer(seconds).timeout
	# Both, deliberately: the print is what a person scanning output sees, the
	# error is what a CI log filter catches.
	print("WATCHDOG: run() did not finish within %.0f s — exiting" % seconds)
	push_error("watchdog: test hung after %.0f s" % seconds)
	quit(HUNG)

func run() -> void:
	print("WATCHDOG: this test defines no run()")
	quit(HUNG)
