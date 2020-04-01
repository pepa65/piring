#!/bin/bash
set +xv
# piring - Control a school sound system from a Raspberry Pi with touchscreen
# Usage: ring
#
# Hardware:
#  Pi with 3.5" 480x320 touchscreen and a relay that controls the
#  power to the amplifier, and a audio lead from the pi's output to the
#  amplifier's input, so that apart from ringing the various school bells,
#  alarms can be sounded and announcements can be made.
#
# Function:
#  The Normal schedule will ring on every weekday, unless that day is
#  marked as a No-Bells day. Special schedules will always ring on any
#  scheduled day, but the Normal schedule will be cancelled, unless at least
#  one of the Special schedules is an Additional schedule (having a `+` after
#  the date in $ringdates). The (optional) file $ringdates determines the
#  dates for the Special and Additional schedules and the No-Bells days (by
#  default Saturdays & Sundays).
#  The time schedules are defined in the file $ringtimes.
#  The touchscreen can be used to turn on the amplifier to make an
#  announcement or (optionally) play (alarm) sound files.
# - The input files $ringdates and $ringtimes are read from the same directory
#   as where the $ring script resides, the $buttons script is in directory
#   $ts together with all images that are part of it, and the sound files
#   reside in directory $sf.
# - The input files $ringtimes and $ringdates are read and checked for
#   proper syntax & semantics.
# - The ringtone sound files referenced in $ringtimes are symlinks `R.ring`
#   in where `R` is the digit referenced (`0` is the default ringtone); when
#   referenced they need to be present in $sf.
# - The optional (alarm)button sound files are symlinks `B.alarm` (B:1..4)
#   which are played when the corresponding touchscreen buttons are selected.
# - The temporary file $state also resides in $ts and it is used to pass
#   touchscreen state that is generated by the python script $buttons that is
#   started from the $ring script.
# - When all is in order the program starts and output is logged to stdout.
#
# Format inputfiles:
# - All lines starting with `#` as the first character are skipped as comments.
# - $ringtimes: lines with `HH:MMsR` where `s` is Schedule (Normal schedule is
#   space/empty, and Special schedule codes have an alphabetic character) and
#   `R` is the numerical single digit Ringtone code. If `R` is space/empty it
#   references the default ringtone file `0.ring`. If `R` is `-` it means that
#   time slot is muted regardless of any other schedules. In general, the `R`
#   refers to the ringtone file `R.ring`.
#   All characters after position 7 are ignored as a comment.
# - $ringdates (optional): lines of `YYYY-MM-DDis` or `YYYY-MM-DD/YYYY-MM-DDis`
#   where `s` is either space/empty (for No-Bells dates) or the alphabetical
#   Special schedule code. The `i` can be empty/space or `+` (means in addition
#   to the Normal schedule, otherwise the Normal schedule is replaced by the
#   Special schedule). The double date format is the beginning and end of an
#   inclusive date range. There can be multiple Special schedules for the
#   same date, and all get rung (even if that date is also a No-Bells date!).
#   All characters after position 12 resp. 23 are ignored as a comment.
#
# Required: wiringpi(gpio) coreutils(sleep fold readlink) sox(play) date
#  [$buttons: python2.7 python-pygame] [`rc.local`: tmux(optional)]
#
# Deployment:
#  To autostart on reboot, source the script `rc.local`. There are two
#   deployment examples given there.
#
# License:
#  GPLv3+  https://spdx.org/licenses/GPL-3.0-or-later.html


# Adjustables: pins 1-13 and 28-40 are taken by the touchscreen
relaypin=14 ampdelay=2 pollres=.1 shutoffdelay=.5 display=:0

# Directory names, scripts and input filenames
ts=touchscreen sf=soundfiles ring=$(readlink -e "$0") buttons=$ts/buttons
ringtimes=ringtimes ringdates=ringdates state=$ts/state

Log(){ # $1:message $2(optional):timeflag
	local datetime
	[[ $2 ]] && datetime=$(date +'%Y-%m-%d %H:%M:%S')
	fold -s <<<"$1 $datetime"
}

Error(){ # $1:message  I:$i $line  IO:$error
	((++error))
	local l
	[[ $i ]] && l="Line $i: '$line' -"
	Log "* $l $1"
}

