#!/bin/bash
set +v
# ring - Controlling a school bell system from a Raspberry Pi
# Usage: ring
#   Reads input files 'ringtimes', 'ringtones', 'ringdates' and 'ringalarms'
#   from the same directory as where the 'ring' script resides. These are
#   checked for proper syntax & semantics, and when OK the program starts and
#    keeps running, logging output to stdout.
# Format:
# - Lines with '#' as the first character are skipped as comments.
# - ringtimes: lines with 'HH:MMsr' (Normal schedule), 'HH:MMs' (Special
#     schedule) or 'HH:MMsr', where 's' is the corresponding Special schedule
#     code (or space for the Normal schedule) and 'r' is the Ringtone code
#     (which refers to a line in the 'ringtones' file that specifies a .wav
#     file). When 'r' is the default '0' code, it can be left out.
# - ringtones: lines with 'filename', where 'filename' is the filesystem
#     location of a .wav file. The file in the first line is referred to by
#     code '0' (the Normal ring tone), the next lines are '1' and up (the
#     maximum is '9').
# - ringdates (optional): lines with 'YYYY-MM-DD' (No School dates) or
#     'YYYY-MM-DD s', where 's' is the alphabetical special Schedule code
#     (uppercase cancels the Normal schedule, lowercase is in addition to the
#      Normal schedule).
# - ringalarms (optional): lines with 'Sfilename', where 'S' at the first
#     character is the minimum number of seconds the button needs to be
#     pressed for the .wav alarmtone in 'filename' to be played.
# Workings: Every weekday the Normal schedule will ring and additional
#   schedules with a lowercase schedule code. On Special dates with an
#   uppercase Schedule code the Normal schedule will not ring.
# Required: wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay)
#   date [tmux]

# Adjustables
relaypin=14 buttonpin=22 ampdelay=3 pollres=.1 shutoffdelay=.5
# Input filenames
ringtimes=ringtimes ringtones=ringtones ringdates=ringdates
ringalarms=ringalarms

Log(){ # $1:message $2:time(or not)
	local datetime
	[[ $2 ]] && datetime="$(date +'%m/%d %H:%M')"
	fold -s <<<"$1 $datetime"
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
		Log "- On $schedule Ringtone $ringcode at $now" ||
		Log "* Playing $wav at $now failed"
	sleep $shutoffdelay
	# Turn relay off
	gpio -g write $relaypin 1 && relayon=0 ||
		Log "* Turning relay off failed"
}

Error(){ # $1:message  I:$i $line  IO:$error
	((++error))
	local l
	[[ $i ]] && l="Line $i: '$line' -"
	Log "* $l $1"
}

Button(){ # IO:$relayon $stop  I:$relaypin $alarmfiles
	local button=$(gpio -g read $buttonpin) buttontime buttonlen i toggle=1
	if [[ $button = 1 && $buttonold = 0 ]]
	then # Button pressed in
		# Record the time
		buttontime=$(date +%s)
		# Wait for release of the button
		gpio edge 22 rising
		gpio -g wfi 22 falling
		buttonlen=$(($(date +%s)-buttontime))
		for i in 9 8 7 6 5 4 3 2 1 0
		do
			# Skip non-defined ones
			[[ -z ${alarmfiles[$i]} ]] && continue
			if ((buttonlen>i))
			then # Long enough to sound this alarm
				((!relayon)) &&
					gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time
				Log "- ALARM $i: ${alarmfiles[$i]}!" time
				while :
				do aplay "${alarmfiles[$i]}" &>/dev/null
				done &
				stop=$!
				toggle=0
				break # Don't try the shorter ones as well
			fi
		done
		if ((toggle && relayon))
		then # Just toggle, no alarm was called for
			# Stop the alarm if it is on
			[[ $stop ]] && kill $stop && killall aplay
			stop=
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
	local now=$(date +'%H:%M') today=$(date +'%Y-%m-%d') nonormal= day i numday
	# Ignore if this time has been checked earlier
	[[ $now = $nowold ]] && return
	nowold=$now
	for day in $noschooldates
	do
		if [[ "$noschooldates " == *" $today "* ]]
		then
			[[ $now = '00:00' ]] && Log "- $today No School day"
			return
		fi
	done
	for i in "${!specialdates[@]}"
	do
		if [[ "${specialdates[$i]} " == *" $today "* ]]
		then
			[[ $now = '00:00' ]] && Log "- $today '$i' day"
			# Block normal day processing on uppercase Schedule code
			[[ $i = ${i^} ]] && nonormal=1 || nonormal=0
			[[ "${schedules[$i]} " == *" $now "* ]] && Ring $i
		fi
	done
	((nonormal)) && return
	# Check Normal days
	numday=$(date '+%u')
	# Ignore weekends (days 6 and 7)
	((numday>5)) && return
	[[ -z $nonormal && $now = '00:00' ]] && Log "- $today Normal day"
	[[ "${schedules['_']} " == *" $now "* ]] && Ring _
}

