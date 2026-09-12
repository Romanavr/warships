class_name Lang
extends RefCounted
## Русский / English.
##
## Keyed on the English string rather than on an abstract id. That is the
## unusual choice here and it is deliberate: the alternative means rewriting
## every line of campaign dialogue, every HUD label and every control caption
## into `tr("hud.target")` form, and a table of ids nobody can read alongside
## a table of strings nobody can find. Keying on the source text means a line
## that has no translation falls back to English and still says something true.
##
## The cost is real and worth stating: change an English string and its
## translation stops matching. `tests/lang.gd` walks every key in the table and
## fails if it is no longer present in the code, which turns that from a silent
## regression into a failing test.

const ENGLISH: String = "en"
const RUSSIAN: String = "ru"
const SETTING: String = "user://language.cfg"

static var current: String = ENGLISH

static func set_language(code: String) -> void:
	current = RUSSIAN if code == RUSSIAN else ENGLISH
	var file := ConfigFile.new()
	file.set_value("display", "language", current)
	file.save(SETTING)

static func load_language() -> void:
	var file := ConfigFile.new()
	if file.load(SETTING) == OK:
		current = String(file.get_value("display", "language", ENGLISH))

static func russian() -> bool:
	return current == RUSSIAN

static func t(text: String) -> String:
	## Translate, or hand back what came in. Untranslated English on screen is a
	## gap; a missing key crashing the HUD mid-fight is a bug.
	if current == ENGLISH:
		return text
	return String(TABLE.get(text, text))

