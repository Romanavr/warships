extends TestHarness
## The translation table, and the guard that keeps it honest.
##
## Translations are keyed on the English source string, which is what makes the
## rest of the code readable — but it also means an innocent edit to an English
## caption silently orphans its Russian. So every key is checked against the
## code that is supposed to produce it.
var failures := 0

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func sources() -> String:
	var joined := ""
	# Every script that puts words on the screen. Miss one and the guard reports
	# its strings as orphans, which is a false alarm that trains people to
	# ignore the real ones.
	for name: String in ["hud", "mode_menu", "campaign", "tally", "ship_layout",
			"patrol", "comms", "briefing", "boat"]:
		joined += FileAccess.get_file_as_string("res://scripts/%s.gd" % name)
	return joined

func run() -> void:
	Lang.set_language(Lang.ENGLISH)
	check(Lang.t("TARGET") == "TARGET", "English hands the source string straight back")
	Lang.set_language(Lang.RUSSIAN)
	check(Lang.t("TARGET") == "ЦЕЛЬ", "Russian translates it")
	check(Lang.t("nothing has this string") == "nothing has this string",
		"An untranslated string falls back rather than vanishing")
	check(Lang.russian(), "and the language sticks")

	# Every entry has to be non-empty and actually different, or it is a line
	# someone forgot to finish.
	var blank: Array[String] = []
	var same: Array[String] = []
	for key: String in Lang.TABLE:
		var value := String(Lang.TABLE[key])
		if value.strip_edges() == "":
			blank.append(key)
		elif value == key and key != "L · English / Русский":
			same.append(key)
	check(blank.is_empty(), "No entry is blank, %d bad" % blank.size())
	check(same.is_empty(), "No entry is a copy of the English, %s" % str(same))

	# The keys have to still exist in the code that draws them. This is the
	# check that earns the string-keyed design its keep.
	var code := sources()
	var orphans: Array[String] = []
	for key: String in Lang.TABLE:
		if not code.contains(key):
			orphans.append(key)
	check(orphans.is_empty(), "Every key still appears in the code, orphaned: %s" % str(orphans))

	# A round trip through the setting file, because the choice is meant to
	# outlive the run that made it.
	Lang.set_language(Lang.RUSSIAN)
	Lang.current = Lang.ENGLISH
	Lang.load_language()
	check(Lang.russian(), "The choice is remembered between runs")
	Lang.set_language(Lang.ENGLISH)
	print("LANG RESULT: %d failures" % failures)
	quit(1 if failures else 0)
