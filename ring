#!/bin/bash
set +v
# ring - Control a school bell system from a Raspberry Pi
# Usage: ring
#   Reads input files 'ringtimes', 'ringtones', 'ringdates' and 'ringalarms'
#   from the same directory as where the 'ring' script resides. These are
#   checked for proper syntax & semantics, and when OK the program starts and
#    keeps running, logging output to stdout.
# Format:
# - Lines with '#' as the first character are skipped as comments.
# - ringtimes: lines with 'HH:MMsR' where 's' is Schedule (Normal schedule is
#     space/empty, and Special schedule codes have an alphabetic character) and
#     'R' is the Ringtone code. If 'R' is space/empty it means it is '0' (the
#     default), a '-' means a mute for that time regardless of other schedules.
#     In general, the 'R' matches the first position of lines with the filename
#     of a .wav sound file in the 'ringtones' file.
#     All characters after position 7 are ignored as a comment.
# - ringtones: lines with 'Rfilename', where 'R' is the numerical Ringtone code #     (0 is the Normal ringtone by default) and 'filename' is the filesystem
#     location of a .wav file.
# - ringdates (optional): lines of 'YYYY-MM-DDis' or 'YYYY-MM-DD/YYYY-MM-DDis'
#     where 's' is space/empty for No-School dates or the alphabetical Special
#     schedule code, and 'i' can be empty/space or '+' (means it is addition to
#     the Normal schedule, otherwise it replaces the Normal schedule).
#     The double date format is the beginning and end of a date range.
#     There can be a single or multiple Special schedules for the same date,
#     and all get rung, even if that date is also a No-School date.
#     All characters after position 12 resp. 23 are ignored as a comment.
# - ringalarms (optional): lines with 'Sfilename', where 'S' at the first
#     character is the minimum number of seconds the button needs to be
#     pressed for the .wav alarmtone in 'filename' to be played. Multiple lines
#     with the same 'S' are played in sequence, with the last one on a loop.
# Workings: Every weekday (except on No-School days) the Normal schedule will
#   ring and additional schedules (with '+' after the date). On dates with a
#   Special schedule without a '+' the Normal schedule will not ring.
# Required: wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay)
#   date [tmux]

# Adjustables
relaypin=14 buttonpin=22 ampdelay=3 pollres=.1 shutoffdelay=.5
# Input filenames
ringtimes=ringtimes ringtones=ringtones ringdates=ringdates
ringalarms=ringalarms

