#!/bin/bash
set +xv
# piring - Control a school sound system from a Raspberry Pi with touchscreen
# Usage: ring [-s|--simulate]
#
# Hardware:
#  Pi with 3.5" 480x320 touchscreen and a relay that controls the
#  power to the amplifier, and a audio lead from the pi's output to the
#  amplifier's input, so that apart from ringing the various school bells,
#  alarms can be sounded and announcements can be made.
#
# Function:
#  The Normal schedule will ring on every weekday, unless that day is
#  marked as a No-Bells day. Special schedules will always ring on any day
#  they are scheduled, but then the Normal schedule will be cancelled, unless
#  at least 1 of the Special schedules is an Additional schedule (having a `+`
#  after the date in file $ringdates). The (optional) file $ringdates lists
#  the dates for the Special & Additional schedules and for the No-Bells days
#  (Saturdays & Sundays are No-Bells days by default).
#  The time schedules are defined in the file $ringtimes.
#  The touchscreen can be used to turn on the amplifier to make an
#  announcement or play (alarm) sound files.
# - The input files $ringdates and $ringtimes are read from the same directory
#   as where the $ring script resides, the $buttons script is in subdirectory
#   $touchscreen together with all images that are part of it,
#   and all the sound files reside in subdirectory $soundfiles.
# - The input files $ringtimes and $ringdates are read and checked for
#   proper syntax & semantics.
# - The Ringtone sound files referenced in $ringtimes are symlinks `R.ring`
#   in where `R` is the digit referenced (`0` is the default ringtone);
#   when referenced they need to be present in $soundfiles.
# - The optional (alarm)button sound files are symlinks `B.alarm` (B:1..4)
#   which are played when the corresponding touchscreen buttons are selected.
# - The temporary file $state also resides in $touchscreen and it is used to
#   pass the touchscreen state that is generated by the python script $buttons
#   (which is started from the $ring script).
# - When all is in order the program starts and output is logged to stdout.
#
# Format inputfiles:
# - All lines starting with `#` as the first character are skipped as comments.
# - $ringtimes: lines with `HH:MMsR` where `s` is Schedule (Normal schedule is
#   space/empty, and Special schedule codes have an alphabetic character) and
#   `R` is the numerical single digit Ringtone code. If `R` is space/empty it
#   references the default ringtone file `0.ring`. If `R` is `-` it means that
#   time slot is muted regardless of any other schedules. In general, the `R`
#   (numerical) refers to the ringtone file `R.ring`.
#   All characters after position 7 are ignored as a comment.
# - $ringdates (optional): lines of `YYYY-MM-DDsP` or `YYYY-MM-DD/YYYY-MM-DDsP`
#   where `s` is either space/empty (for No-Bells dates) or the alphabetical
#   Special schedule code. The `P` can be empty/space (replace the Normal
#   schedule) or `+` (in Addition to the Normal schedule). The double date
#   format is the beginning and end of an inclusive date range.
#   There can be multiple Special schedules for the same date, and all get rung
#   (even if that date is also a No-Bells date!).
#   All characters after position 12 resp. 23 are ignored as a comment.
#
# Required: coreutils(sleep fold readlink) sox(play) date
#  [$buttons: python3-pygame] [installation: tmux(optional)]
#
# License: GPLv3+  https://spdx.org/licenses/GPL-3.0-or-later.html


# Adjustables: (pins 1-26 are taken up by the touchscreen)
# BCM pin 26 (pin37): relay switch; pin39: GND; pin2/4: 5V (relay needs 5V)
pin=26 ampdelay=1 pollres=.1 shutoffdelay=.3 display=:0 gpiodelay=1 startdelay=1 relay=/sys/class/gpio/gpio$pin
[[ $1 = -s || $1 = --simulate ]] && sim=1 || sim=0

# Directory names, scripts and input filenames
ringtimes=ringtimes ringdates=ringdates touchscreen=touchscreen soundfiles=soundfiles
ring=$(readlink -e "$0") buttons=$touchscreen/buttons state=$touchscreen/state touchlog=$touchscreen/touch.log