# Globals
declare -A schedules=() ringcodes=() specialdates=() alarmfiles=()
noschooldates= nowold= relayon=0 buttonold=9 stop= errors=0 i= tonefiles=()
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
[[ ! -f "$ringtones" ]] && Error "No input file '$ringtones'" ||
	mapfile -O 1 -t tones <"$ringtones"
for i in "${!tones[@]}"
do
	line=${tones[$i]}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	[[ ! -f $line ]] && Error "Not a file"
	tonefiles+=($line)
done
((maxcode=${#tonefiles[@]}-1))
((maxcode>9)) && Error "More than 10 files in $ringtones"
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringtones"
((errors+=error))

Log "> Validating Time information in '$(readlink -f $ringtimes)'"
error=0
[[ ! -f "$ringtimes" ]] && Error "No input file '$ringtimes'" ||
	mapfile -O 1 -t times <"$ringtimes"
for i in "${!times[@]}"
do # Validate and store times
	line=${times[$i]} time=${line:0:5} schedule=${line:5:1} ringcode=${line:6:1}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	! date -d "$time" &>/dev/null &&
		Error "Invalid Time: '$time'"
	# Use underscore for the Normal schedule (schedule is empty or space)
	[[ -z $schedule || $schedule = ' ' ]] && schedule='_'
	[[ ! $schedule =~ ^[_a-zA-Z]$ ]] &&
		Error "Schedule should be a upper or lower case letter, not '$schedule'"
	schedules[$schedule]+=" $time"
	[[ $ringcode && ! $ringcode = ' ' ]] || ringcode=0
	[[ ! $ringcode =~ ^[0-9]$ ]] &&
		Error "Ringcode should be single digit number, not '$ringcode'"
	((ringcode>maxcode)) &&
		Error "Add a .wav on line $((ringcode+1)) of file $ringtones"
	# Only store ringcodes that are not 0
	((ringcode)) && ringcodes[$time$schedule]=$ringcode
done
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringtimes"
((errors+=error))

Log "> Validating Date information in '$(readlink -f $ringdates)'"
error=0
[[ -f "$ringdates" ]] && mapfile -O 1 -t dates <"$ringdates" || dates=()
for i in "${!dates[@]}"
do # Validate and split dates
	line=${dates[$i]} date=${line:0:10} empty=${line:10:1} schedule=${line:11:1}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	[[ ! $date =~ ^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$ ]] &&
		Error "Date format should be '20YY-DD-MM'"
	! date -d "$date" &>/dev/null &&
		Error "Invalid Date: '$date'"
	[[ $empty && ! $empty = ' ' ]] &&
		Error "There must be 1 space after the date, not '$empty'"
	[[ $schedule && ! $schedule =~ ^[a-zA-Z]$ ]] &&
		Error "Schedule should be a upper or lower case letter, not '$schedule'"
	[[ $schedule ]] && specialdates[$schedule]+=" $date" ||
		noschooldates+=" $date"
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringdates"
((errors+=error))

Log "> Validating Alarm information in '$(readlink -f $ringalarms)'"
error=0
[[ -f "$ringalarms" ]] && mapfile -O 1 -t alarms <"$ringalarms"
for i in "${!alarms[@]}"
do
	line=${alarms[$i]}
	# Skip empty lines and comments
	[[ -z ${line// } || ${line:0:1} = '#' ]] && continue
	secs=${line:0:1} file=${line:1}
	[[ $secs != [0-9] ]] && Error "$secs is not a number from 0 to 9"
	[[ ! -f $file ]] && Error "$file is not a file"
	[[ ${alarmfiles[$secs]} ]] &&
		Error "Alarm already present for press length $secs" ||
		alarmfiles[$secs]=$file
done
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringalarms"
((errors+=error))

# Listing tonefiles
Log "> Tonefiles: ${tonefiles[*]}"

# Listing alarmfiles
Log "> Alarmfiles:\
$(for i in ${!alarmfiles[*]}; do echo -n " ${i}s:${alarmfiles[$i]}"; done)"

# Listing dates
Log "> No School dates:$noschooldates"
for i in "${!specialdates[@]}"
do Log "> '$i' dates:${specialdates[$i]}"
done

# Listing schedules
for i in "${!schedules[@]}"
do
	[[ $i = _ ]] && s='Normal schedule:' || s="'$i' schedule:"
	for j in ${schedules[$i]}
	do
		c=${ringcodes[$j$i]}
		[[ $c ]] && s+=" ${j}_$c" || s+=" $j"
	done
	Log "> $s"
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