Log(){ # $1:message $2:time(or not)
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

Ring(){ # $1:schedule  I:$tonefiles $relaypin $ampdelay $time  IO:$relayon
	local schedule ringcode wav
	[[ $1 = _ ]] && schedule='Normal schedule' || schedule="schedule '$1'"
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
		Log "- Ring Ringtone $ringcode on $schedule at $now" ||
		Log "* Playing $wav at $now failed"
	sleep $shutoffdelay
	# Turn relay off
	gpio -g write $relaypin 1 && relayon=0 ||
		Log "* Turning relay off failed"
}

Button(){ # IO:$relayon $stop  I:$relaypin $alarmfiles
	local button=$(gpio -g read $buttonpin) buttontime buttonlen s toggle=1
	if [[ -z $stop && $button = 1 && $buttonold = 0 ]]
	then # Button just pressed and nothing playing already
		# Record the time
		buttontime=$(date +%s)
		# Wait for release of the button
		gpio edge 22 rising
		gpio -g wfi 22 falling
		buttonlen=$(($(date +%s)-buttontime))
		for s in 9 8 7 6 5 4 3 2 1 0
		do
			# Skip non-defined ones
			[[ ${alarmfiles[$s]} ]] || continue
			if ((buttonlen>s))
			then # Long enough to sound this alarm
				((!relayon)) &&
					gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time
				Log "- ALARM $s: ${alarmfiles[$s]}!" time
				{
					while :
					do read line
						[[ $line ]] && alarm=$line
						aplay "$alarm" &>/dev/null
					done <<<"${alarmfiles[$s]}"
				} &
				stop=$!
				toggle=0
				break # Don't try the shorter ones as well
			fi
		done
		if ((toggle && relayon))
		then # Just toggle, no alarm was called for
			# Stop the alarm if it is on
			[[ $stop ]] && kill $stop && stop= && killall aplay
			gpio -g write $relaypin 1 && relayon=0 && Log "- Amplifier off" time ||
				Log "* Unable to switch off the relay"
		else
			gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time ||
				Log "* Unable to switch on the relay"
		fi
	fi
	buttonold=$button
}

Bellcheck(){ # I:$noschooldates $specialdates $schedules IO:$nowold
	local now=$(date +'%H:%M') today=$(date +'%Y-%m-%d') skipnormal=0 day s
	# Ignore if this time has been checked earlier
	[[ $now = $nowold ]] && return
	nowold=$now
	[[ $now = 00:00 ]] && daylog=1
	# Check Special schedules
	for s in "${!specialdates[@]}"
	do
		if [[ "${specialdates[$s]} " = *" $today "* ]]
		then
			((daylog)) && daylog=0 && Log "- $today '$s' day:${schedules[$s]}"
			((ringcodes[$now${s:0:1}]==10)) &&
				Log "- $today '$s' skipping:$now" && return
			[[ ${s:1} != + ]] && skipnormal=1
			[[ "${schedules[$s]} " = *" $now "* ]] && Ring ${s:0:1} && return
		fi
	done
	((skipnormal)) && return
	# No-School dates trump Normal days
	[[ "$noschooldates " = *" $today "* ]] && ((daylog)) && daylog=0 &&
		Log "- $today No School day" && return
	# Ignore weekends (days 6 and 7)
	if (($(date '+%u')>5))
	then
		((daylog)) && daylog=0 && Log "- $today $(date +%A)"
		return
	fi
	# Check Normal days
	((!skipnormal && daylog)) && daylog=0 &&
		Log "- $today Normal day:${schedules['_']}"
	[[ "${schedules['_']} " = *" $now "* ]] && Ring _
}


# Globals
declare -A schedules=() ringcodes=() specialdates=()
tonefiles=()
noschooldates= nowold= relayon=0 buttonold=9 stop= errors=0 i= daylog=1
self=$(readlink -e "$0")
# Read files from the same directory as this script
cd "${self%/*}"

Log "# Ring program initializing" time
Log "> Amplifier switch-on delay ${ampdelay}s,  Button polling ${pollres}s"
# for testing without gpio installed
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

Log "> Validating File information in '$(readlink -f $ringtones)'"
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
((error)) && Log "$error error$s in $ringtones"
((errors+=error))

Log "> Validating Date information in '$(readlink -f $ringdates)'"
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
		idate=${line:21:1} schedule=${line:22:1}
		[[ -z ${idate// } || $idate = + ]] ||
			Error "After the dates only space or '+' allowed, not '$idate'"
		[[ ${schedule// } && $schedule != [a-zA-Z] ]] &&
			Error "Schedule should be alphabetic, not '$schedule'"
		[[ ${schedule// } && $idate = '+' ]] && schedule+=+
		while [[ ! $date > $date2 ]]
		do
			[[ $date < $today ]] && continue
			[[ ${schedule// } ]] && specialdates[$schedule]+=" $date" ||
				noschooldates+=" $date"
			date=$(date -d "tomorrow $date" '+%Y-%m-%d')
		done
	else
		[[ -z ${idate// } || $idate = + ]] ||
			Error "After the date only space, '/' or '+' allowed, not '$idate'"
		schedule=${line:11:1}
		[[ ${schedule// } && $schedule != [a-zA-Z] ]] &&
			Error "Schedule should be alphabetic, not '$schedule'"
		[[ $date < $today ]] && continue
		[[ ${schedule// } && $idate = '+' ]] && schedule+=+
		[[ ${schedule// } ]] && specialdates[$schedule]+=" $date" ||
			noschooldates+=" $date"
	fi
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringdates"
((errors+=error))

Log "> Validating Time information in '$(readlink -f $ringtimes)'"
error=0
[[ -f "$ringtimes" ]] || Error "No input file '$ringtimes'"
mapfile -O 1 -t times <"$ringtimes"
for i in "${!times[@]}"
do # Validate and store times
	line=${times[$i]} time=${line:0:5} schedule=${line:5:1} ringcode=${line:6:1}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	date -d "$time" &>/dev/null || Error "Invalid Time: '$time'"
	# Use underscore for the Normal schedule (schedule is empty or space)
	[[ ${schedule// } ]] || schedule='_'
	[[ $schedule = [_a-zA-Z] ]] ||
		Error "Schedule should be alphabetical, not '$schedule'"
	[[ ${ringcode// } ]] || ringcode=0
	[[ $ringcode = [-0-9] ]] ||
		Error "Ringcode should be single digit or '-', not '$ringcode'"
	[[ $ringcode != - && -z ${tonefiles[$ringcode]} ]] &&
		Error "Add a .wav filename preceded by '$ringcode' to $ringtones"
	# Skip if no dates with this schedule and it is not a Normal schedule
	[[ -z ${specialdates[$schedule]} && -z ${specialdates[$schedule+]} &&
			$schedule != _ ]] && continue
	schedules[$schedule]+=" $time"
	[[ $ringcode = - ]] && ringcode=10
	ringcodes[$time$schedule]=$ringcode
done
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringtimes"
((errors+=error))

Log "> Validating Alarm information in '$(readlink -f $ringalarms)'"
error=0 j=0
[[ -f "$ringalarms" ]] && mapfile -O 1 -t alarms <"$ringalarms"
for i in "${!alarms[@]}"
do
	line=${alarms[$i]}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	secs=${line:0:1} file=${line:1}
	[[ $secs != [0-9] ]] && Error "$secs is not a number from 0 to 9"
	[[ -f $file ]] || Error "$file is not a file"
	alarmfiles[$secs]+="$file"$'\n'
done
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringalarms"
((errors+=error))

# Listing tonefiles
Log "> Tonefiles: ${tonefiles[*]}"

# Listing alarmfiles
for l in ${!alarmfiles[@]}
do
	Log "> Alarmfiles $l seconds: ${alarmfiles[$l]//$'\n'/ }"
done

# Listing dates
Log "> No School dates:$noschooldates"
for s in "${!specialdates[@]}"
do Log "> '$s' dates:${specialdates[$s]}"
done

# Listing schedules
for s in "${!schedules[@]}"
do
	[[ $s = _ ]] && scheds='Normal schedule:' || scheds="'$s' schedule:"
	for t in ${schedules[$s]}
	do
		r=${ringcodes[$t$s]}
		case $r in
			10) scheds+=" ${t}-" ;;
			0) scheds+=" $t" ;;
			*) scheds+=" ${t},$r"
		esac
	done
	Log "> $scheds"
done

# Reporting initial checks
((errors==1)) && s= || s=s
((errors)) &&
	Log "* Total of $errors error$s, not starting Ring program" && exit 1 ||
	Log "> All input files are valid"
[[ $gpio ]] ||
	Log "* Essential package 'wiringpi' (program 'gpio') not installed"

# Main loop
Log "# Ring program starting" time
while :
do
	Button
	Bellcheck
	sleep $pollres
done