Log(){ # $1:message $2(optional):timeflag
	local datetime
	[[ $2 ]] && datetime=$(date +'%Y-%m-%d %H:%M:%S')
	fold -s <<<"$1 $datetime"
}

Error(){ # IO:error  I:i,line  $1:message
	((++error))
	local l
	[[ $i ]] && l="Line $i: '$line' -"
	Log "* $l $1"
}

# Actually ring a bell
Ring(){ # IO:playing  I:now,pin,relay,ampdelay,time,shutoffdelay  $1:schedule
	local sched ringcode snd
	[[ $1 = '_' ]] && sched='Normal schedule' || sched="schedule '$1'"
	ringcode=${ringcodes[$now$1]}
	# Empty ringcode is 0
	[[ $ringcode ]] || ringcode=0
	snd=$soundfiles/$ringcode.ring
	Gpio on
	# Ring bell
	Log "- Ring Ringtone $ringcode on $sched at $now"
	play -V0 -q "$snd" 2>/dev/null ||
		Log "* Error playing $snd at $now"
	Gpio off
}

# Handle button inputs
Button(){ # IO:playing  I:state,button,relayon,soundfiles
	local button=$(<"$state") snd
	# States: relay on/off and playing yes/no; transitions: button 0..4
	# 0: if relayon: relayoff and kill player if playing
	# If not 0 and relayoff: relayon; if file present: play file

	# Nothing on, nothing needed
	((! button && ! relayon)) && return

	# No button and relayon: relay off and no playing
	if ((! button && relayon))
	then
		# If actually playing
		if ((playing)) && ps $playing >/dev/null
		then
			kill -9 $playing
			wait $playing 2>/dev/null
			Log "* Interrupted sound from process $playing" time
		fi
		Gpio off
		return
	fi

	# Already on: no action
	((relayon)) && return

	# Turn on if announcing or sound file present
	snd=$(readlink -e "$soundfiles/$button.alarm")
	if ((button==1)) || [[ $snd ]]
	then Gpio on
	else Log "* Missing sound file $soundfiles/$button.alarm"
	fi

	# Play sound file if present
	if [[ $snd ]]
	then
		play -V0 --ignore-length -q "$snd" 2>/dev/null &
		playing=$!
		(($?)) && Log "* Error playing $snd at $now"
		((button>1)) && Log "- ALARM $button: $snd" time
	fi
	((button==1)) && Log "- Announcement: $snd" time
}

# See if a bell needs to be ringed
Bellcheck(){ # IO:nowold,daylogged I:nobellsdates,specialdates,schedules,additionals,ringcodes,muteds
	# Once daily log and ring if required
	local now=$(date +'%H:%M') today=$(date +'%Y-%m-%d')
	local additoday=0 spectoday=0 rung=0 speclogged=0

	# Skip if this time has been checked already earlier
	[[ $now = $nowold ]] &&
		return
	nowold=$now

	# If muted, register now as rung
	[[ "${muteds[$now]} " = *" $today "* ]] &&
		rung=1 &&
		Log "> $today muting: $now"

	# No daylog yet at the start of a new day (or at program startup)
	[[ $now = 00:00 ]] && daylogged=0

	# Check all Special schedules
	for s in "${!specialdates[@]}"
	do
		if [[ "${specialdates[$s]} " = *" $today "* ]]
		then # Today has a Special schedule
			spectoday=1
			# Log all special schedules for today if not yet logged
			((! daylogged && ++speclogged)) &&
				Log "> $today '$s${additionals[$s]}' day:${schedules[$s]}"
			# If any Special schedules is Additional today, mark it
			[[ ${additionals[$s]} ]] &&
				additoday=1
			((! rung)) &&
				[[ "${schedules[$s]} " = *" $now "* ]] &&
				rung=1 &&
				Ring $s
		fi
	done
	((speclogged && ! additoday)) && daylogged=1

	# No longer deal with Normal days if No-Bells day today
	if [[ "$nobellsdates " = *" $today "* ]]
	then
		# Log No-Bells day if nothing logged yet today
		((! daylogged)) &&
			daylogged=1 &&
			Log "> $today No-Bells day"
		return
	fi

	# Ignore weekends (days 6 and 7), no Normal day
	if (($(date +'%u')>5))
	then
		# Log Weekend day if nothing logged yet today
		((! daylogged)) &&
			daylogged=1 &&
			Log "> $today $(date +'%A')"
		return
	fi

	# Log Normal day if nothing (or only special schedules) logged for today
	((! daylogged)) &&
		daylogged=1 &&
		Log "> $today Normal day:${schedules['_']}"

	# If not rung yet and: additional schedule or no special schedules at all
	((! rung && (additoday || ! spectoday))) &&
		[[ "${schedules['_']} " = *" $now "* ]] &&
		rung=1 &&
		Ring _
}