const TABLE := {
	# --- front end -------------------------------------------------------- #
	"STRAIT OF HORMUZ": "ОРМУЗСКИЙ ПРОЛИВ",
	"Choose your fight": "Выберите бой",
	"CAMPAIGN": "КАМПАНИЯ",
	"Four levels · Strait of Hormuz": "Четыре уровня · Ормузский пролив",
	"Close the strait. Starts by teaching you where to put your rounds.":
		"Закрыть пролив. Начинается с того, что учит, куда класть снаряды.",
	"DUEL": "ДУЭЛЬ",
	"One corvette against one": "Один корвет против одного",
	"No orders and no escorts. Everything you have is released from the first second.":
		"Ни приказов, ни охранения. Всё оружие свободно с первой секунды.",
	"1 or 2 · arrows and Enter · or click": "1 или 2 · стрелки и Enter · или мышью",
	"LANGUAGE": "ЯЗЫК",

	# --- HUD panels -------------------------------------------------------- #
	"TARGET": "ЦЕЛЬ",
	"YOU": "ВЫ",
	"NO CONTACT DESIGNATED": "ЦЕЛЬ НЕ НАЗНАЧЕНА",
	"T · designate nearest": "T · назначить ближайшую",
	"GUNS": "ПУШКИ",
	"ASM": "ПКР",
	"MASKED": "ЗАКРЫТА БЕРЕГОМ",
	"OUT OF RANGE": "ВНЕ ДОСЯГАЕМОСТИ",
	"SPEED": "СКОРОСТЬ",
	"ALT": "ВЫСОТА",
	"STANDING BY": "ОЖИДАНИЕ",
	"ROTARY WING · ATTACK": "ВЕРТОЛЁТ · УДАРНЫЙ",
	"MERCHANT HULL · UNARMED": "ТОРГОВОЕ СУДНО · БЕЗ ОРУЖИЯ",
	"NO AIR SUPPORT": "АВИАПОДДЕРЖКИ НЕТ",

	# --- pause and controls ------------------------------------------------- #
	"PAUSED": "ПАУЗА",
	"SHIP CONTROLS": "УПРАВЛЕНИЕ КОРАБЛЁМ",
	"GUNSHIP CONTROLS": "УПРАВЛЕНИЕ ВЕРТОЛЁТОМ",
	"ahead and astern": "вперёд и назад",
	"helm": "руль",
	"fire the guns at the pointer": "огонь из пушек по курсору",
	"anti-ship missile at the designated contact": "ПКР по назначенной цели",
	"designate the next contact, nearest first": "назначить следующую цель, от ближней",
	"take the other set of controls": "перейти к другому аппарату",
	"forward and back": "вперёд и назад",
	"turn": "поворот",
	"climb and descend": "набор и снижение высоты",
	"rockets, or cannon when they are gone": "НУРС, затем пушка",
	"air-to-air missile": "ракета воздух-воздух",
	"flares": "тепловые ловушки",
	"back to the ship": "обратно на корабль",
	"pause": "пауза",
	"restart the level": "перезапустить уровень",
	"full damage readout": "полная сводка повреждений",
	"orbit the camera · Shift to slide it": "вращать камеру · Shift — сдвинуть",

	# --- prompts ------------------------------------------------------------ #
	"Press T to designate the contact you want to shoot at.":
		"Нажмите T, чтобы назначить цель.",
	"Now hold the left mouse button to fire where you are pointing.":
		"Теперь удерживайте левую кнопку мыши — огонь по курсору.",
	"T designates, X sends an anti-ship missile at whatever is designated.":
		"T назначает цель, X пускает по ней противокорабельную ракету.",
	"Point at the gold diamond on her funnel and hold the left button.":
		"Наведитесь на золотой ромб у трубы и удерживайте левую кнопку.",
	"When VAMPIRE flashes, a missile is inbound. Your close-in gun answers it on its own.":
		"Когда мигает VAMPIRE — к вам идёт ракета. Зенитный автомат отвечает сам.",
	"You are flying now. Space and Shift for height, Z for flares if he shoots.":
		"Вы за штурвалом. Space и Shift — высота, Z — ловушки, если по вам пустят ракету.",
	"Put an island between you and her and her missiles lose the track.":
		"Уйдите за остров — её ракеты потеряют захват.",
	"T designates her. Guns for her mounts, missiles for her hull — or the other way round.":
		"T назначает её. Пушки по установкам, ракеты по корпусу — или наоборот.",
	"Rockets. X for the air-to-air missile, Z to throw flares.":
		"НУРС. X — ракета воздух-воздух, Z — тепловые ловушки.",
	"Middle mouse button and drag swings the view round your ship.":
		"Средняя кнопка мыши с перетаскиванием вращает камеру вокруг корабля.",

	# --- debrief ------------------------------------------------------------ #
	"ROUNDS FIRED": "ВЫПУЩЕНО СНАРЯДОВ",
	"ROUNDS ON TARGET": "ПОПАДАНИЙ",
	"MISSILES": "РАКЕТЫ",
	"MODULES KNOCKED OUT": "ВЫВЕДЕНО МОДУЛЕЙ",
	"CONTACTS SUNK": "ПОТОПЛЕНО ЦЕЛЕЙ",
	"DAMAGE TAKEN": "ПОЛУЧЕНО УРОНА",
	"TIME": "ВРЕМЯ",
	"GUNNERY EXCELLENT": "СТРЕЛЬБА ОТЛИЧНАЯ",
	"GUNNERY GOOD": "СТРЕЛЬБА ХОРОШАЯ",
	"ROUNDS WASTED": "СНАРЯДЫ ПОТРАЧЕНЫ ЗРЯ",
	"SHOOTING WILD": "СТРЕЛЬБА МИМО",
	"NO ROUNDS EXPENDED": "СНАРЯДЫ НЕ РАСХОДОВАЛИСЬ",
	"Stand by for the next contact": "Ожидайте следующую цель",
	"Press R to fight it again": "Нажмите R, чтобы повторить",
	"THE STRAIT IS CLOSED": "ПРОЛИВ ЗАКРЫТ",


	# --- who is speaking ----------------------------------------------------- #
	"ADM. RONALD J. GRUMP": "АДМ. РОНАЛЬД ДЖ. ГРАМП",
	"ADM. RONALD GRUMP": "АДМ. РОНАЛЬД ГРАМП",
	"COMMANDER · TASK GROUP TREMENDOUS": "КОМАНДУЮЩИЙ · СОЕДИНЕНИЕ «ПОТРЯСАЮЩЕЕ»",
	"TASK GROUP TREMENDOUS": "СОЕДИНЕНИЕ «ПОТРЯСАЮЩЕЕ»",
	"You gonna pay for this. Bigly. Attack them!":
		"Вы за это заплатите. Крупно. Атаковать их!",
	"ADMIRAL NASIRI": "АДМИРАЛ НАСИРИ",
	"FLEET COMMAND": "КОМАНДОВАНИЕ ФЛОТА",
	"SHAHEEN 1": "ШАХИН-1",
	"ARMY AVIATION": "АРМЕЙСКАЯ АВИАЦИЯ",
	"MASTER, MV MERIDIAN": "КАПИТАН Т/Х «МЕРИДИАН»",
	"CHANNEL 16": "КАНАЛ 16",
	"VIPER 3": "ВАЙПЕР-3",
	"US NAVAL AVIATION": "АВИАЦИЯ ВМС США",
	"CAPT. HALSTEAD": "КЭПТ. ХОЛСТЕД",
	"US NAVY": "ВМС США",
	"DISTRESS": "БЕДСТВИЕ",
	"CHANNEL 16 · ALL SHIPS": "КАНАЛ 16 · ВСЕМ СУДАМ",

	# --- campaign dialogue --------------------------------------------------- #
	"No task group, Kestrel. No gunships, no orders. Just the two of us. Come ahead.":
		"Ни соединения, Кестрел. Ни вертолётов, ни приказов. Только мы двое. Подходи.",
	"She is gone. Clean fight, Kestrel.": "Её больше нет. Чистый бой, Кестрел.",
	"Kestrel, Fleet Command. Tehran has closed the strait to US-flagged traffic as of this morning. You are the enforcement.":
		"Кестрел, командование флота. С сегодняшнего утра Тегеран закрыл пролив для судов под флагом США. Обеспечение — на вас.",
	"Contact fine on your port bow — the box boat Meridian, running the closure. Order her to heave to.":
		"Цель слева по носу — контейнеровоз «Меридиан», идёт в нарушение запрета. Прикажите ему лечь в дрейф.",
	"Kestrel, Meridian. We are in an international transit lane, we are not heaving to, and my owners will hear about this. Out.":
		"Кестрел, «Меридиан». Мы в международном коридоре, в дрейф не ложимся, и о вашем поведении узнают судовладельцы. Конец связи.",
	"She has made her choice. Put rounds into her engine room — the funnel, right aft. Nothing else.":
		"Он сделал выбор. Бейте по машинному отделению — труба, ближе к корме. Больше никуда.",
	"Stopped, Kestrel. Not on the bottom. Sink a merchant and this ends badly for every one of us.":
		"Остановить, Кестрел. Не утопить. Потопите торговое судно — и всем нам это выйдет боком.",
	"Her engine room is gone and she is dead in the water. Check fire.":
		"Машинное отделение уничтожено, судно потеряло ход. Прекратить огонь.",
	"New contacts to the south, closing fast — two US patrol craft coming to collect her.":
		"Новые цели с юга, быстро сближаются — два патрульных катера США идут за ним.",
	"Guns only, Kestrel. You are not cleared for missiles. Let us not start a war over a box boat.":
		"Только артиллерия, Кестрел. Ракеты применять запрещаю. Не будем начинать войну из-за контейнеровоза.",
	"Both down. That is how it is done.": "Оба потоплены. Вот так это и делается.",
	"A tug is coming out of Bandar Abbas for the Meridian. Let her go — she is somebody else's problem now.":
		"Из Бендер-Аббаса за «Меридианом» вышел буксир. Оставьте его — теперь это чужая забота.",
	"Stand by, Kestrel. This will not be the last of them.":
		"Будьте наготове, Кестрел. Эти были не последними.",
	"Kestrel, four fast craft leaving Bandar-e-Jask at speed. These ones are carrying anti-ship missiles.":
		"Кестрел, из Бендер-э-Джаска полным ходом вышли четыре быстроходных катера. У этих — противокорабельные ракеты.",
	"Keep your close-in gun hot and watch for the vampire warning. You are cleared for anti-ship missiles of your own — use them.":
		"Держите зенитный автомат в готовности и следите за сигналом VAMPIRE. Свои противокорабельные ракеты разрешаю — применяйте.",
	"Air contact, low and fast, sixteen hundred out. US gunship — they have stopped sending boats.":
		"Воздушная цель, низко и быстро, шестнадцать сотен. Ударный вертолёт США — катера они слать перестали.",
	"Viper Three, tally one corvette, in the open, no air cover. Rolling in.":
		"Вайпер-три, вижу корвет, на открытой воде, без прикрытия с воздуха. Захожу на цель.",
	"Not quite, Viper. Kestrel, Shaheen One — I am off your stern and I have him.":
		"Не совсем, Вайпер. Кестрел, я Шахин-один — я у вас за кормой и он у меня на прицеле.",
	"You have the cockpit. Kestrel is covering you now — take him.":
		"Вы за штурвалом. Кестрел вас прикрывает — работайте по нему.",
	"Splash one. Shaheen One is winchester and turning for the deck.":
		"Цель поражена. Шахин-один без боезапаса, снижаюсь и иду домой.",
	"SAM launch to the north — that is not the gunship. Shaheen, break, break!":
		"Пуск зенитной ракеты с севера — это не вертолёт. Шахин, отворот, отворот!",
	"Shaheen One is down. There is a corvette out there we never saw.":
		"Шахин-один сбит. Где-то там корвет, которого мы не видели.",
	"She is hauling off to the north. We are not finished with her.":
		"Он отходит на север. Мы с ним ещё не закончили.",
	"Kestrel, the corvette that killed Shaheen is still out there, and this time you are not alone.":
		"Кестрел, корвет, убивший Шахина, всё ещё там — и на этот раз вы не одни.",
	"Peykaap One and Two, joining from the north. Keep them under your close-in gun and they will live.":
		"Пейкаап-один и два присоединяются с севера. Держите их под своим зенитным автоматом — и они уцелеют.",
	"Still here? After what I did to your helicopter? You have no idea what you are dealing with.":
		"Ещё здесь? После того, что я сделал с вашим вертолётом? Вы не понимаете, с кем связались.",
	"Kestrel, USS Carney. You are outranged and outgunned. Come about and go home.":
		"Кестрел, это «Карни». Вы уступаете и в дальности, и в огне. Разворачивайтесь и уходите.",
	"Do not come about, Kestrel. Get inside her missile envelope and finish it. That is for Shaheen.":
		"Не разворачивайтесь, Кестрел. Войдите в зону пуска и закончите это. Это за Шахина.",
	"Carney is gone. That is for Shaheen One, and the strait is closed. Bring her home, Kestrel.":
		"«Карни» уничтожен. Это за Шахина-один, и пролив закрыт. Возвращайтесь домой, Кестрел.",

	# --- module names ------------------------------------------------------- #
	"Forward gun": "Носовое орудие",
	"Aft gun": "Кормовое орудие",
	"Engine room": "Машинное отделение",
	"Steering gear": "Рулевая машина",
	"Bridge": "Мостик",
	"Wheelhouse": "Ходовая рубка",
	"Search radar": "Обзорная РЛС",
	"Navigation radar": "Навигационная РЛС",
	"Port VLS": "Левая ПУ",
	"Stbd VLS": "Правая ПУ",
	"CIWS mount": "Зенитный автомат",
	"IR SAM bank": "ЗУР с ИК ГСН",
	"Bow hull": "Носовая часть",
	"Citadel hull": "Средняя часть",
	"Stern hull": "Кормовая часть",
	"Forepeak": "Форпик",
	"Cargo holds": "Грузовые трюмы",
}