Ring(){ #I:$now $relaypin $ampdelay $time $shutoffdelay
		# IO:$relayon  $1:schedule
	local sched ringcode snd
	[[ $1 = '_' ]] && sched='Normal schedule' || sched="schedule '$1'"
	ringcode=${ringcodes[$now$1]}
	# Empty ringcode is 0
	[[ $ringcode ]] || ringcode=0
	snd=$ringcode.ring
	# Turn relay on
	gpio -g write $relaypin $on && relayon=1 ||
		Log "* Error turning on amplifier" time
	sleep $ampdelay
	# Ring bell
	Log "- Ring Ringtone $ringcode on $sched at $now"
	play -V0 --ignore-length -q "$snd" 2>/dev/null ||
		Log "* Error playing $snd at $now"
	sleep $shutoffdelay
	# Turn relay off
	gpio -g write $relaypin $off && relayon=0 ||
		Log "* Error turning off amplifier" time
}

Button(){ # IO:$relayon $playing I:$relaypin $state
	local button=$(<"$state") soundfile
	# States: relay on/off and playing yes/no; transitions: button 0..4
	# 0: if relayon: relayoff and kill player if playing
	# If !0 and relayoff: relayon; if file present: play file

	# Nothing on, nothing needed
	((!button && !relayon)) && return

	# No button and relayon: relay off and no playing
	if ((!button && relayon))
	then
		# If actually playing
		if ((playing)) && ps $playing >/dev/null
		then
			kill -9 $playing
			wait $playing 2>/dev/null
			Log "* Interrupted sound from process $playing"
		fi
		sleep $shutoffdelay
		gpio -g write $relaypin $off && relayon=0 &&
			Log "- Amplifier off" time ||
			Log "* Error turning off amplifier" time
		playing=0
		return
	fi

	# Already on: no action
	((relayon)) && return

	# Turn on if announcing or sound file present
	if ((button==1)) || [[ -f $sf/$button.alarm ]]
	then
		gpio -g write $relaypin $on && relayon=1 &&
			Log "- Amplifier on" time && sleep $ampdelay ||
			Log "* Error turning on amplifier" time
	else
		Log "* Missing sound file for alarm $button"
	fi

	# Play sound file if present
	if [[ -f $sf/$button.alarm ]]
	then
		play -V0 --ignore-length -q "$sf/$button.alarm" 2>/dev/null &
		playing=$!
		(($?)) && Log "* Error playing $snd at $now"
		soundfile=$(readlink "$sf/$button.alarm")
		((button>1)) && Log "- ALARM $button: $soundfile" time
	fi
	((button==1)) && Log "- Announcement: $soundfile" time
}

Bellcheck(){ # IO:$nowold $daylogged
		# I:$nobellsdates $specialdates $schedules $additional $ringcodes $muted
	local now=$(date +'%H:%M') today=$(date +'%Y-%m-%d')
	local additoday=0 spectoday=0 rung=0 sslogs=0

	# Ignore if this time has been checked earlier
	[[ $now = $nowold ]] && return
	nowold=$now

	# If muted, register now as rung
	[[ "${muted[$now]} " = *" $today "* ]] &&
		rung=1 && Log "> $today muting: $now"

	# No daylog yet at the start of a new day
	[[ $now = 00:00 ]] && daylogged=0

	# Check all Special schedules
	for s in "${!specialdates[@]}"
	do
		if [[ "${specialdates[$s]} " = *" $today "* ]]
		then
			spectoday=1
			# Log all special schedules for today if not yet logged
			((!daylogged && ++sslogs)) &&
				Log "> $today '$s${additional[$s]}' day:${schedules[$s]}"
			# If any Special schedules is Additional today, mark it
			[[ ${additional[$s]} ]] && additoday=1
			((!rung)) && [[ "${schedules[$s]} " = *" $now "* ]] && rung=1 && Ring $s
		fi
	done
	((sslogs)) && daylogged=1 sslogs=0

	# No longer deal with Normal days if No-Bells day today
	if [[ "$nobellsdates " = *" $today "* ]]
	then
		# Log No-Bells day if nothing logged yet today
		((!daylogged)) && daylogged=1 && Log "> $today No-Bells day"
		return
	fi

	# Ignore weekends (days 6 and 7), no Normal day
	if (($(date +'%u')>5))
	then
		# Log Weekend day if nothing logged yet today
		((!daylogged)) && daylogged=1 && Log "> $today $(date +'%A')"
		return
	fi

	# Log Normal day if nothing logged yet today or Additional schedule(s)
	((!daylogged || additoday)) && daylogged=1 &&
		Log "> $today Normal day:${schedules['_']}"

	# If not rung yet and: additional schedule or no special schedules at all
	((!rung && (additoday || !spectoday))) &&
		[[ "${schedules['_']} " = *" $now "* ]] && rung=1 && Ring _
}

Exittrap(){ # I:$relaypin $playing
	gpio -g write $relaypin $off
	gpio unexportall
	kill "$playing"
	kill -9 "$buttonspid"
	Log
	Log "# Quit" time
}