Exittrap(){ # I:playing,buttonspid
	((relayon)) && Gpio off
	Gpio down
	kill "$playing"
	kill -9 "$buttonspid"
	Log $'\n'"# Quit" time
}

Gpio(){ # 1:up|down|out|on|off  I:sim,pin,gpiodelay,relay,off,on  IO:relayon
	case $1 in
	up) # Export relay pin
		((!sim)) && ! echo $pin >/sys/class/gpio/export &&
			Log "* Exporting relay pin $pin failed" && exit 1
		Log "> Relay pin $pin exported"
		sleep $gpiodelay
		((!sim)) && [[ ! -a $relay ]] &&
			Log "* Setting up relay with pin $pin failed" && exit 1 ;;
	down) # Unexport relay pin
		sleep $gpiodelay
		((!sim)) && echo $pin >/sys/class/gpio/unexport
		sleep $gpiodelay ;;
	out) # Set relay pin to output
		((!sim)) && ! echo out >$relay/direction &&
			Log "* Setting up relay pin $pin for output failed" && exit 1
		Log "> Relay pin $pin used for output"
		sleep $gpiodelay
		Gpio off ;;
	off) # Turn relay off
		sleep $shutoffdelay
		((!sim)) && ! echo $off >$relay/value &&
			Log "* Error turning off amplifier" && exit 1
		Log "- Amplifier off" time
		relayon=0 playing=0 ;;
	on) # Turn relay on
		((!sim)) && ! echo $on >$relay/value &&
			Log "* Error turning on amplifier" time && exit 1
		Log "- Amplifier on" time
		sleep $ampdelay
		relayon=1 ;;
	esac
}

# Globals
declare -A schedules=() ringcodes=() specialdates=() additionals=() muteds=()
kbd= nobellsdates= nowold= relayon= playing=0 errors=0 i= daylogged=0
on=0 off=1 output=op buttonspid=  # reversed on & off

# Read files from the same directory as this script
cd "${ring%/*}"

Log $'\n'"# Ring program initializing" time
Log "> Amplifier switch-on delay ${ampdelay}s"

# Setting up pins
((sim)) && Log "> Simulate, not writing to gpio device"
if [[ ! -a $relay ]]
then Gpio up
else Log "> Relay pin $pin already exported"
fi
Gpio out
trap Exittrap QUIT EXIT

