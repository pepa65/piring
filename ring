#!/bin/bash
set +xv
# ring - Control a school sound system from a Raspberry Pi
# Usage: ring [-k|--keyboard [<device>]]
#          -k/--keyboard:  use keyboard [device] instead of the button
# Function:
#   The Normal schedule will ring on every weekday, unless that day is
#   marked as a No-Bells day. Special schedules will always ring on any
#   scheduled day, but the Normal schedule will be cancelled, unless at least
#   one of the Special schedules is an Additional schedule (having a `+` after
#   the date in `ringdates`).
#   The (optional) file `ringdates` determines the dates for the Special
#   schedules and the No-Bells days, the time schedules are defined in the file
#   `ringtimes`, and the file `ringtones` contains the names of the
#   corresponding .wav-files.
#   The optional file `ringalarms` defines what happens when the button is
#   pushed for a certain minimum length, which can be used for alarms.
#
#   Input files 'ringtimes', 'ringtones', 'ringdates' and 'ringalarms' are read
#   from the same directory as where the 'ring' script resides. These are
#   checked for proper syntax & semantics, and when OK the program starts and
#   keeps running, logging output to stdout.
# Format inputfiles:
# - Lines with '#' as the first character are skipped as comments.
# - ringtimes: lines with `HH:MMsR` where `s` is Schedule (Normal schedule is
#   space/empty, and Special schedule codes have an alphabetic character) and
#   `R` is the Ringtone code. If `R` is space/empty it means it is `0` (the
#   default), a `-` means a mute for that time regardless of any other
#   schedules. In general, the `R` matches the first position of lines with the
#   filename of a `.wav` sound file in the `ringtones` file. R is numerical if
#   not empty or `-`. All characters after position 7 are ignored as a comment.
# - ringtones: lines with `Rfilename`, where `R` is the numerical Ringtone
#   code (0 is the Normal ringtone by default) and 'filename' is the filesystem
#   location of a .wav file.
# - ringdates (optional): lines of `YYYY-MM-DDis` or
#   `YYYY-MM-DD/YYYY-MM-DDis` where `s` is space/empty for No-Bells dates or
#   the alphabetical Special schedule code, and `i` can be empty/space or `+`
#   (means in addition to the Normal schedule, otherwise the Normal schedule is
#   replaced by the Speciak schedule). The double date format is the beginning
#   and end of a date range. There can be multiple Special schedules for the
#   same date, and all get rung, even if that date is also a No-Bells date.
#   All characters after position 12 resp. 23 are ignored as a comment.
# - ringalarms (optional): lines with `Sfilename`, where `S` at the first
#   character is the minimum number of seconds the button needs to be pressed
#   for the .wav alarmtone in `filename` to be played. If `S` is `0` then the
#   tone is played whenever the amplifier is switched on.
# Required: wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay)
#   date [control:tmux] [keyboard:evdev grep sudo coreutils(ls head)]

# Adjustables
relaypin=14 buttonpin=22 ampdelay=3 pollres=.1 shutoffdelay=.5 key=LEFTCTRL
# Constants
ev=10
# Input filenames
ringtimes=ringtimes ringtones=ringtones ringdates=ringdates
ringalarms=ringalarms

Log(){ # $1:message $2:time(optional)
	local datetime
	[[ $2 ]] && datetime=$(date +'%Y-%m-%d %H:%M')
	fold -s <<<"$1 $datetime"
}

Error(){ # $1:message  I:$i $line  IO:$error
	((++error))
	local l
	[[ $i ]] && l="Line $i: '$line' -"
	Log "* $l $1"
}

Ring(){ #I:$now $tonefiles $relaypin $buttonpin $ampdelay $time $shutoffdelay
		# IO:$relayon  $1:schedule
	local sched ringcode wav
	[[ $1 = '_' ]] && sched='Normal schedule' || sched="schedule '$1'"
	ringcode=${ringcodes[$now$1]}
	# Empty ringcode is 0
	[[ $ringcode ]] || ringcode=0
	wav=${tonefiles[$ringcode]}
	# Turn relay on
	gpio -g write $relaypin 0 && relayon=1 ||
		Log "* Turning relay on failed"
	sleep $ampdelay
	# Ring bell
	aplay "$wav" &>/dev/null &&
		Log "- Ring Ringtone $ringcode on $sched at $now" ||
		Log "* Playing $wav at $now failed"
	sleep $shutoffdelay
	# Turn relay off
	gpio -g write $relaypin 1 && relayon=0 ||
		Log "* Turning relay off failed"
}