# Globals
declare -A schedules=() ringcodes=() specialdates=() additional=() muted=()
kbd= gpio= nobellsdates= nowold= relayon= playing=0 errors=0 i= daylogged=0
on=0 off=1 buttonspid=

# Read files from the same directory as this script
cd "${ring%/*}"

Log "# Ring program initializing" time
Log "> Amplifier switch-on delay ${ampdelay}s"

# For testing without gpio installed
gpio=$(type -p gpio) || gpio(){ :;}

# Setting up pins
! gpio export $relaypin out &&
	Log "* Setting up relay pin $relaypin for output failed" && exit 1 ||
	Log "> Relay pin $relaypin used for output"
gpio -g write $relaypin $off && relayon=0 ||
	Log "* Error turning off amplifier"
trap Exittrap QUIT EXIT

Log "- Validating Date information in '$(readlink -f $ringdates)'"
error=0
today=$(date +'%Y-%m-%d')
[[ -f "$ringdates" ]] && mapfile -O 1 -t dates <"$ringdates" || dates=()
for i in "${!dates[@]}"
do # Validate and split dates
	line=${dates[$i]} date=${line:0:10} idate=${line:10:1}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	[[ $date = 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]] ||
		Error "Date format should be '20YY-DD-MM', not: $date"
	date -d "$date" &>/dev/null || Error "Invalid date: '$date'"
	if [[ $idate = / ]]
	then
		date2=${line:11:10}
		[[ $date2 = 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]] ||
			Error "Date format should be '20YY-DD-MM', not: $date2"
		date -d "$date2" &>/dev/null || Error "Invalid date: '$date2'"
		[[ $date > $date2 ]] && Error "The first date can't be after the second"
		idate=${line:21:1} s=${line:22:1}
		[[ ${idate// } && $idate != '+' ]] &&
			Error "After the dates only space or '+' allowed, not '$idate'"
		[[ ${s// } && $s != [a-zA-Z] ]] &&
			Error "Schedule should be alphabetic, not '$s'"
		while [[ ! $date > $date2 ]]
		do
			if [[ ! $date < $today ]]
			then
				[[ ${s// } ]] && specialdates[$s]+=" $date" || nobellsdates+=" $date"
				[[ $idate = '+' ]] && additional[$s]='+'
			fi
			date=$(date -d "tomorrow $date" +'%Y-%m-%d')
		done
	else
		[[ ${idate// } && $idate != '+' ]] &&
			Error "After the date only space, '/' or '+' allowed, not '$idate'"
		s=${line:11:1}
		[[ ${s// } && $s != [a-zA-Z] ]] &&
			Error "Schedule should be alphabetic, not '$s'"
		[[ $date < $today ]] && continue
		[[ ${s// } ]] && specialdates[$s]+=" $date" || nobellsdates+=" $date"
		[[ $idate = '+' ]] && additional[$s]='+'
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
	[[ $ringcode != '-' && ! -f $sf/$ringcode.ring ]] &&
		Error "Sound filename '$sf/$ringcode.ring' missing"
	# Skip if no dates with this schedule and it is not a Normal schedule
	[[ -z ${specialdates[$s]} && $s != '_' ]] && continue
	# Mute '-' ringcodes
	[[ $ringcode = '-' ]] &&
		muted[$time]=${specialdates[$s]} schedules[$s]+=" $time-Muted" ||
		ringcodes[$time$s]=$ringcode schedules[$s]+=" $time"
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringtimes"
((errors+=error))

# Listing ringtone files
rings=${ringcodes[@]} rings=$(sort -u <<<"${rings// /$'\n'}")
for r in $rings
do Log "> Ringtone $r: $(readlink "$sf/$r.ring")"
done

# Listing alarmfiles
for f in "$sf"/{1..4}.alarm
do
	[[ -f $f ]] || continue
	b=${f##*/} b=${b:0:1}
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
			*) scheds+=" ${t},$r"
		esac
	done
	Log "> $scheds"
done

# Reporting initial checks
((errors==1)) && s= || s=s
((errors)) &&
	Log "* Total of $errors error$s, not starting Ring program" && exit 2
Log "> All input files are valid"

[[ $gpio ]] ||
	Log "* Essential package 'wiringpi' (application 'gpio') not installed"

# Starting the button interface
DISPLAY=$display $buttons &
buttonspid=$!
(($?)) && Log "* Can't start 'buttons'" && exit 3
Log "> Touchscreen ready"

# Main loop
Log "# Ring program starting" time
while :
do
	Button
	Bellcheck
	sleep $pollres
done