Log "- Validating Date information in '$(readlink -f $ringdates)'"
error=0
today=$(date +'%Y-%m-%d')
[[ -f "$ringdates" ]] && mapfile -O 1 -t dates <"$ringdates" || dates=()
for i in "${!dates[@]}"
do # Validate and split dates
	line=${dates[$i]} date=${line:0:10} s=${line:10:1}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	[[ $date = 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]] ||
		Error "Date format should be '20YY-DD-MM', not: $date"
	date -d "$date" &>/dev/null || Error "Invalid date: '$date'"
	if [[ $s = / ]]
	then
		date2=${line:11:10}
		[[ $date2 = 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]] ||
			Error "Date format should be '20YY-DD-MM', not: $date2"
		date -d "$date2" &>/dev/null || Error "Invalid date: '$date2'"
		[[ $date > $date2 ]] && Error "The first date can't be after the second"
		s=${line:21:1} a=${line:22:1}
		[[ ${s// } && ! $s = [a-zA-Z] ]] &&
			Error "Schedule should be alphabetic, not '$s'"
		[[ ${a// } && ! $a = '+' ]] &&
			Error "After the schedule only space or '+' allowed, not '$a'"
		while [[ ! $date > $date2 ]]
		do
			if [[ ! $date < $today ]]
			then
				if [[ ${s// } ]]
				then
					specialdates[$s]+=" $date"
					additionals[$s]=${a// }
				else (($(date -d $date +'%u')<6)) && nobellsdates+=" $date"
				fi
			fi
			date=$(date -d "tomorrow $date" +'%Y-%m-%d')
		done
	else
		[[ ${s// } && ! $s = [a-zA-Z] ]] &&
			Error "Schedule should be alphabetic, not '$s'"
		a=${line:11:1}
		[[ ${a// } && ! $a = '+' ]] &&
			Error "After the schedule only space or '+' allowed, not '$a'"
		[[ $date < $today ]] && continue
		if [[ ${s// } ]]
		then
			specialdates[$s]+=" $date"
			additionals[$s]=${a// }
		else (($(date -d $date +'%u')<6)) && nobellsdates+=" $date"
		fi
	fi
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringdates"
((errors+=error))

Log "- Validating Time information in '$(readlink -f $ringtimes)'"
error=0
[[ -f "$ringtimes" ]] || Error "No input file '$ringtimes'"
mapfile -O 1 -t times <"$ringtimes"
for i in "${!times[@]}"
do # Validate and store times
	line=${times[$i]} time=${line:0:5} s=${line:5:1} ringcode=${line:6:1}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	date -d "$time" &>/dev/null || Error "Invalid Time: '$time'"
	# Use underscore for the Normal schedule (schedule is empty or space)
	[[ ${s// } ]] || s='_'
	[[ $s = [_a-zA-Z] ]] || Error "Schedule should be alphabetical, not '$s'"
	[[ ${ringcode// } ]] || ringcode=0
	[[ $ringcode = [-0-9] ]] ||
		Error "Ringcode should be single digit, space or '-', not '$ringcode'"
	[[ ! $ringcode = '-' && ! -f $soundfiles/$ringcode.ring ]] &&
		Error "Sound filename '$soundfiles/$ringcode.ring' missing"
	# Skip if no dates with this schedule and it is not a Normal schedule
	[[ -z ${specialdates[$s]} && ! $s = '_' ]] && continue
	# Mute '-' ringcodes
	if [[ $ringcode = '-' ]]
	then
		muteds[$time]=${specialdates[$s]}
		schedules[$s]+=" $time-Muted"
	else
		ringcodes[$time$s]=$ringcode
		schedules[$s]+=" $time"
	fi
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringtimes"
((errors+=error))

# Listing ringtone files
rings=${ringcodes[@]} rings=$(sort -u <<<"${rings// /$'\n'}")
for r in $rings
do Log "> Ringtone $r: $(readlink "$soundfiles/$r.ring")"
done

# Listing alarmfiles
for b in 1 2 3 4
do
	f=$soundfiles/$b.alarm
	[[ -f $f ]] || continue
	Log "> Alarm button $b: $(readlink "$f")"
done

# Listing dates
Log "> No-Bells dates:$nobellsdates"
for s in "${!specialdates[@]}"
do Log "> '$s' dates:${specialdates[$s]}"
done

# Listing schedules
for s in "${!schedules[@]}"
do
	[[ $s = '_' ]] && scheds='Normal schedule:' || scheds="'$s' schedule:"
	for t in ${schedules[$s]}
	do
		r=${ringcodes[$t$s]}
		case $r in
			0) scheds+=" $t" ;;
			*) scheds+=" ${t}-$r"
		esac
	done
	Log "> $scheds"
done

# Reporting initial checks
((errors==1)) && s= || s=s
((errors)) &&
	Log "* Total of $errors error$s, not starting Ring program" && exit 2
Log "> All input files are valid"

# Starting the button interface
[[ -f $state ]] || echo -n "0">"$state"
((!sim)) && DISPLAY=$display $buttons >"$touchlog" &
buttonspid=$!
sleep $startdelay
((!sim)) && ! kill -0 $buttonspid 2>/dev/null && Log "* Can't start 'buttons'" && exit 3
Log "> Touchscreen ready, pid: $buttonspid"

# Main loop
Log "# Ring program starting" time
while :
do
	Button
	Bellcheck
	sleep $pollres
done