Button(){ # IO:$relayon $playing $buttonold
		# I:$relaypin $alarmfiles $kbd $ev $buttonpin
	local button buttontime buttonlen len
	if [[ $kbd ]]
	then
		sudo evtest --query $kbd EV_KEY KEY_$key
		(($?==ev)) && button=1 || button=0
	else
		button=$(gpio -g read $buttonpin)
	fi
	if [[ $button = 1 && $buttonold = 0 ]]
	then # Button just pressed
		buttonold=1
		if [[ -z $playing ]]
		then # Nothing playing already
			# Record the time
			buttontime=$(date +'%s')
			# Wait for release of the button
			if [[ $kbd ]]
			then
				while sudo evtest --query $kbd EV_KEY KEY_$key; (($?==ev))
				do :
				done
			else
				gpio edge $buttonpin rising
				gpio -g wfi $buttonpin falling
			fi
			buttonlen=$(($(date +'%s')-buttontime))
			for len in 9 8 7 6 5 4 3 2 1 0
			do
				# Skip non-defined ones
				[[ ${alarmfiles[$len]} ]] || continue
				if ((buttonlen>=len))
				then # Long enough to sound this alarm
					((!relayon)) &&
						gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time
					Log "- ALARM $len: ${alarmfiles[$len]}" time
					aplay -q "${alarmfiles[$len]}" &
					playing=$!
					return # Otherwise lower len will always match
				fi
			done
		fi
		# Just toggle: button just pressed and no alarm was called for
		if ((relayon))
		then
			# Stop the alarm if it is playing
			[[ $playing ]] && kill -9 $playing && wait 2>/dev/null && playing=
			gpio -g write $relaypin 1 && relayon=0 && Log "- Amplifier off" time ||
				Log "* Unable to switch off the relay"
		else
			gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time ||
				Log "* Unable to switch on the relay"
		fi
	else
		buttonold=$button
	fi
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


# Globals
declare -A schedules=() ringcodes=() specialdates=() additional=() muted=()
tonefiles=() kbd= gpio= test=0
nobellsdates= nowold= relayon=0 buttonold=9 playing= errors=0 i= daylogged=0
self=$(readlink -e "$0")
# Read files from the same directory as this script
cd "${self%/*}"
[[ $1 = -t || $1 = --test ]] && test=1

Log "# Ring program initializing" time
Log "> Amplifier switch-on delay ${ampdelay}s,  Button polling ${pollres}s"
# For testing without gpio installed
gpio=$(type -p gpio) || gpio(){ :;}

# Setting up pins
! gpio export $relaypin out &&
	Log "* Setting up relay pin $relaypin for output failed" && exit 2 ||
	Log "> Relay pin $relaypin used for output"
! gpio export $buttonpin in &&
	Log "* Setting up button pin $buttonpin for input failed" ||
	Log "> Button pin $buttonpin used for input"
gpio -g mode $buttonpin down
gpio -g write $relaypin 1 && relayon=0 ||
	Log "* Turning relay off failed"
trap "gpio -g write $relaypin 1; gpio unexportall; Log; Log '# Quit' time" \
		QUIT EXIT

Log "- Validating File information in '$(readlink -f $ringtones)'"
error=0
[[ -f "$ringtones" ]] || Error "No input file '$ringtones'"
mapfile -O 1 -t tones <"$ringtones"
for i in "${!tones[@]}"
do
	line=${tones[$i]} ringcode=${line:0:1} file=${line:1}
	# Skip empty lines and comments
	[[ -z ${line// } || $ringcode = '#' ]] && continue
	[[ $ringcode = [0-9] ]] || Error "Bad ringtone code: '$ringcode' (not 0-9)"
	[[ -f $file ]] || Error "Not a file: '$file'"
	tonefiles[$ringcode]=$file
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringtones"
((errors+=error))

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
			[[ ${s// } ]] && specialdates[$s]+=" $date" || nobellsdates+=" $date"
			[[ $idate = '+' ]] && additional[$s]='+'
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
	[[ $ringcode != '-' && -z ${tonefiles[$ringcode]} ]] &&
		Error "Add a .wav filename preceded by '$ringcode' to $ringtones"
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

Log "- Validating Alarm information in '$(readlink -f $ringalarms)'"
error=0 j=0
[[ -f "$ringalarms" ]] && mapfile -O 1 -t alarms <"$ringalarms"
for i in "${!alarms[@]}"
do
	line=${alarms[$i]}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	l=${line:0:1} file=${line:1}
	[[ $l != [0-9] ]] && Error "Not a number from 0 to 9: '$l'"
	[[ -f $file ]] || Error "Not a file: '$file'"
	[[ ${alarmfiles[$l]} ]] && Error "More than one alarm for $l seconds" ||
		alarmfiles[$l]=$file
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringalarms"
((errors+=error))

# Listing tonefiles
Log "> Tonefiles: ${tonefiles[*]}"

# Listing alarmfiles
for l in ${!alarmfiles[@]}
do
	((l==1)) && s= || s=s
	Log "> Alarmfile $l second$s: ${alarmfiles[$l]//$'\n'/ }"
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
	Log "* Total of $errors error$s, not starting Ring program" && exit 1
Log "> All input files are valid"

[[ $gpio ]] ||
	Log "* Essential package 'wiringpi' (program 'gpio') not installed"

if [[ $1 = -k || $1 = --keyboard ]]
then
	! sudo -v && Log "* Privileges insufficient for using keyboard" && exit 2
	[[ $2 && -c $2 ]] && kbd=$2 || Log "* Invalid keyboard device: $2"
	if [[ -d /dev/input/by-path && -z $kbd ]]
	then
		kbd=$(ls -l /dev/input/by-path |grep kbd |head -1) kbd=${kbd##*/}
		[[ $kbd ]] && kbd=/dev/input/$kbd
	fi
	[[ $kbd ]] && Log "> Use $key on the keyboard instead of the button" ||
		Log "* Using keyboard not possible"
fi

# Main loop
Log "# Ring program starting" time
while :
do
	Button
	Bellcheck
	sleep $pollres
done
